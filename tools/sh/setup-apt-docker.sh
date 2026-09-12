#!/bin/bash

set -euo pipefail

## Check for root or privileges
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with privileges."
  exit 1
fi

# Add Docker's official GPG key:
echo -e "Adding Docker's official GPG key and setting up the repository for apt package manager."

# Add Docker's official GPG key:
apt update
apt install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "${DEBIAN_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update
echo -e "Docker's official GPG key and repository have been added successfully."

echo -e "Run the following command to install Docker and its components:\n\n \
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-model-plugin\n"
