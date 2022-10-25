#!/bin/bash
#Usage ./setup-az-pipelines.sh "Org" "Project" "SvcEndpoint" 
#./setup-az-pipelines.sh "https://dev.azure.com/mlacours0374/" "ado-ocp-test" "mikelgithub" 

AZ_ORG=$1
AZ_PROJECT=$2
SVC_ENDPOINT=$3

AZ_ARGS="--org $AZ_ORG --project $AZ_PROJECT"

echo "Creating pipe for Org: $AZ_ORG, Project: $AZ_PROJECT"
if [[ -z "${AZURE_DEVOPS_EXT_GITHUB_PAT}" ]]; then
  echo "Must supply the AZURE_DEVOPS_EXT_GITHUB_PAT environment variable"
  exit -1
fi
## Check for existance of the service endpint
SVC_ENDPT=$(az devops service-endpoint list $AZ_ARGS)	


echo $SVC_ENDPT | jq '.[] | select (.name=="'$SVC_ENDPOINT'") .id'
#SVC_ID=$(echo $SVC_ENDPT | jq '.[] | .serviceEndpointProjectReferences | .[] | select (.name=="'"$SVC_ENDPOINT"'") | .projectReference.id')
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
az pipelines create $AZ_ARGS --name 'code-build' \
  --description 'Pipeline Building Spring App' --repository-type 'github' \
  --repository "https://github.com/malacourse/spring-rest" \
   --branch "features/update-pipeline" --yml-path "azure-pipelines-build.yml" --service-connection "$SERVICE_ID"
