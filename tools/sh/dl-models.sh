#!/bin/bash

set -euo pipefail

hf_token=${HF_TOKEN:-""}
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
models_dir="${script_dir}/models"
artifacts_path="/opt/app-root/src/models"
docling_oci="ghcr.io/docling-project/docling-serve-cpu:v1.30.0"

dl_models_cmd="docling-tools models download --all --quiet --output-dir ${artifacts_path}"
docker_run_args="
    --rm \
    -v ${models_dir}:${artifacts_path} \
    -e DOCLING_SERVE_ARTIFACTS_PATH=${artifacts_path}
"

if [[ -z "${hf_token}" ]]; then
    echo "HF_TOKEN environment variable is not set. Download experience might get degraded!"
else
    echo -e "HF_TOKEN environment variable is set."
    docker_run_args="${docker_run_args} -e HF_TOKEN=${hf_token}"
fi

echo -e "Setting up models directory at ${models_dir}..."
mkdir -p "${models_dir}"

echo -e "Setting docling user:group permissions for models directory..."
sudo chown -R "1001:0" "${models_dir}"

echo -e "Copying cached models..."
docker run ${docker_run_args} ${docling_oci} rsync -zavl /opt/app-root/src/.cache/docling/models/ ${artifacts_path}/ && sync

echo -e "Cleaning up cached models..."
docker run ${docker_run_args} ${docling_oci} rm -rf /opt/app-root/src/.cache/docling/models/* && sync

echo -e "Downloading all models..."
docker run ${docker_run_args} ${docling_oci} ${dl_models_cmd} && sync

exit 0
