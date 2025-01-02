#!/bin/bash

#
# INSTALL DEPS
#

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl vim
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
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

sudo kubectl wait --for=condition=Ready pods --all --timeout=600s -n argocd

# Install ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Not mandatory at all, but for convenience and best practice, let's reset the default password
# https://argo-cd.readthedocs.io/en/stable/faq/#i-forgot-the-admin-password-how-do-i-reset-it
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {
    "admin.password": "$2a$10$Ql1.T6pVWAcRlgeXe22N5.cpD0xLD62Ul5Kn5nObCgB9vv4of.vj.",
    "admin.passwordMtime": "'$(date +%FT%T%Z)'"
  }}'

#######################
# Gitlab Prerequisite #
#######################
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# PostgreSQL, Redis, Gitaly
# Ignore theses prerequisite since each of these components are present for trial in Gitlab chart.

# Secrets
# Keep auto-generated secret for now

############################
# Gitlab install with Helm #
############################

# Doc used:
# https://docs.gitlab.com/charts/installation/deployment.html#deploy-using-helm
# https://docs.gitlab.com/charts/development/minikube/#deploying-gitlab-with-minimal-settings

sudo kubectl create namespace gitlab

sudo helm repo add gitlab https://charts.gitlab.io/
sudo helm repo update
sudo helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
  --timeout 600s \
  --set global.hosts.domain=192.168.56.110.nip.io \
  --set global.hosts.externalIP=192.168.56.110 \
  --set global.hosts.https=false # Needed to explicitly authorize conexion with http

# Wait gitlab is ready
sudo kubectl wait --for=condition=Ready pod -l app=webservice --timeout=600s -n gitlab

# Get access to gitlab using 192.168.56.110:4280 in a browser
GITLAB_PORT=4280
sudo kubectl port-forward svc/gitlab-webservice-default --address 192.168.56.110 -n gitlab $GITLAB_PORT:8181 2>&1 >/dev/null &

###############################
# Create a new repo in gitlab #
###############################

# Create the repo with the app.yaml in it
REPO_NAME="myrepo"
mkdir $REPO_NAME && cd $REPO_NAME && git init
git config --global user.name banthony && git config --global user.email banthony@42.com
cp /home/vagrant/app.yaml . && git add app.yaml && git commit -m "init commit"

# For credential we can also use .netrc file:
# echo -e "machine gitlab.192.168.56.110.nip.io\nlogin root\npassword $ROOT_PASSWORD" >.netrc && mv .netrc ~/
# git push --set-upstream http://@gitlab.192.168.56.110.nip.io:$GITLAB_PORT/root/a.git master

GITASKPASS_SCRIPT="get_gitlab_root_pass.sh"
echo "sudo kubectl get -n gitlab secret gitlab-gitlab-initial-root-password -ojsonpath='{.data.password}' | base64 --decode && echo" >$GITASKPASS_SCRIPT
chmod 755 $GITASKPASS_SCRIPT
export GIT_ASKPASS="./${GITASKPASS_SCRIPT}"
git remote add origin http://root@gitlab.192.168.56.110.nip.io:$GITLAB_PORT/root/$REPO_NAME.git
git push -u origin master
chown -R vagrant:vagrant ./
# git push --set-upstream http://root@gitlab.192.168.56.110.nip.io:$GITLAB_PORT/root/$REPO_NAME.git master

#####################################
# Configure argocd with gitlab repo #
#####################################

# Setup argocd to directly talk with kubernetes instead of Argo API server
sudo argocd login --core

sudo kubectl config set-context --current --namespace=argocd

ROOT_PASSWORD=$(
  kubectl get -n gitlab secret gitlab-gitlab-initial-root-password -ojsonpath='{.data.password}' | base64 --decode
  echo
)

sudo argocd app create wil-playground --repo http://root@${ROOT_PASSWORD}192.168.56.110.nip.io:${GITLAB_PORT}/root/${REPO_NAME}.git --path ./ --dest-server https://kubernetes.default.svc --dest-namespace dev

# Setup the app to automatically update the deployment according to gitlab repo HEAD
sudo argocd app set wil-playground --sync-policy automated --self-heal

# Sync the app with gitlab repo (deploy according to HEAD)
sudo argocd app sync wil-playground

sudo kubectl wait --for=condition=Ready pods --all --timeout=60s -n argocd

# # Access ArgoCD from Host browser with 192.168.56.110:8081
sudo kubectl port-forward svc/argocd-server --address 192.168.56.110 -n argocd 8081:80 2>&1 >/dev/null &

# # Access wil-playground deployed app with localhost:8888
# sudo kubectl port-forward svc/wil-playground-service -n dev 8888:8888 2>&1 >/dev/null &
