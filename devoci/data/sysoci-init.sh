#!/bin/bash

set -euo pipefail

## Set up the system for running the containers
sysctl -w vm.overcommit_memory=1

## Set up the gateway config directory with the correct permissions
aigw_config_dir="/aigw/config"

if [ ! -f "${aigw_config_dir}/config.yaml" ]; then
    echo -e "Setting up fresh gateway config file at ${aigw_config_dir}/config.yaml..."
    cp /tmp/env/agentgateway.yaml "${aigw_config_dir}/config.yaml"
else
    echo -e "Gateway config file already exists at ${aigw_config_dir}/config.yaml, skipping setup..."
fi

### Add htpasswd file for basic auth to open portals
if [ ! -f "${aigw_config_dir}/.htpasswd" ]; then
    echo -e "Setting up fresh htpasswd file at ${aigw_config_dir}/.htpasswd..."
    cp /tmp/data/env/aigw_htpasswd "${aigw_config_dir}/.htpasswd"
else
    echo -e "Htpasswd file already exists at ${aigw_config_dir}/.htpasswd, skipping setup..."
fi

chown -R 65532:65532 "${aigw_config_dir}"
chmod 640 "${aigw_config_dir}/.htpasswd"

## Setup casdoor
casdoor_config_dir="/casdoor/config"

if [ ! -f "${casdoor_config_dir}/app.conf" ]; then
    echo -e "Setting up fresh casdoor config file at ${casdoor_config_dir}/app.conf..."
    cp /tmp/env/casdoor.conf "${casdoor_config_dir}/app.conf"
else
    echo -e "Casdoor config file already exists at ${casdoor_config_dir}/app.conf, skipping setup..."
fi

if [ ! -f "${casdoor_config_dir}/init_data.json" ]; then
    echo -e "Setting up fresh casdoor init data file at ${casdoor_config_dir}/init_data.json..."
    cp /tmp/data/casdoor/init_data.json "${casdoor_config_dir}/init_data.json"
else
    echo -e "Casdoor init data file already exists at ${casdoor_config_dir}/init_data.json, skipping setup..."
fi

chown -R 1000:1000 "${casdoor_config_dir}"

## Add wget and grpc_health_probe to /tools so that they can be used by the containers

### Add wget tool
if [ -f "/tools/wget" ]; then
    echo -e "wget already exists at /tools/wget, skipping copy..."
else
    echo -e "wget not found at /tools/wget, adding it..."
    cp /bin/wget /tools/wget
fi

chmod 755 /tools/wget

### Add grpc_health_probe tool
if [ -f "/tools/grpc_health_probe" ]; then
    echo -e "grpc_health_probe already exists at /tools/grpc_health_probe, skipping copy..."
else
    echo -e "grpc_health_probe not found at /tools/grpc_health_probe, adding it..."
    cp /tmp/data/tools/grpc_health_probe /tools/grpc_health_probe
fi

chmod 755 /tools/grpc_health_probe
