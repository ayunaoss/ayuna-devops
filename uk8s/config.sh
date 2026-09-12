#!/bin/bash

## Cluster configuration
MASTER_NODE="uk8s-master"
WORKER_NODES=("uk8s-agent1" "uk8s-agent2")
KUBECTL_CTX="microk8s"
SSH_KEY="$HOME/.ssh/id_rsa"
REGISTRY_PORT=5000

## VM resources
CPU=2
MEM=12G
DISK=32G
