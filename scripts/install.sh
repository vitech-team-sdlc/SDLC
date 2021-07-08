#!/usr/bin/env bash

set -e

export INFRA_REPO_NAME="demo-infra" # <1>
export ENV_REPO_NAME="demo-environment" # <2>

export BASE_REPO_URL="https://github.com/vitech-team"
export INFRA_GIT="$BASE_REPO_URL/$INFRA_REPO_NAME.git" # <3>
export ENV_GIT="$BASE_REPO_URL/$ENV_REPO_NAME.git" # <3>

export TF_VAR_jx_bot_username=XXX # <4>
export TF_VAR_jx_bot_token=XXX # <4>

export CLUSTER_NAME="demo-time" # <5>
export GCP_PROJECT="XXX" # <6>
export ZONE="europe-west1-c" # <7>
export MIN_NODE_COUNT="4" # <8>
export FORCE_DESTROY="false" # <9>

export green="\e[32m"
export nrm="\e[39m"

if [ ! -d $INFRA_REPO_NAME ]; then
  git clone $INFRA_GIT
fi
if [ ! -d $ENV_REPO_NAME ]; then
  git clone $ENV_GIT
fi


cd "$ENV_REPO_NAME" || exit
git pull

jx gitops update

git add .

git commit -m "chore: gitops update from upstream"

git push

cd "../$INFRA_REPO_NAME" || exit

rm -f values.auto.tfvars
# <10>
cat <<EOF >values.auto.tfvars
resource_labels = { "provider" : "jx" }
jx_git_url = "${ENV_GIT}"
gcp_project = "${GCP_PROJECT}"
cluster_name = "${CLUSTER_NAME}"
cluster_location = "${ZONE}"
force_destroy = "${FORCE_DESTROY}"
min_node_count = "${MIN_NODE_COUNT}"
EOF

git commit -a -m "fix: configure cluster repository and project" && git push || echo "Nothing to push"

terraform init
terraform apply

echo -e "${green}Setup kubeconfig...${nrm}"
gcloud components update
gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone "${ZONE}" --project "${GCP_PROJECT}"

echo "Taling logs..."
jx admin log

echo -e "${green}Okay, now we are creating new key for service account...${nrm}"
gcloud iam service-accounts keys create keyfile.json --iam-account "${CLUSTER_NAME}-tekton@${GCP_PROJECT}.iam.gserviceaccount.com"
SECRETNAME=docker-registry-auth
kubectl create secret docker-registry $SECRETNAME \
  --docker-server=https://gcr.io \
  --docker-username=_json_key \
  --docker-email=sdlc@vitechteam.com \
  --docker-password="$(cat keyfile.json)" \
  --namespace=jx
kubectl label secret $SECRETNAME secret.jenkins-x.io/replica-source=true --namespace=jx

cd "../$ENV_REPO_NAME" || exit
git pull

echo -e "${green}Okay, now we need populate secrets which is related on other services...${nrm}"
echo -e "${green}Creating proxy to vault...${nrm}"
jx secret vault portforward &
sleep 3
jx secret verify
jx secret populate
jx secret edit -f sonar

echo -e "${green}Killing proxy process...${nrm}"
kill %1

echo -e "For destroy open infrastructure folder and execute: ${green}terraform destroy${nrm}"

echo -e "For vault root token use: ${green}kubectl get secrets vault-unseal-keys  -n secret-infra -o jsonpath={.data.vault-root} | base64 --decode${nrm}"
