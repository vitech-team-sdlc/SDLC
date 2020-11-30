#!/usr/bin/env bash

export INFRA_REPO_NAME="demo-infra" # <1>
export ENV_REPO_NAME="demo-environment" # <2>

export INFRA_GIT="https://github.com/vitech-team/$INFRA_REPO_NAME.git" # <3>
export ENV_GIT="https://github.com/vitech-team/$ENV_REPO_NAME.git" # <3>

export TF_VAR_jx_bot_username=XXX # <4>
export TF_VAR_jx_bot_token=XXX # <4>

export CLUSTER_NAME="demo-time" # <5>
export GCP_PROJECT="XXX" # <6>
export ZONE="europe-west1-c" # <7>
export MIN_NODE_COUNT="4" # <8>
export FORCE_DESTROY="false" # <9>

export green="\e[32m"
export nrm="\e[39m"

git clone $INFRA_GIT
git clone $ENV_GIT

cd $INFRA_REPO_NAME || exit

rm values.auto.tfvars
# <10>
cat <<EOF >>values.auto.tfvars
resource_labels = { "provider" : "jx" }
jx_git_url = "${ENV_GIT}"
gcp_project = "${GCP_PROJECT}"
cluster_name = "${CLUSTER_NAME}"
cluster_location = "${ZONE}"
force_destroy = "${FORCE_DESTROY}"
min_node_count = "${MIN_NODE_COUNT}"
EOF

git commit -a -m "fix: configure cluster repository and project"
git push

terraform init
terraform apply

echo -e "${green}Setup kubeconfig...${nrm}"
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

jx namespace jx

echo -e "For vault root token use: ${green}kubectl get secrets vault-unseal-keys  -n secret-infra -o jsonpath={.data.vault-root} | base64 --decode${nrm}"
