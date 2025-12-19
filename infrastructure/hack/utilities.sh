#!/bin/bash

set -e

function install_istio() {
  echo "Install Istio"
  sudo microk8s enable community || true
  sudo microk8s enable istio || true

  # make sure the addon has settled up
  sudo microk8s status --wait-ready 1>/dev/null

  # apply prometheus and kiali yamls
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.13/samples/addons/prometheus.yaml
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.13/samples/addons/kiali.yaml

  # make sure the added pods are up
  sleep 5
  kubectl wait --for=condition=Ready --timeout=5m pods --all -n istio-system

  echo "End Install Istio"
  echo
}

function install_seldon_core() {
  echo "Install Seldon Core"
  kubectl create namespace seldon-system
  helm install seldon-core seldon-core-operator \
    --repo https://storage.googleapis.com/seldon-charts \
    --set usageMetrics.enabled=true \
    --set istio.enabled=true \
    --namespace seldon-system

  cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: seldon-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
EOF

  kubectl patch svc istio-ingressgateway -n istio-system --patch '{"spec": {"ports": [{"name": "http2", "nodePort": 32000, "port": 80, "protocol": "TCP", "targetPort": 8080}]}}'
  echo "End Install Seldon Core"
  echo
}

function configure_monitoring() {
  echo "Configure monitoring"

  # enable operator in microk8s
  sudo microk8s enable prometheus || true
  sudo microk8s status --wait-ready 1>/dev/null || true

  cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: seldon-podmonitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/managed-by: seldon-core
  podMetricsEndpoints:
    - port: metrics
      interval: 1s
      path: /prometheus
  namespaceSelector:
    any: true
EOF

  kubectl apply -f ~/ipa/infrastructure/istio-monitoring.yaml

  # make sure the added pods are up
  echo "Check the monitoring pods are up..."
  
  # Wait for pods to be created
  while [[ $(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l) -eq 0 ]]; do
    echo "Waiting for pods to be created in monitoring namespace..."
    sleep 2
  done

  kubectl wait --for=condition=Ready --timeout=5m pods --all -n monitoring
  echo -e "Check Passed!\n"

  kubectl patch svc prometheus-k8s -n monitoring --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"}]'
  kubectl patch svc grafana -n monitoring --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"}]'
  kubectl patch svc prometheus-k8s -n monitoring --patch '{"spec": {"type": "NodePort", "ports": [{"port": 9090, "nodePort": 30090}]}}'
  kubectl patch svc grafana -n monitoring --patch '{"spec": {"type": "NodePort", "ports": [{"port": 3000, "nodePort": 30300}]}}'

  # apply kiali and jaeger
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.13/samples/addons/kiali.yaml
  kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.13/samples/addons/jaeger.yaml

  # make sure the added pods are up
  echo "Check the istio-system pods are up..."
  sleep 5
  kubectl wait --for=condition=Ready --timeout=5m pods --all -n istio-system
  echo -e "Check Passed!\n"

  echo "End Configure monitoring"
  echo
}

function install_docker() {
  echo "Try to remove old dockers"
  sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
  echo "Install Docker (configure Docker apt repository and install packages)"
  sudo apt-get update -y || true
  sudo apt-get install -y ca-certificates curl gnupg lsb-release || true

  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  UBUNTU_CODENAME=$(lsb_release -cs || echo focal)
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y

  # Install Docker packages (omit docker-model-plugin which may not exist on older distros)
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin docker-ce-rootless-extras || true
  sudo groupadd docker || true
  sudo usermod -aG docker $USER
  sudo systemctl enable docker.service
  sudo systemctl enable containerd.service
  echo "Docker install step finished"
  echo "End Install Docker"
  echo
}

install_istio
install_seldon_core
configure_monitoring
install_docker
