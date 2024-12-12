#!/bin/bash

#
# INSTALL DEPS
#

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

#
# SETUP THE ARCHITECTURE
#

# Create new cluster
sudo k3d cluster create p3-cluster --api-port 6443 -p 8080:80@loadbalancer --agents 2
sudo kubectl create namespace dev
sudo kubectl create namespace argocd

# Install ArgoCD
sudo kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

sudo kubectl wait --for=condition=Ready pods --all --timeout=60s -n argocd

# Install ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Not mandatory at all, but for convenience and best practice, let's reset the default password
# https://argo-cd.readthedocs.io/en/stable/faq/#i-forgot-the-admin-password-how-do-i-reset-it
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {
    "admin.password": "$2a$10$ywZgQhdK.iA1DC3krGcwwejpBkb9cctzs9eOy0to3Yp1mUhnmDet2",
    "admin.passwordMtime": "'$(date +%FT%T%Z)'"
  }}'



# Install Gitlab
sudo kubectl create namespace gitlab


###########
###########

# Setup argocd to directly talk with kubernetes instead of Argo API server
# sudo argocd login --core

# sudo kubectl config set-context --current --namespace=argocd

# sudo argocd app create wil-playground --repo https://github.com/banthony42/inception_of_things.git --path p3/config --dest-server https://kubernetes.default.svc --dest-namespace dev

# # Setup the app to automatically update the deployment according to github repo HEAD
# sudo argocd app set wil-playground --sync-policy automated --self-heal

# # Sync the app with github repo (deploy according to HEAD)
# sudo argocd app sync wil-playground

# sudo kubectl wait --for=condition=Ready pods --all --timeout=60s -n argocd

# # Access ArgoCD from Host browser with 192.168.56.110:8081
# sudo kubectl port-forward svc/argocd-server --address 192.168.56.110 -n argocd 8081:80 2>&1 >/dev/null &

# # Access wil-playground deployed app with localhost:8888
# sudo kubectl port-forward svc/wil-playground-service -n dev 8888:8888 2>&1 >/dev/null &