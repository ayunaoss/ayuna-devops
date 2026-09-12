#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IP_CNT_BEGIN=11
PORT_CNT_BEGIN=81
IP_PREFIX="10.10.10"
POD_IMAGE_NAME="ayuna-playpod"
HOST_ENTRIES_HDR="# Ayuna playpod sshd ip-host mapping"

INVENTORY_FILE="$DIR/inventory"
ID_RSA_FILE="$DIR/assets/id_rsa"
OVERRIDE_VARS_FILE="$DIR/vars.yml"
PLAYBOOK_FILE="$DIR/../site.yml"
TARGETS=$(grep '\.dev\.local' $INVENTORY_FILE | grep -v ';' | awk {'print $1'} | sort | uniq)

cleanup_pod_ips() {
    echo "Cleaning up ips and hosts of playpod containers..."
    grep -v "$HOST_ENTRIES_HDR" /etc/hosts | sudo tee /etc/hosts 1>/dev/null
    grep -v "$IP_PREFIX" /etc/hosts | sudo tee /etc/hosts 1>/dev/null

    local counter=$IP_CNT_BEGIN

    for host in $TARGETS; do
        ip="$IP_PREFIX.$((counter++))"
        sudo ip -4 addr del ${ip}/32 dev lo 2>/dev/null
    done

    echo "	Done."
}

setup_pod_ips() {
    cleanup_pod_ips

    local counter=$IP_CNT_BEGIN

    echo "Setting up ips and hosts for playpod containers..."
    echo "$HOST_ENTRIES_HDR" | sudo tee -a /etc/hosts

    for host in $TARGETS; do
        ip="$IP_PREFIX.$((counter++))"
        sudo ip -4 addr add ${ip}/32 dev lo 2>/dev/null
        echo "$ip   $host" | sudo tee -a /etc/hosts
    done

    echo "	Done."
}

build_image() {
    echo "Building playpod container image..."
    podman build -t "${POD_IMAGE_NAME}:latest" . 1>/dev/null
    echo "	Done."
}

stop_containers() {
    echo "Stopping playpod containers..."

    for host in $TARGETS; do
        podman stop ${host} &>/dev/null
        podman rm -f ${host} &>/dev/null
    done

    echo "	Done."
}

start_containers() {
    stop_containers

    echo "Starting playpod containers..."

    local counter=$IP_CNT_BEGIN
    local portcnt=$PORT_CNT_BEGIN

    for host in $TARGETS; do
        ip="$IP_PREFIX.$((counter++))"
        port="$((portcnt++))22"
        podman run \
            -d \
            -p ${ip}:${port}:22 \
            --expose=22 \
            --name ${host} \
            "${POD_IMAGE_NAME}:latest" 1>/dev/null
    done

    echo "	Done."
}

run_ansible() {
    ANSIBLE_HOST_KEY_CHECKING=False \
        ansible-playbook \
        --inventory-file="$INVENTORY_FILE" \
        --user=podder \
        --private-key="$ID_RSA_FILE" \
        --extra-vars="@$OVERRIDE_VARS_FILE" \
        "$PLAYBOOK_FILE"
}

usage() {
    cat <<END

Usage: $0 [OPTIONS]

Run ansible playbook on podman containers.

Options:
    mkimg : Build container image to run the playbook on.
    clean : Cleanup the container and ip configuration.
    play  : Run the playbook on containers.
    help  : Show this help message.
END
}

## Actual business logic - a.k.a. main
if [ $# -lt 1 ]; then
    usage
    exit 1
fi

option=$1

case "$option" in
mkimg)
    build_image
    ;;
clean)
    stop_containers && cleanup_pod_ips && sync
    ;;
play)
    setup_pod_ips && start_containers && run_ansible
    ;;
help)
    usage
    exit 0
    ;;
*)
    echo -e "Unknown option. Please check the help."
    usage
    exit 1
    ;;
esac
