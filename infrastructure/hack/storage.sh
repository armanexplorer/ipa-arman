#!/bin/bash

# https://microk8s.io/docs/how-to-nfs

set -e

PRIVATEIP=$(hostname -I | cut -d' ' -f1)
PUBLIC_IP="$1" && [ ! "$PUBLIC_IP" ] && PUBLIC_IP=$(curl -s ipinfo.io | jq -r '.ip')

function setup_storage() {
  echo "Setup storage: Install NFS"
  
  sudo apt install -y nfs-kernel-server
  
  sudo mkdir /mnt/myshareddir
  sudo chown nobody:nogroup /mnt/myshareddir
  sudo chmod 777 /mnt/myshareddir
  
  sudo cp /etc/exports /etc/exports.bak
  echo "/mnt/myshareddir $PRIVATEIP/30(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
  sudo exportfs -a
  
  sudo systemctl restart nfs-kernel-server
  echo "Setup storage: End Install NFS"
  echo

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nfs
  namespace: default
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 200Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: $PRIVATEIP
    path: "/mnt/myshareddir"
EOF

  kubectl create ns minio-system
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-nfs
  namespace: minio-system
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
EOF

  MINIOUSER=minioadmin
  MINIOPASSWORD=minioadmin

  helm repo add minio https://charts.min.io/

  helm upgrade --install minio minio/minio --wait \
    --namespace minio-system \
    --set rootUser=${MINIOUSER} \
    --set rootPassword=${MINIOPASSWORD} \
    --set mode=standalone \
    --set persistence.enabled=true \
    --set persistence.existingClaim=pvc-nfs \
    --set persistence.storageClass=- \
    --set replicas=1

  # make sure the added pods are up
  kubectl wait --for=condition=ready pod -l app=minio -n minio-system
  # until kubectl get pods -l app=minio-job -n minio-system --field-selector=status.phase==Succeeded -o \
  #   'jsonpath={.items[*].status.phase}' | grep -qE 'Succeeded'; do
  #   sleep 5
  # done

  kubectl patch svc minio -n minio-system --type='json' -p '[{"op":"replace","path":"/spec/type","value":"LoadBalancer"}]'
  kubectl patch svc minio -n minio-system --patch '{"spec": {"type": "LoadBalancer", "ports": [{"port": 9000, "nodePort": 31900}]}}'

  ACCESS_KEY=$(kubectl get secret minio -n minio-system -o jsonpath="{.data.rootUser}" | base64 --decode)
  SECRET_KEY=$(kubectl get secret minio -n minio-system -o jsonpath="{.data.rootPassword}" | base64 --decode)

  wget https://dl.min.io/client/mc/release/linux-amd64/mc
  chmod +x mc
  sudo cp mc /usr/local/bin
  mc alias set minio http://localhost:31900 "$ACCESS_KEY" "$SECRET_KEY" --api s3v4
  mc ls minio

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
  RCLONE_CONFIG_S3_ENDPOINT: http://$PUBLIC_IP:31900
EOF
  rm mc
  echo "End Setup storage"
  echo
}

function setup_nfs_for_microk8s() {
  echo "Setup NFS for Microk8s..."

  sudo apt install -y nfs-kernel-server
  sudo mkdir -p /srv/nfs
  sudo chown nobody:nogroup /srv/nfs
  sudo chmod 0777 /srv/nfs

  sudo cp /etc/exports /etc/exports.bak
  echo "/srv/nfs $PRIVATEIP/30(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
  sudo exportfs -a

  sudo systemctl restart nfs-kernel-server

  echo "End Setup NSF for microk8s"
  echo
}

function install_csi_driver_for_nfs() {
  echo "Install CSI driver for NFS..."

  microk8s enable helm3
  microk8s helm3 repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
  microk8s helm3 repo update
  
  microk8s helm3 install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
    --namespace kube-system \
    --set kubeletDir=/var/snap/microk8s/common/var/lib/kubelet

  microk8s kubectl wait pod --selector app.kubernetes.io/name=csi-driver-nfs --for condition=ready --namespace kube-system

  microk8s kubectl get csidrivers

  echo "End Install CSI driver for NFS"
  echo
}

function create_sc_and_pvc() {
  echo "Create StoraceClass and PersistantVolumeClaim..."

  # you should nfsvers accordindg to the outuput of ``mount | grep nfs`` and in ``vers`` param
  cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: $PRIVATEIP
  share: /srv/nfs
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - hard
  - nfsvers=4.2
EOF

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  storageClassName: nfs-csi
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
EOF

  echo "End Create StoraceClass and PersistantVolumeClaim"
  echo
}

# setup_storage
