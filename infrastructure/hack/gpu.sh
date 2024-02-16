#!/bin/bash

set -e

# enable Multi-Process Service GPU partitioning
function enable_mps() {
    # disable gpu
    sudo microk8s disable gpu

    # remove wrong version resoruces (prevents from error in isntalling newer operators)
    kubectl delete crd clusterpolicies.nvidia.com || true
    kubectl delete crd nvidiadrivers.nvidia.com || true

    cat <<EOF > gpu-custom-values.yaml
migManager:
  enabled: false

mig:
  strategy: mixed

toolkit:
  enabled: true
EOF

    # enable new gpu operator through microk8s
    microk8s enable gpu --driver operator --version 22.9.0 --values gpu-custom-values.yaml

    sudo microk8s.status --wait-ready

    # verify the gpu is up
    echo -e "\nCheck nvidia-operator-validator...\n"
    until kubectl logs -n gpu-operator-resources -lapp=nvidia-operator-validator -c nvidia-operator-validator | grep -q "all validations are successful"; do
        sleep 5
    done
    echo -e "Check Passed!\n"

    # worklaod test
    echo -e "Create test workload on GPU...\n"

    kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: cuda-vector-add
spec:
  restartPolicy: OnFailure
  containers:
    - name: cuda-vector-add
      image: "k8s.gcr.io/cuda-vector-add:v0.1"
      resources:
        limits:
          nvidia.com/gpu: 1
EOF

    # verify the gpu is up
    echo -e "Check cuda-vector-add has been completed...\n"
    until kubectl logs cuda-vector-add | grep -q "Test PASSED"; do
        sleep 5
    done
    echo -e "Check Passed!\n"

    kubectl delete pod/cuda-vector-add    

    rm gpu-custom-values.yaml

    # disale nvidia plugin in this node
    kubectl label node arman-gpu nvidia.com/gpu.deploy.driver=false --overwrite

    # enable nebuly plugin in this node
    kubectl label nodes arman-gpu "nos.nebuly.com/gpu-partitioning=mps"

    # ? remove any last history (maybe it should not be removed!)
    # kubectl label node arman-gpu nvidia.com/device-plugin.config- 

    # install nebuly device plugin
    helm install oci://ghcr.io/nebuly-ai/helm-charts/nvidia-device-plugin --wait \
        --version 0.13.0 \
        --generate-name \
        -n nebuly-nvidia \
        --create-namespace

    # install cert manager
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.yaml

    # install nebuly nos
    helm install oci://ghcr.io/nebuly-ai/helm-charts/nos --wait \
        --version 0.1.2 \
        --namespace nebuly-nos \
        --generate-name \
        --create-namespace
}