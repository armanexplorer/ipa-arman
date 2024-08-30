#!/bin/bash

set -e

# Install Google Cloud SDK
function install_gcloud() {
  echo "Installing Google Cloud SDK"
  sudo apt-get install -y apt-transport-https ca-certificates gnupg curl sudo
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
  sudo apt-get update && sudo apt-get install google-cloud-cli
  echo "Google Cloud SDK installation complete"
  echo
}

# Install Helm
function install_helm() {
  echo "Installing Helm"
  wget https://get.helm.sh/helm-v3.11.3-linux-amd64.tar.gz -O helm.tar.gz
  tar -xf helm.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm helm.tar.gz
  rm -r linux-amd64
  echo "Helm installation complete"
  echo
}

# Install MicroK8s
function install_microk8s() {
  echo "Installing MicroK8s"

  sudo snap install microk8s --classic --channel=1.23/edge

  sudo usermod -a -G microk8s $USER
  mkdir -p $HOME/.kube
  sudo chown -f -R $USER ~/.kube
  sudo microk8s config >$HOME/.kube/config
  
  # prevent warnings of group and world read on kube config file
  chmod go-r ~/.kube/config

  # check microk8s is ready
  sudo microk8s.status --wait-ready

  # firewall configs (TODO: possible deprecation)
  command -v ufw && sudo ufw allow in on cni0
  command -v ufw && sudo ufw allow out on cni0
  command -v ufw && sudo ufw default allow routed

  # only works for Ubuntu20.04
  sudo iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited || true

  # might be needed to run this for INPUT chain too
  # sudo iptables -D INPUT -j REJECT --reject-with icmp-host-prohibited || true

  sudo microk8s enable dns
  echo "MicroK8s installation complete"
  echo
}

function install_kubectl() {
  echo "Install kubectl"
  curl -LO https://dl.k8s.io/release/v1.23.2/bin/linux/amd64/kubectl
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

  # ? update config after installing kubectl
  sudo microk8s config >$HOME/.kube/config
  
  command -v ufw && sudo ufw allow 16443
  command -v ufw && (echo "y" | sudo ufw enable)
  echo "alias k='kubectl'" >>~/.zshrc
  rm kubectl
  echo "End Install kubectl"
}

install_gcloud
install_helm
install_microk8s
install_kubectl

# if there is gpu on node, enable it
# command -v nvidia-smi && enable_gpu
