#!/bin/bash

set -euo pipefail

k8s_namespace=${1:-ayunaio}

## Capture the pods to be deleted
to_be_deleted=$(kubectl get pods -n ${k8s_namespace} --no-headers=true | grep -iE "Completed|ImagePullBackOff" | grep -v grep | awk {'print $1'})

if [ -z "$to_be_deleted" ]; then
    echo "No pods to delete"
else
    echo -e "Pods to be deleted:\n${to_be_deleted}"
    ## Delete the pods
    for pod in $to_be_deleted; do
        kubectl delete pod -n ${k8s_namespace} $pod
    done
fi
