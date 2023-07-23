#!/bin/bash

set -e

export ARGO_VERSION=INSERT_YOUR_VALUE_HERE
export MINIKUBE_CLUSTER_RAM=INSERT_YOUR_VALUE_HERE
export MINIKUBE_CLUSTER_CPUS=INSERT_YOUR_VALUE_HERE
export MINIKUBE_CLUSTER_DISK_SIZE=INSERT_YOUR_VALUE_HERE

export DOCKER_USERNAME=INSERT_YOUR_VALUE_HERE
export DOCKER_TOKEN=INSERT_YOUR_VALUE_HERE
export DOCKER_PASSWORD=INSERT_YOUR_VALUE_HERE
export DOCKER_EMAIL=INSERT_YOUR_VALUE_HERE
export HUGGINGFACE_TOKEN=INSERT_YOUR_VALUE_HERE

export DOCKER_SERVER="https://index.docker.io/v1/"

export DEFAULT_BUCKET_NAME="my-bucket"


minikube start --memory ${MINIKUBE_CLUSTER_RAM} \
               --cpus ${MINIKUBE_CLUSTER_CPUS} \
               --disk-size ${MINIKUBE_CLUSTER_DISK_SIZE}

kubectl create namespace argo
kubectl apply -n argo -f \
        https://github.com/argoproj/argo-workflows/releases/download/v${ARGO_VERSION}/install.yaml

kubectl patch deployment \
        argo-server \
        --namespace argo \
        --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": [
        "server",
        "--auth-mode=server"
        ]}]'

# Download the binary
curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.4.8/argo-darwin-amd64.gz

# Unzip
gunzip argo-darwin-amd64.gz

# Make binary executable
chmod +x argo-darwin-amd64

# Move binary to path
mv ./argo-darwin-amd64 /usr/local/bin/argo

# Test installation
argo version


kubectl -n argo create secret generic docker-config --from-literal="config.json={\"auths\": {\"https://index.docker.io/v1/\": {\"auth\": \"$(echo -n $DOCKER_USERNAME:$DOCKER_TOKEN|base64)\"}}}"


kubectl -n argo create secret generic hugging-face-token --from-literal=key=${HUGGINGFACE_TOKEN}

kubectl -n argo create rolebinding default-admin --clusterrole=admin --serviceaccount=argo:default

kubectl -n argo create secret docker-registry my-private-registry \
  --docker-server=${DOCKER_SERVER} \
  --docker-username=${DOCKER_USERNAME} \
  --docker-password=${DOCKER_PASSWORD}\
  --docker-email=${DOCKER_EMAIL}

kubectl -n argo create -f argo/persistent_volume.yml

brew install helm

helm repo add minio https://helm.min.io/ # official minio Helm charts
helm repo update
helm  -n argo install argo-artifacts minio/minio --set service.type=LoadBalancer --set fullnameOverride=argo-artifacts

export ACCESS_KEY=$(kubectl get secret argo-artifacts --namespace argo -o jsonpath="{.data.accesskey}" | base64 --decode)
export SECRET_KEY=$(kubectl get secret argo-artifacts --namespace argo -o jsonpath="{.data.secretkey}" | base64 --decode)

current_configmap=$(kubectl get configmap workflow-controller-configmap -n argo -o yaml)

updated_configmap="""${current_configmap}
data:
  artifactRepository: |
    s3:
      bucket: ${DEFAULT_BUCKET_NAME}
      keyFormat: prefix/in/bucket
      endpoint: argo-artifacts:9000
      insecure: true
      accessKeySecret:
        name: argo-artifacts
        key: accesskey
      secretKeySecret:
        name: argo-artifacts
        key: secretkey
      useSDKCreds: true
"""

echo "${updated_configmap}" | kubectl -n argo apply -f -

