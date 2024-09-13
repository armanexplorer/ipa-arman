# Docs and Debugs

## Inference with GPU (Nebuly-nos)

Components:

- operator
- gpu-partitioner
- scheduler
- mig-agent
- gpu-agent

### scheduler

### `CSIStorageCapacity` error

```bash
# get scheduler pod resource (to check image tag version)
kubectl get pod nos-1725004658-scheduler-cfb54db75-nfpnz -n nebuly-nos -o yaml
```

```log
pkg/mod/k8s.io/client-go@v0.25.4/tools/cache/reflector.go:169: Failed to watch *v1.CSIStorageCapacity: failed to list *v1.CSIStorageCapacity: the server could not find the requested resource
```

We have a problem with ``CSIStorageCapacity`` resource in the 0.2.1 version of Nubely-nos, because it depends on kubernetes 1.25.4. Specifically, it uses the
`k8s.io/client-go v0.25.4` package ([Link](https://github.com/kubernetes/client-go)), which needs the `storage.k8s.io/v1` api resource for using `CSIStorageCapacity`, while it is for Kubernetes 1.24 and up, and we have only `storage.k8s.io/v1beta1` api resource.

The solutions are:

- upgrade Kubernetes version and use 1.24.
- change the `mod.go` of the nebuly-nos ([link](https://github.com/nebuly-ai/nos/blob/main/go.mod)) to use 0.23 versions instead of 0.25, specially for `client-go` and build the image and use that image address and tag in the Helm Values
- change the scheduler tag Helm Value to use some which uses the 0.23 or older version of `client-go` library.

[Helm Values](https://github.com/nebuly-ai/nos/tree/main/helm-charts/nos)

### GPU Partitioner

- The GPU Partitioner component watches for pending pods that cannot be scheduled due to lack of MIG/MPS resources they request. If it finds such pods, it checks the current partitioning state of the GPUs in the cluster and tries to find a new partitioning state that would allow to schedule them without deleting any of the used resources.
- processes pending pods in batches when deciding GPU partitioning plan
- uses an internal k8s scheduler to simulate the scheduling of the pending pods to find a plan
  - reads the scheduler `ConfigMap` defined by `gpuPartitioner.scheduler.config`

```bash
kubectl logs -n nebuly-nos -l app.kubernetes.io/name=nos-gpu-partitioner -f
```

### Nvidia k8s-device-plugin

- The creation and deletion of MPS resources is handled by the k8s-device-plugin
- can expose a single GPU as multiple MPS resources
- takes care of injecting the `environment variables` and `mounting the volumes` required by the container to communicate to the `MPS server`
- making sure that the resource limits defined by the device requested by the `container` are enforced.

```bash
# throw warning to select the container [nvidia-device-plugin-sidecar nvidia-mps-server nvidia-device-plugin-ctr]
kubectl logs -n nebuly-nvidia -l app.kubernetes.io/name=nebuly-nvidia-device-plugin -f

# gpu MPS main logs
kubectl logs -f pod/nvidia-device-plugin-1725004645-zct6t -n nebuly-nvidia --all-containers --max-log-requests=6
```

### log of models

```bash
# get the full logs of the containers in inside the pod
kubectl logs -f pod/yolo-yolo-0-yolo-585b5469c7-9jsnr --all-containers

# watch on logs (important when the log changes)
watch kubectl logs pod/yolo-yolo-0-yolo-78fbc5fbdb-s45jw  --all-containers

# get logs of a special container
kubectl logs pod/yolo-yolo-0-yolo-69d5c75957-59ttj -c classifier-model-initializer
```

### log of node (allocations)

```bash
kubectl describe node $(hostname) | tail -n 20

# get the total memory label applied by the NVIDIA GPU Operator (being used by GPU Partitioner to check allocation request fits)
kubectl describe node $(hostname) | grep "nvidia.com/gpu.memory"
```

### check the container GPU VRAM limitation

With MPS, the `CUDA_MPS_PINNED_DEVICE_MEM_LIMIT` will be set in each container which requests GPU

```bash
kubectl exec -it yolo-yolo-0-yolo-596f59bbd6-fw7ng -c yolo bash
env | grep -i CUDA

# example of the output when we set one 2gb GPU for this container 
CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=2G
CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
```

### test without running model-iter

```py
  check_load_test('video', 'image', '/home/cc/ipa-private/pipelines/mlserver-final/video/seldon-core-version/nodes/yolo', 'yolo')
```

### about GPU we used

`lscpu` -> Intel(R) Xeon(R) Gold 6126 CPU @ 2.60GHz
`lspci -v | grep -A 10 VGA` + `nvidia-smi` -> Quadro RTX 6000
Quadro RTX 6000, 24212MiB
Quadro RTX 6000, 24GB -> $0.50 / hour
Google Custom machine type (2vCPU + 8GB Ram ~= n1-standard-2) -> $0.1 / hour

Key features and specifications of the Quadro RTX 6000:

- Architecture: Turing
- CUDA Cores: 4,608
- Ray Tracing Cores: 576
- Tensor Cores: 144
- Memory: 24 GB GDDR6
- Memory Bus Width: 384-bit
- Clock Speeds: Base Clock: 1.35 GHz, Boost Clock: 1.62 GHz
- Power Consumption: 225W

Fri Aug 30 07:34:28 2024
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 550.54.15              Driver Version: 550.54.15      CUDA Version: 12.4     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  Quadro RTX 6000                Off |   00000000:3B:00.0 Off |                  Off |
| 33%   25C    P8             16W /  260W |       0MiB /  24576MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI        PID   Type   Process name                              GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|  No running processes found                                                             |
+-----------------------------------------------------------------------------------------+

### storage

## Use NFS for Persistent Volumes on MicroK8s

[Docs](https://microk8s.io/docs/how-to-nfs)

```bash

# watch pods in a namespace with a selector
kubectl --namespace=kube-system get pods --selector="app.kubernetes.io/instance=csi-driver-nfs" --watch

# check the current nfs mounts
mount | grep nfs

# check nfs controller and node logs
microk8s kubectl logs --selector app=csi-nfs-controller -n kube-system -c nfs
microk8s kubectl logs --selector app=csi-nfs-node -n kube-system -c nfs
```

## Minio

**1. Create a Kubernetes Service:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: minio
spec:
  selector:
    app: minio
  ports:
    - protocol: TCP
      port: 9000
      targetPort: 9000
```

- **`apiVersion`:** Specifies the API version of the Kubernetes object.
- **`kind`:** Defines the type of object, which is a `Service` in this case.
- **`metadata`:** Contains metadata about the service, including its name.
- **`spec`:** Defines the desired state of the service.
  - **`selector`:** Matches pods with the specified label. In this example, pods with the label `app: minio` will be part of the service.
  - **`ports`:** Defines the ports exposed by the service.
    - **`protocol`:** The protocol used for communication (TCP in this case).
    - **`port`:** The port on which the service will be accessible within the cluster.
    - **`targetPort`:** The port on which the pods are listening.

**2. Deploy the Minio Service:**

```bash
kubectl apply -f minio-service.yaml
```

This will create a Kubernetes service named `minio` that exposes port 9000 to other pods within the cluster.

**3. Access the Minio Service from Other Pods:**

To access the Minio service from other pods, you can use the service's DNS name, which is typically `<service-name>.<namespace>.svc`. In this case, it would be `minio.default.svc`.

For example, if you have another pod running a container that needs to access Minio, you can use the following command to connect to the Minio service:

```bash
minio --address minio.default.svc:9000
```

Replace `minio.default.svc` with the actual DNS name of your service if your namespace is different.

**Additional Considerations:**

- If you need to expose the Minio service to the outside world, you can create a NodePort or LoadBalancer service instead of a ClusterIP service.
- For more advanced scenarios, you might consider using Ingress controllers to manage external access to the Minio service.

By following these steps, you should be able to successfully expose your Minio service on a port that other pods in your microk8s cluster can access.

## Seldon config

```bash
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: seldon-rclone-secret
type: Opaque
stringData:
  RCLONE_CONFIG_S3_TYPE: s3
  RCLONE_CONFIG_S3_PROVIDER: Minio
  RCLONE_CONFIG_S3_ENV_AUTH: "false"
  RCLONE_CONFIG_S3_ACCESS_KEY_ID: minioadmin
  RCLONE_CONFIG_S3_SECRET_ACCESS_KEY: minioadmin
  RCLONE_CONFIG_S3_ENDPOINT: http://minio.minio-system:9000
EOF
```

## Firewall

To watch system logs in Ubuntu 20.04 and identify dropped traffic, you can use a combination of tools and commands. Here's how to monitor your system logs effectively:

1. Use journalctl to view systemd journal logs:

```bash
sudo journalctl -f
```

This command will show you real-time logs from all services managed by systemd[1].

2. To specifically watch for network-related issues, use:

```bash
sudo journalctl -f | grep -i "drop\|reject\|deny"
```

This will filter the logs for entries containing "drop", "reject", or "deny" [case-insensitive](2).

3. Monitor the syslog file directly:

```bash
sudo tail -f /var/log/syslog | grep -i "drop\|reject\|deny"
```

This command will show you the last few lines of the syslog file and update in real-time, filtering for network-related issues[3].

4. Check the kernel ring buffer for network-related messages:

```bash
sudo dmesg -w | grep -i "drop\|reject\|deny"
```

This will display kernel messages in real-time, filtered for network issues[4].

5. If you're using UFW (Uncomplicated Firewall), you can check its logs:

```bash
sudo tail -f /var/log/ufw.log
```

This will show you the most recent UFW log entries and update in real-time[5].

6. To monitor iptables drops in real-time:

```bash
sudo iptables -I INPUT 1 -j LOG --log-prefix "IPTables-Dropped: "
sudo tail -f /var/log/syslog | grep "IPTables-Dropped"
```

This will add a logging rule to iptables and then monitor the syslog for those entries[6].

Remember to remove the logging rule when you're done:

```bash
sudo iptables -D INPUT -j LOG --log-prefix "IPTables-Dropped: "
```

## kubectl commands

```bash
# get resources in all namespaces (--all-namespaces -A)
kubectl get pods -A 

# get network resources and logs
kubectl get networkpolicies -A
kubectl get felixconfiguration default -o yaml
kubectl logs -n kube-system -l k8s-app=calico-node
kubectl get svc -n kube-system kube-dns
kubectl get pods -n kube-system | grep coredns

# edit coredns configmap
kubectl -n kube-system edit configmap/coredns

# check firewall logs
sudo journalctl -n 100 -f

# find not good pods
bad_pods_num=$(kubectl get pods --all-namespaces | grep -v "Completed" | grep -v "Running" | grep -v "NAME" | wc -l)

if [ $bad_pods_num -eq 0 ]; then
  echo "All pods are in Completed or Running state."
else
  echo "There are pods not in Completed or Running state."
fi

# troubleshooting DNS problems

# First Method
kubectl run -it --rm debug --image=busybox -- nslookup google.com

# Second Method
cat <<EOF | k apply -f -                                                        
apiVersion: v1
kind: Pod
metadata:
  name: dnsutils
  namespace: default
spec:
  containers:
  - name: dnsutils
    image: gcr.io/kubernetes-e2e-test-images/dnsutils:1.3
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
EOF

kubectl exec dnsutils -it -- nslookup google.com 
```

## Helm

```bash
helm list -n <namespace>

helm get values <release-name> -n <namespace>

# using file
helm upgrade <release-name> <chart> --reuse-values -f new-values.yaml -n <namespace>

# using command line options
helm upgrade <release-name> <chart> --reuse-values --set key1=newvalue1 -n <namespace>

# NOTE: if you not use --reuse-values, this will happen:
# Values specified in new-values.yaml will override the corresponding values in the chart's default values.yaml.
# Values not specified in new-values.yaml will revert to the chart's default values, not the current release values.
# The chart's default values (from its values.yaml file) will be used for any settings not explicitly overridden.

# you can also use multiple files (In this case, values in new-values.yaml will override those in current-values.yaml.)
helm upgrade <release-name> <chart> -f current-values.yaml -f new-values.yaml

# Use before and after the upgrade to compare the actual Kubernetes manifests that will be applied.
helm get manifest <release-name>
```

## mlserver

### `connection rest by peer` error

```log
grpc_status:14, grpc_message:"recvmsg:Connection reset by peer"
```

[Link1](https://stackoverflow.com/questions/75143542/connection-reset-by-peer-in-python-grpc)
[Link2](https://github.com/grpc/grpc/issues/19514)

## volumesnapshotcontents and volumesnapshotclasses not found error in csi-nfs-controller

```bash
# check logs
k logs -f csi-nfs-controller-5cbd9c4656-x86d2 -n kube-system --all-containers
```

```log
failed to list *v1.VolumeSnapshotContent: the server could not find the requested resource (get volumesnapshotcontents.snapshot.storage.k8s.io) 
failed to list *v1.VolumeSnapshotClass: the server could not find the requested resource (get volumesnapshotclasses.snapshot.storage.k8s.io)
```

### SOLUTION

```bash
# install CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.0.1/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.0.1/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.0.1/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# Install the Snapshot Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.0.1/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v6.0.1/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml
```

## AMAZON EC2 Prices

[Link](https://aws.amazon.com/ec2/)

## kubernetes api-resources docs

[Link](https://www.pulumi.com/registry/packages/kubernetes/api-docs/)
