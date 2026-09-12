#!/bin/bash

set -euo pipefail

# 1. Get IDs of all containers with "exited" status
# -a: all containers, -q: numeric IDs only, -f: filter by status
EXITED_CONTAINERS=$(docker ps -a -q -f status=exited)

# 2. Check if any exited containers were found
if [ -z "$EXITED_CONTAINERS" ]; then
    echo "No exited containers found."
else
    # 3. List the containers being removed for transparency
    echo "The following exited containers will be removed:"
    docker ps -a -f status=exited --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"

    # 4. Remove the containers
    echo -e "\nRemoving containers..."
    docker rm $EXITED_CONTAINERS
fi
