#!/bin/bash

process_release() {
  echo "Processing Release: $3"

  local AZ_ORG=$1
  local AZ_PROJECT=$2
  local RELEASE_NAME=$3
  local PL_NAME=$4

  RELEASE_LIST=$(az pipelines release definition list $AZ_ARGS )
  #echo "Release List: $RELEASE_LIST"
  POST_DATA=$(jq '.| .name="'$PL_NAME-$RELEASE_NAME'"' ./files/release-template.json)

  NEW_REL=$(curl  -s -d "$POST_DATA" -u username:$MYPAT -H "Content-Type: application/json" "https://vsrm.dev.azure.com/$AZ_ORG/$AZ_PROJECT/_apis/release/definitions/1?api-version=6.0" | jq .)
  #echo $NEW_REL
  #RELEASE_COUNT=$(echo $PL_LIST | jq '. | length')
  #if [ $PL_COUNT -gt 0 ]; then
  #  echo "Pipeline Exists, skipping"
  #else
  #  NEW_PL=$(az pipelines create $AZ_ARGS --name "$PIPE_NAME" \
  #      --description "$PIPE_NAME via Automation" --repository-type 'github' \
  #      --repository "$PL_REPO" --skip-run \
  #       --branch "$PL_REPO_BRANCH" --yml-path "$PL_BUILD_FILE" --service-connection "$SERVICE_ID")
  #  echo "Created Pipeline: $NEW_PL"
  #fi
}

add_pipeline_file() {
echo "Adding build file to repository"
  local PL_REPO=$1
  local PL_REPO_BRANCH=$2
  REPO_PATH=${PL_REPO:8}
  NEW_URL=$(echo https://$GIT_USERNAME:$GIT_TOKEN@$REPO_PATH|tr -d ' \n')
  echo "GIT NEW URL: $NEW_URL"
  CUR_DIR=$(pwd)
  cd $(mktemp -d)
  git clone $NEW_URL -- working
  cd working
  git config --global user.email "$GIT_USERNAME@redhat.com"
  git config --global user.name "$GIT_USERNAME"
  git config credential.helper 'cache --timeout=30'
  git fetch
  git switch $PL_REPO_BRANCH
  cp $CUR_DIR/files/azure-pipelines-build.yml .
  git branch -m "$PL_REPO_BRANCH/AzureAutomation"
  git add ./azure-pipelines-build.yml
  git commit -m "Add azure build and release automation"
  echo Pushing to origin "$FULL_IMAGE_TAG"
  git push origin "$PL_REPO_BRANCH/AzureAutomation"
  cd $CUR_DIR
}


process_pipeline() {
  local AZ_ORG=$1
  local AZ_PROJECT=$2
  local SVC_ENDPOINT=$3
  local PIPE_NAME=$4
  local PL_REPO=$5
  local PL_REPO_BRANCH=$6
  local PL_REPO_BUILD_FILE=$7
  local PL_RELEASES=$8
  local PL_INIT=$9

  AZ_ARGS="--org https://dev.azure.com/$AZ_ORG/ --project $AZ_PROJECT"

  echo "Creating pipe for Org: $AZ_ORG, Project: $AZ_PROJECT"
  if [[ -z "${AZURE_DEVOPS_EXT_GITHUB_PAT}" ]]; then
    echo "Must supply the AZURE_DEVOPS_EXT_GITHUB_PAT environment variable"
    exit -1
  fi

  ## Check for existance of the service endpint
  SVC_ENDPT=$(az devops service-endpoint list $AZ_ARGS)
  SVC_ID=$(echo $SVC_ENDPT | jq '.[] | select (.name=="'$SVC_ENDPOINT'") .id')

  ## If Endpoint not defined create id
  if [ -z "${SVC_ID}" ]; then
    echo "Creating service $SVC_ENDPOINT"
    SVC_ENDPT=$(az devops service-endpoint github create $AZ_ARGS --github-url https://github.com --name $SVC_ENDPOINT --detect true)
    #echo $SVC_ENDPT | jq '. | .id'
    SVC_ID=$(echo $SVC_ENDPT | jq '. | .id')
  fi
  SERVICE_ID=$(echo "$SVC_ID"  | tr -d '"')

  PL_LIST=$(az pipelines list $AZ_ARGS --name "$PIPE_NAME")
  PL_COUNT=$(echo $PL_LIST | jq '. | length')
  if [ $PL_COUNT -gt 0 ]; then
    echo "Pipeline Exists, skipping"
  else
    if [ $PL_INIT == "true" ]; then
      add_pipeline_file "$PL_REPO" "$PL_REPO_BRANCH"
      PL_BUILD_FILE="azure-pipelines-build.yml"
    fi

    NEW_PL=$(az pipelines create $AZ_ARGS --name "$PIPE_NAME" \
        --description "$PIPE_NAME via Automation" --repository-type 'github' \
        --repository "$PL_REPO" --skip-run \
         --branch "$PL_REPO_BRANCH" --yml-path "$PL_BUILD_FILE" --service-connection "$SERVICE_ID")
    echo "Created Pipeline: $NEW_PL"
  fi

  for row in $(echo "${PL_RELEASES}" | jq -r '.[] | @base64'); do
     _jq() {
       echo ${row} | base64 --decode | jq -r ${1}
    }
    RELEASE_NAME=$(echo $(_jq '.name'))
    process_release "$AZ_ORG" "$AZ_PROJECT" "$RELEASE_NAME" "$PIPE_NAME"
  done

}

az login -u "$AZ_USERNAME" -p "$AZ_PASSWORD" --allow-no-subscriptions
curl -L -s -o ./yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O ./yq
chmod +x ./yq
PIPE_JSON=$(./yq -o=json  ./pipelines.yml)

for row in $(echo "${PIPE_JSON}" | jq -r '.[] | @base64'); do
   _jq() {
       echo ${row} | base64 --decode | jq -r ${1}
   }
   PIPE_NAME=$(echo $(_jq '.name'))
   AZ_PROJECT=$(echo $(_jq '.az_project'))
   AZ_ORG=$(echo $(_jq '.az_organization'))
   AZ_SERVICE=$(echo $(_jq '.az_github_service'))
   PL_REPO=$(echo $(_jq '.repo'))
   PL_BRANCH=$(echo $(_jq '.branch'))
   PL_INIT=$(echo $(_jq '.initialize_build'))
   PL_BUILD_FILE=$(echo $(_jq '.build_file'))
   PL_RELEASES=$(echo $(_jq '.releases'))
   echo "processing Project: $AZ_PROJECT, Pipeline: $PIPE_NAME, ORG: $AZ_ORG, SVC: $AZ_SERVICE"
   process_pipeline "$AZ_ORG" "$AZ_PROJECT" "$AZ_SERVICE" "$PIPE_NAME" "$PL_REPO" "$PL_BRANCH" "PL_BUILD_FILE" "$PL_RELEASES" "$PL_INIT"
done

