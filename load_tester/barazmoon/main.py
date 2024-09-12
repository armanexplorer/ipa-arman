import time
from typing import List, Tuple
import numpy as np
from multiprocessing import Process, active_children  # , Lock
import asyncio
from aiohttp import ClientSession
from numpy.random import default_rng
import aiohttp
import asyncio
import subprocess
import grpc
from mlserver.codecs.string import StringRequestCodec
from mlserver.codecs.numpy import NumpyRequestCodec
import mlserver.grpc.dataplane_pb2_grpc as dataplane
import mlserver.grpc.converters as converters


import logging
logger = logging.getLogger(__name__)

def decode_from_bin(
    outputs: List[bytes], shapes: List[List[int]], dtypes: List[str]
) -> List[np.array]:
    batch = []
    for input, shape, dtype in zip(outputs, shapes, dtypes):
        buff = memoryview(input)
        array = np.frombuffer(buff, dtype=dtype).reshape(shape)
        batch.append(array)
    return batch


class Data:
    def __init__(
        self, data, data_shape, custom_parameters={"custom": "custom"}
    ) -> None:
        self.data = data
        self.data_shape = data_shape
        self.custom_parameters = custom_parameters


# from multiprocessing import Queue

# MAX_QUEUE_SIZE = 1000000
# queue = Queue(MAX_QUEUE_SIZE)
# lock = Lock()

# TCP_CONNECTIONS = 500
# connector = TCPConnector(limit=TCP_CONNECTIONS)

TIMEOUT = 20 * 60

# ============= Async + Process based load tester =============

# TODO problems:
# 1. high process load -> not closing finished processes on time
# 2. having a way to save the responses recieved from the load-tester


class BarAzmoonProcess:
    def __init__(
        self, *, workload: List[int], endpoint: str, http_method="get", **kwargs
    ):
        self.endpoint = endpoint
        self.http_method = http_method
        self._workload = (rate for rate in workload)
        self._counter = 0
        self.kwargs = kwargs

    def start(self):
        total_seconds = 0
        for rate in self._workload:
            total_seconds += 1
            self._counter += rate
            generator_process = Process(
                # target=self.target_process, args=(rate, queue, ))
                target=self.target_process,
                args=(
                    rate,
                    total_seconds,
                ),
            )
            generator_process.daemon = True
            generator_process.start()
            active_children()
            time.sleep(1)
        # print(f"{len(active_children())}=")
        print("Spawned all the processes. Waiting to finish...")
        for p in active_children():
            p.join()

        print(f"total seconds: {total_seconds}")

        return self._counter, total_seconds

    # def target_process(self, count, queue):
    def target_process(self, count, second):
        asyncio.run(
            self.generate_load_for_second(
                count,
            )
        )
        responses = asyncio.run(
            self.generate_load_for_second(
                count,
            )
        )
        print("-" * 50)
        print(f"{second=}")
        for response in responses:
            print(response)
        # for response in responses:
        #     queue.put(response)
        print()

    async def generate_load_for_second(self, count):
        # timeout = ClientTimeout(total=TIMEOUT)
        # async with ClientSession(timeout=timeout) as session:
        async with ClientSession() as session:
            delays = np.cumsum(np.random.exponential(1 / (count * 1.5), count))
            tasks = []
            for i in range(count):
                task = asyncio.ensure_future(self.predict(delays[i], session))
                tasks.append(task)
            return await asyncio.gather(*tasks)

    async def predict(self, delay, session):
        await asyncio.sleep(delay)
        data_id, data = self.get_request_data()
        async with getattr(session, self.http_method)(
            self.endpoint, data=data
        ) as response:
            # print('-'*25, 'request sent!', '-'*25)
            response = await response.json(content_type=None)
            # lock.acquire()
            # queue.put(response)
            # lock.release()
            # print('')
            # self.process_response(data_id, response)
            return response

    def get_request_data(self) -> Tuple[str, str]:
        return None, None

    def process_response(self, data_id: str, response: dict):
        pass

    # def get_responses(self):
    #     outputs = [queue.get() for _ in range(queue.qsize())]
    #     return outputs


# ============= Pure Async Rest based load tester =============


async def request_after_rest(session, url, wait, payload):
    if wait:
        await asyncio.sleep(wait)
    sending_time = time.time()
    try:
        async with session.post(url, data=payload, timeout=TIMEOUT) as resp:
            if resp.status != 200:
                resp = {"failed": await resp.text()}  # TODO: maybe raise!
            else:
                resp = await resp.json()
            arrival_time = time.time()
            timing = {
                "time": {"sending_time": sending_time, "arrival_time": arrival_time}
            }
            resp.update(timing)
            return resp
    except asyncio.exceptions.TimeoutError:
        resp = {"failed": "timeout"}
        arrival_time = time.time()
        timing = {"time": {"sending_time": sending_time, "arrival_time": arrival_time}}
        resp.update(timing)
        return resp


class BarAzmoonAsyncRest:
    def __init__(self, endpoint, payload, mode, benchmark_duration=1):
        """
        endpoint:
            the http path the load testing endpoint
        payload:
            data to the be sent
        """
        self.endpoint = endpoint
        self.payload = payload
        self.session = aiohttp.ClientSession()
        self.responses = []
        self.duration = benchmark_duration
        self.mode = mode

    async def benchmark(self, request_counts):
        tasks = []
        for i, req_count in enumerate(request_counts):
            tasks.append(
                asyncio.ensure_future(
                    self.submit_requests_after(
                        i * self.duration, req_count, self.duration
                    )
                )
            )
        await asyncio.gather(*tasks)

    async def submit_requests_after(self, after, req_count, duration):
        if after:
            await asyncio.sleep(after)
        tasks = []
        beta = duration / req_count
        start = time.time()

        rng = default_rng()
        if self.mode == "step":
            arrival = np.zeros(req_count)
        elif self.mode == "equal":
            arrival = np.arange(req_count) * beta
        elif self.mode == "exponential":
            arrival = rng.exponential(beta, req_count)
        print(
            f"Sending {req_count} requests sent in {time.ctime()} at timestep {after}"
        )
        for i in range(req_count):
            tasks.append(
                asyncio.ensure_future(
                    request_after_rest(
                        self.session,
                        self.endpoint,
                        wait=arrival[i],
                        payload=self.payload,
                    )
                )
            )
        resps = await asyncio.gather(*tasks)

        elapsed = time.time() - start
        if elapsed < duration:
            await asyncio.sleep(duration - elapsed)

        self.responses.append(resps)
        print(
            f"Recieving {len(resps)} requests sent in {time.ctime()} at timestep {after}"
        )

    async def close(self):
        await self.session.close()


# ============= Pure Async Grpc based load tester =============


async def request_after_grpc(stub: dataplane.GRPCInferenceServiceStub, metadata, wait, payload):
    if wait:
        await asyncio.sleep(wait)
        
    # clock
    sending_time = time.time()
    
    # initiate response
    times = {}
    resp = {'times': times}
    
    try:
        # grpc call
        grpc_resp = await stub.ModelInfer(request=payload, metadata=metadata)
        
        # clock
        arrival_time = time.time()
        
        # convert grpc response to readable one
        inference_response = converters.ModelInferResponseConverter.to_types(grpc_resp)
        
        # type of inference
        type_of = inference_response.parameters.type_of
        
        # extract output based on datatype
        if type_of == "image":
            for request_output in inference_response.outputs:
                dtypes = request_output.parameters.dtype
                shapes = request_output.parameters.datashape
                output_data = request_output.data.__root__
                shapes = eval(shapes)
                dtypes = eval(dtypes)
                X = decode_from_bin(outputs=output_data, shapes=shapes, dtypes=dtypes)
                outputs = {"data": X}
        elif type_of == "text":
            raw_json = StringRequestCodec.decode_response(inference_response)
            outputs = {"data": raw_json}
        elif type_of == "int":
            numpy_output = NumpyRequestCodec.decode_response(inference_response)
            outputs = {"data": numpy_output}

        # extract timestamps
        times["request"] = {"sending": sending_time, "arrival": arrival_time}
        resp["model_name"] = grpc_resp.model_name
        
         # handling drops
        inf_times = getattr(inference_response.outputs[0].parameters, 'times', None)
        if inf_times:
            times["models"] = eval(eval(inf_times)[0])
            resp["outputs"] = [outputs]
        else:
            drop_message = NumpyRequestCodec.decode_response(inference_response)[0]
            resp = {"failed": drop_message}        
    except asyncio.exceptions.TimeoutError:
        resp["failed"] = "timeout"
        times["request"] = {"sending": sending_time, "arrival": arrival_time}
    except grpc.RpcError as e:
        resp["failed"] = str(e)
        if 'arrival_time' in locals():
            times["request"] = {"sending": sending_time, "arrival": arrival_time}
        else:
            times["request"] = {"sending": sending_time}
    
    return resp


class BarAzmoonAsyncGrpc:
    def __init__(
        self,
        endpoint: str,
        metadata: str,
        payloads: List[Data],
        mode: str,
        benchmark_duration=1,
    ):
        """
        endpoint:
            the path the load testing endpoint
        payload:
            data to the be sent
        """
        self.endpoint = endpoint
        self.payloads = payloads
        self.metadata = metadata
        self.responses = []
        self.mode = mode
        self.duration = benchmark_duration
        self.request_index = 0
        self.stop_flag = False
        self.gpu_utilizations = []
        self.stub: dataplane.GRPCInferenceServiceStub = None

    # def stop(self):
    #     self.stop_flag = True

    async def benchmark(self, request_counts):
        async with grpc.aio.insecure_channel(
                self.endpoint,
                options=(
                    ('grpc.keepalive_time_ms', 180000),
                    ('grpc.keepalive_permit_without_calls', True),
                )
            ) as ch:
            self.stub = dataplane.GRPCInferenceServiceStub(ch)
            tasks = []
            
            # create multiple async benchmarks according to the number of 
            # workload elements
            request_counts = list(request_counts)
            # logger.debug("\n\n" + "-" * 25 + f"PARAMS AGAIN" + "-" * 25 + "\n")
            # logger.debug(self.duration)
            # logger.debug(request_counts)
            # logger.debug("\n\n")
            
            for i, req_count in enumerate(request_counts):
                tasks.append(
                    asyncio.ensure_future(
                        self.submit_requests_after(
                            i * self.duration, req_count, self.duration
                        )
                    )
                )
                tasks.append(
                    asyncio.ensure_future(
                        self.get_gpu_utilization(i*self.duration)
                    )
                )
            await asyncio.gather(*tasks)

    async def submit_requests_after(self, after, req_count, duration):
        """
        send current benchmark requests according to the mode of distribution.
        starts to send requests after `after` seconds.
        """
        
        if after:
            await asyncio.sleep(after)
        
        # time between each request
        beta = duration / req_count
        
        # determine the distbirbution of requests arrival times in current benchmark
        if self.mode == "step":
            arrival = np.zeros(req_count)
        elif self.mode == "equal":
            arrival = np.arange(req_count) * beta
        elif self.mode == "exponential":
            rng = default_rng()
            arrival = rng.exponential(beta, req_count)  # beta is average time between reqs 
        else:
            raise Exception("You should set mode to `step`, `equal`, or `exponential`")
        
        tasks = []
        start = time.time()
        
        logger.info(f"Start to send {req_count} requests at timestep {after}")
        
        # send each request according to the arrivals distribution in the benchmark
        # duration (1 sec)

        data_len = len(self.payloads)
        # logger.debug("CREATE ASYNC REQUESTS...")
        for i in range(req_count):
            data_index = self.request_index % data_len
                            
            # break if the stop flag has been set
            if self.stop_flag:
                break
            
            # create async requests
            tasks.append(
                asyncio.ensure_future(
                    request_after_grpc(
                        self.stub,
                        self.metadata,
                        wait=arrival[i],
                        payload=self.payloads[data_index],
                    )
                )
            )
            self.request_index += 1
        # logger.debug("Requests created!")
            
        # if self.stop_flag:
        #     # Cancel all remaining tasks if the stop flag is set
        #     for task in tasks:
        #         task.cancel()
        #     return []

        # logger.debug("AWAIT FOR RESPONSES")
        # wait untill all requests in this benchmark resolve, in the order they sent
        resps = await asyncio.gather(*tasks)
        # logger.debug("Responses Received!")

        # wait until the duration complete (maybe only for better logging?!)
        elapsed = time.time() - start
        if elapsed < duration:
            await asyncio.sleep(duration - elapsed)

        # store responses in current object to be accessible for other methods
        self.responses.append(resps)
        
        # report success rate of this benchmark
        total = len(resps)
        success = len([1 for resp in resps if "failed" not in resp.keys()])
        
        logger.info(f"Finished receiving {total} requests at timestep {after}")
        logger.info(f"success rate: {success}/{total}")
        
        return resps

    async def get_gpu_utilization(self, do_after):
        await asyncio.sleep(do_after+0.01)
        process = subprocess.Popen(['nvidia-smi', '--query-gpu=utilization.gpu', '--format=csv,noheader,nounits'],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, _ = process.communicate()
        percent = int(out.decode('utf-8').strip())
        self.gpu_utilizations.append(percent)