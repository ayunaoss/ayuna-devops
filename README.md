# Ayuna DevOps

Set of useful tools and utilities for dev-ops.

## Playpod

Playpod is a tool to run ansible playbooks on podman containers.

## UK8s

This project provides utility scripts to setup Canonical's microk8s cluster locally on Ubuntu X86-64bit systems.

1. **config.sh**: Use this script for master and work nodes configuration
2. **setup-cluster.sh**: Use this script to initiate the cluster
3. **cleanup-cluster.sh**: Use this script to clean up the cluster
4. **samples**: This folder contains additional K8s resource yaml files

## Ocibase

This provides the Docker setup to build base container images for python, golang and typescript services.

## Devoci

This provides local container environment for ayuna-forge system services (dependencies).

## Tools

This provides general purpose python and shell scripts for infra management. For example, `oci_setup.py` under `tools/py` can be used to initialize the data and environment needed to run devoci containers.
