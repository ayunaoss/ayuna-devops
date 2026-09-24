# Ayuna DevOps

Set of useful tools and utilities for dev-ops.

## Ocibase

This provides the Dockerfile, build script and artifacts to build and publish base container images, as follows.

1. **oci-py**: Base image for Python projects. Uses 3.12 version of python with `uv` as the package manager.
2. **oci-js**: Base image for JS/TS projects. Uses 24.x version of Node.js with `pnpm` as the package manager.
3. **oci-go**: Base image for Go projects. Uses 1.27 version of Go with the standard Go toolchain as the package manager.
4. **oci-pyjs**: Base image for Python and JS/TS projects. Combines the environments for both Python and Node.js.
5. **oci-gojs**: Base image for Go and JS/TS projects. Combines the environments for both Go and Node.js.
6. **oci-pygojs**: Base image for Python, Go, and JS/TS projects. Combines the environments for Python, Go, and Node.js.
7. **oci-builder**: Base image containing g++ compiler and other essential tools for local development. Includes the environments for Python, Node.js, and Go.
8. **oci-docling-cpu**: Image to run CPU based [Docling service](https://github.com/docling-project/docling-serve) for document extraction.

All oci images are available at [Ayuna OSS Packages](https://github.com/ayunaoss?tab=packages) in GitHub.

## UK8s

This project provides utility scripts to setup Canonical's microk8s cluster locally on Ubuntu X86-64bit systems.

1. **config.sh**: Use this script for master and work nodes configuration
2. **setup-cluster.sh**: Use this script to initiate the cluster
3. **cleanup-cluster.sh**: Use this script to clean up the cluster
4. **samples**: This folder contains additional K8s resource yaml files

## Devoci

This provides local container environment for ayuna-forge system services (dependencies).

## Tools

This provides general purpose python and shell scripts for infra management.

## Playpod

Playpod is a tool to run ansible playbooks on podman containers.
