#!/bin/bash

set -euo pipefail

## Check if config file is passed as argument
if [ "$#" -ne 1 ]; then
    echo "Error: Invalid number of arguments"
    echo "Usage: connect-aks.sh <env-config-file>"
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

if [ -z "$(command -v az 2>/dev/null)" ]; then
    echo -e "Azure CLI is not installed. Please install it and try again"
    return 1
fi

check_kubectl="$(command -v kubectl 2>/dev/null)"
check_kubelogin="$(command -v kubelogin 2>/dev/null)"

if [ -z "$check_kubectl" ] || [ -z "$check_kubelogin" ]; then
    echo -e "Either kubectl or kubelogin is not installed, will try setting up locally under ~/.local/bin ..."
    az aks install-cli --install-location $HOME/.local/bin/kubectl --kubelogin-install-location $HOME/.local/bin/kubelogin
    export PATH=$HOME/.local/bin:$PATH
else
    echo -e "Found existing kubectl and kubelogin binaries"
fi

echo -e "Checking Azure login ..."
check_az_login="$(az account show --query tenantId -o tsv 2>/dev/null)"

if [ "$check_az_login" != "$TENANT_ID" ]; then
    az login --tenant $TENANT_ID --use-device-code
else
    echo -e "Already logged in to Azure"
fi

echo -e "Setting Azure subscription to $SUBSCRIPTION_ID"
az account set --subscription $SUBSCRIPTION_ID

aks_cluster=$(kubectl config get-clusters | grep -w $AKS_NAME | grep -v 'grep')

if [ -z "$aks_cluster" ]; then
    echo -e "Setting AKS cluster context for $AKS_NAME"
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME && sync
    kubectl config use-context $AKS_NAME
    kubectl config set-cluster $AKS_NAME --server $AKS_SERVER_URL
else
    kubectl config use-context $AKS_NAME
fi

kubectl get namespaces && sync

echo -n "Checking cluster access for ${AKS_NAME}... "
kubectl cluster-info --request-timeout=5s >/dev/null 2>&1

if [ $? != 0 ]; then
    echo -e "FAILED (check VPN or firewall rules)"
    exit 1
else
    echo -e "OK"
fi
