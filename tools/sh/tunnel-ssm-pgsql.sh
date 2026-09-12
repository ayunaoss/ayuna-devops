#!/bin/bash

set -euo pipefail

req_vars=(AWS_PROFILE BASTION_HOST_NAME POSTGRES_ENDPOINT)

for var in ${req_vars[@]}; do
    if [ -z "${!var}" ]; then
        echo "Error: Required environment variable '$var' is not set!"
        echo "Ensure to source the correct pulumi-aws env file"
        exit 1
    fi
done

BASTION_HOST_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${BASTION_HOST_NAME}" \
    "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text --profile ${AWS_PROFILE})

if [ -z "$BASTION_HOST_ID" ]; then
    echo "No running bastion host found with the specified tag."
    exit 1
else
    echo "Bastion Host Instance ID: $BASTION_HOST_ID"
fi

aws ssm start-session --profile ${AWS_PROFILE} \
    --target ${BASTION_HOST_ID} \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "host=${POSTGRES_ENDPOINT},portNumber=5432,localPortNumber=5432"
