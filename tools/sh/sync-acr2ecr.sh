#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

## Check for the required arguments
if [ "$#" -ne 1 ]; then
    echo "Error: Invalid number of arguments"
    echo "Usage: sync-acr2ecr.sh <env-config-file>"
    exit 1
fi

env_config_file="$1"

## Check for the existance of the environment config file
if [ ! -f "$env_config_file" ]; then
    echo "Error: $env_config_file not found!"
    exit 1
fi

echo -e "Loading environment config..."
source $env_config_file

req_vars=(
    "ACR_NAME"
    "AWS_ACCOUNT"
    "AWS_REGION"
    "AWS_PROFILE"
    "AWS_WITH_SSO"
    "OCI_IMAGES"
)

## Check for the required environment variables to be set
for item in "${req_vars[@]}"; do
    if [ -z "${!item}" ]; then
        echo "Error: $item is not set in the environment config file."
        exit 1
    fi
done

function sync_oci_image() {
    local image=$1
    local tag=$2

    echo -e "\nEnsuring ECR repo exists: $image"

    if ! aws ecr describe-repositories \
        --repository-names $image \
        --region ${AWS_REGION} --profile ${AWS_PROFILE} \
        --output text >/dev/null 2>&1; then
        echo -e "Repository $image does not exist. Creating..."
        aws ecr create-repository \
            --repository-name $image \
            --region ${AWS_REGION} --profile ${AWS_PROFILE} >/dev/null
        echo -e "Repository $image created."
    else
        echo -e "Repository $image already exists."
    fi

    echo -e "\nProcessing $image:$tag"

    docker pull ${ACR_NAME}.azurecr.io/$image:$tag
    docker tag ${ACR_NAME}.azurecr.io/$image:$tag \
        ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/$image:$tag

    docker push ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/$image:$tag
    echo -e "" && sync

    docker rmi ${ACR_NAME}.azurecr.io/$image:$tag
    docker rmi ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/$image:$tag
}

# Login
echo -e "\nLogging into Azure ACR..."
az acr login --name ${ACR_NAME}

echo -e "\nLogging into AWS ECR..."
## If AWS SSO is enabled (true), login using device-code.
## Otherwise, use AWS profile (with long-term credentials).
if [ "${AWS_WITH_SSO}" = "true" ]; then
    aws sso login --profile ${AWS_PROFILE} --use-device-code
fi

aws ecr get-login-password --region ${AWS_REGION} --profile ${AWS_PROFILE} |
    docker login --username AWS \
        --password-stdin ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com

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

echo -e "\nACR to ECR sync completed successfully!"
