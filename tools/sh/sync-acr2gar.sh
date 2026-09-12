#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

## Check for the required arguments
if [ "$#" -ne 1 ]; then
    echo "Error: Invalid number of arguments"
    echo "Usage: ./acr2gar-sync.sh <deployment-env-file>"
    exit 1
fi

deploy_env_file="$1"

## Check for the existence of the deployment environment file
if [ ! -f "$deploy_env_file" ]; then
    echo "Error: $deploy_env_file not found!"
    exit 1
fi

echo -e "Loading deployment environment config..."
source "$deploy_env_file"

req_vars=(
    "ACR_NAME"
    "GCP_PROFILE"
    "GCP_PROJECT_ID"
    "GCP_REGION"
    "GCP_GAR_REPO"
    "OCI_IMAGES"
)

## Check for the required environment variables to be set
for item in "${req_vars[@]}"; do
    if ! declare -p "$item" &>/dev/null || [ -z "${!item}" ]; then
        echo "Error: $item is not set in the deployment environment file."
        exit 1
    fi
done

GAR_HOST="${GCP_REGION}-docker.pkg.dev"

function sync_oci_image() {
    local image=$1
    local tag=$2

    echo -e "\nProcessing $image:$tag"

    ACR_IMAGE="${ACR_NAME}.azurecr.io/${image}:${tag}"
    GAR_IMAGE="${GAR_HOST}/${GCP_PROJECT_ID}/${GCP_GAR_REPO}/${image}:${tag}"

    docker pull "${ACR_IMAGE}"
    docker tag "${ACR_IMAGE}" "${GAR_IMAGE}"
    docker push "${GAR_IMAGE}"
    echo -e "" && sync

    docker rmi "${GAR_IMAGE}"
}

# Login
echo -e "\nLogging into Azure ACR..."
az acr login --name "${ACR_NAME}"

echo -e "\nConfiguring Docker for Google Artifact Registry..."
gcloud auth configure-docker "${GAR_HOST}" --quiet --configuration="${GCP_PROFILE}"

## Ensure GAR repo exists
echo -e "\nEnsuring GAR repo exists: ${GCP_GAR_REPO}"
if ! gcloud artifacts repositories describe "${GCP_GAR_REPO}" \
    --location="${GCP_REGION}" \
    --project="${GCP_PROJECT_ID}" \
    --configuration="${GCP_PROFILE}" >/dev/null 2>&1; then

    echo -e "Repository ${GCP_GAR_REPO} does not exist. Creating..."
    gcloud artifacts repositories create "${GCP_GAR_REPO}" \
        --repository-format=docker \
        --location="${GCP_REGION}" \
        --project="${GCP_PROJECT_ID}" \
        --configuration="${GCP_PROFILE}" \
        --description="Synced from Azure ACR"
    echo -e "Repository ${GCP_GAR_REPO} created."
else
    echo -e "Repository ${GCP_GAR_REPO} already exists."
fi

## Sync OCI images
echo -e "\nSyncing OCI images..."
for oci_image in ${OCI_IMAGES[@]}; do
    image=$(echo $oci_image | cut -d":" -f1)
    tag=$(echo $oci_image | cut -d":" -f2)
    sync_oci_image $image $tag
done

## Clean up the images
echo -e "\nCleaning up docker images..."
docker builder prune -a -f && sync

TO_BE_REMOVED=$(docker images -q --filter "dangling=true")
if [ -n "${TO_BE_REMOVED}" ]; then
    docker rmi ${TO_BE_REMOVED} && sync
fi

echo -e "\nACR to GAR sync completed successfully!"
