#!/bin/bash

process_update() {
  AZ_ORG=$1
  AZ_PROJECT=$2
  SVC_ENDPOINT=$3
  PIPE_NAME=$4
  AZ_ARGS="--org $AZ_ORG --project $AZ_PROJECT"

  echo "Creating pipe for Org: $AZ_ORG, Project: $AZ_PROJECT"
  if [[ -z "${AZURE_DEVOPS_EXT_GITHUB_PAT}" ]]; then
    echo "Must supply the AZURE_DEVOPS_EXT_GITHUB_PAT environment variable"
    exit -1
  fi

  ## Check for existance of the service endpint
  SVC_ENDPT=$(az devops service-endpoint list $AZ_ARGS)


  echo $SVC_ENDPT | jq '.[] | select (.name=="'$SVC_ENDPOINT'") .id'
  SVC_ID=$(echo $SVC_ENDPT | jq '.[] | select (.name=="'$SVC_ENDPOINT'") .id')

  ## If Endpoint not defined create id
  if [ -z "${SVC_ID}" ]; then
    echo "Creating service $SVC_ENDPOINT"
    SVC_ENDPT=$(az devops service-endpoint github create --org $AZ_ORG --project $AZ_PROJECT --github-url https://github.com --name $SVC_ENDPOINT --detect true)
    echo $SVC_ENDPT | jq '. | .id'
    SVC_ID=$(echo $SVC_ENDPT | jq '. | .id')
  fi
  SERVICE_ID=$(echo "$SVC_ID"  | tr -d '"')
  echo Hello $SERVICE_ID
  az pipelines create $AZ_ARGS --name "$PIPE_NAME" \
    --description "$PIPE_NAME via Automation" --repository-type 'github' \
    --repository "https://github.com/malacourse/spring-rest" \
     --branch "features/update-pipeline" --yml-path "azure-pipelines-build.yml" --service-connection "$SERVICE_ID"

}

curl -L -s -o ./yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O ./yq
chmod +x ./yq
PIPE_JSON=$(./yq -o=json  ./pipelines.yml)

for row in $(echo "${PIPE_JSON}" | jq -r '.[] | @base64'); do
   _jq() {
       echo ${row} | base64 --decode | jq -r ${1}
   }
   _PIPE_NAME=$(echo $(_jq '.name'))
   _AZ_PROJECT=$(echo $(_jq '.az_project'))
   _AZ_ORG=$(echo $(_jq '.az_organization'))
   _AZ_SERVICE=$(echo $(_jq '.az_github_service'))
   echo "processing Project: $_AZ_PROJECT, Pipeline: $_PIPE_NAME, ORG: $_AZ_ORG, SVC: $_AZ_SERVICE"
   process_update "$_AZ_ORG" "$_AZ_PROJECT" "$_AZ_SERVICE" "$_PIPE_NAME"
done

