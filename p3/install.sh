#!/bin/bash

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install docker
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Download kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Install kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Create new cluster
sudo k3d cluster create p3-cluster --api-port 6443 -p 8080:80@loadbalancer --agents 2

# Install ArgoCD
sudo kubectl create namespace argocd
sudo kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

sudo kubectl wait --for=condition=Ready pods --all -n argocd

# Install ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

echo "Waiting for cluster to be ready ..."
sleep 20

sudo argocd login --core

sudo kubectl config set-context --current --namespace=argocd

sudo argocd app create wil-playground --repo https://github.com/banthony42/inception_of_things.git --path p3/config --dest-server https://kubernetes.default.svc --dest-namespace dev

sudo argocd app set wil-playground --sync-policy automated --self-heal

sudo kubectl create namespace dev

sudo argocd app sync wil-playground

sudo kubectl port-forward svc/argocd-server --address 192.168.56.110 -n argocd 8081:80 2>&1 >/dev/null &
sudo kubectl port-forward svc/wil-playground-service -n dev 8888:8888 2>&1 >/dev/null &

# Get ArgoCD password :
# sudo kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d