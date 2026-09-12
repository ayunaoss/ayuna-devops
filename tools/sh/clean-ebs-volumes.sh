#!/usr/bin/env bash
set -euo pipefail

# EKS EBS Cleaner Script
# Lists and deletes PVCs/PVs with EBS storage class and removes released volumes
# Usage: ./eks-ebs-cleaner.sh --namespace=<namespace> [--dry-run|--force]

# CONFIG
DRY_RUN=true
STORAGE_CLASS=""
NAMESPACE=""

# Function to show usage
show_usage() {
    echo "Usage: $0 --namespace=<namespace> --storage-class=<storage-class> [--dry-run|--force]"
    echo ""
    echo "Options:"
    echo "  --namespace=<ns>        (Required) Target specific namespace"
    echo "  --storage-class=<sc>    (Required) Storage class to filter PVCs/PVs"
    echo "  --dry-run               Show what would be deleted without actually deleting (default)"
    echo "  --force                 Actually perform the deletion"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --namespace=my-namespace --storage-class=ebs           # Dry run for my-namespace"
    echo "  $0 --namespace=my-namespace --storage-class=gp3 --force    # Actually delete resources in my-namespace"
}

# Parse arguments
for arg in "$@"; do
    case $arg in
    --dry-run)
        DRY_RUN=true
        shift
        ;;
    --force)
        DRY_RUN=false
        shift
        ;;
    --namespace=*)
        NAMESPACE="${arg#*=}"
        shift
        ;;
    -n=* | --ns=*)
        NAMESPACE="${arg#*=}"
        shift
        ;;
    --storage-class=*)
        STORAGE_CLASS="${arg#*=}"
        shift
        ;;
    --sc=*)
        STORAGE_CLASS="${arg#*=}"
        shift
        ;;
    -h | --help)
        show_usage
        exit 0
        ;;
    esac
done

# Validate namespace is provided
if [[ -z "$NAMESPACE" ]]; then
    echo "ERROR: --namespace is required"
    echo ""
    show_usage
    exit 1
fi

# Validate storage class is provided
if [[ -z "$STORAGE_CLASS" ]]; then
    echo "ERROR: --storage-class is required"
    echo ""
    show_usage
    exit 1
fi

echo "=========================================="
echo "EKS EBS Cleaner"
echo "=========================================="
echo "DRY_RUN: $DRY_RUN"
echo "STORAGE_CLASS: $STORAGE_CLASS"
echo "NAMESPACE: $NAMESPACE"
echo ""

# Check kubectl is available
if ! command -v kubectl &>/dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &>/dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi

# Function to list PVCs with EBS storage class
list_pvcs() {
    kubectl get pvc --namespace="$NAMESPACE" -o json 2>/dev/null |
        jq -r ".items[] | select(.spec.storageClassName == \"$STORAGE_CLASS\") | \"\(.metadata.name)\"" || true
}

# Function to list PVs with EBS storage class
list_pvs() {
    kubectl get pv --namespace="$NAMESPACE" -o json 2>/dev/null |
        jq -r ".items[] | select(.spec.storageClassName == \"$STORAGE_CLASS\") | \"\(.metadata.name)\"" || true
}

# Function to list available EC2 volumes that were previously attached to the cluster
list_available_volumes() {
    aws ec2 describe-volumes \
        --filters "Name=status,Values=available" \
        "Name=tag-key,Values=kubernetes.io/created-for/pvc/name" \
        "Name=tag-key,Values=kubernetes.io/created-for/pvc/namespace" \
        "Name=tag-value,Values=${NAMESPACE}" \
        --query "Volumes[].VolumeId" \
        --output text 2>/dev/null || true
}

# Function to delete PVC
delete_pvc() {
    local namespace="$1"
    local name="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would delete PVC: $namespace/$name"
    else
        echo "  Deleting PVC: $namespace/$name"
        kubectl delete pvc "$name" -n "$namespace" --wait=true
    fi
}

# Function to delete PV
delete_pv() {
    local namespace="$1"
    local name="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would delete PV: $namespace/$name"
    else
        echo "  Deleting PV: $namespace/$name"
        kubectl delete pv "$name" -n "$namespace" --wait=true
    fi
}

# Function to delete an EC2 volume
delete_volume() {
    local volume_id="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would delete EC2 volume: $volume_id"
    else
        echo "  Deleting EC2 volume: $volume_id"
        aws ec2 delete-volume --volume-id "$volume_id" 2>/dev/null || echo "    Failed to delete $volume_id (may already be deleted)"
    fi
}

echo "Step 1: Listing PVCs with storage class '$STORAGE_CLASS'..."
echo "-----------------------------------------------------------"

PVCS=$(list_pvcs)
PVC_COUNT=$(echo "$PVCS" | grep -v '^$' | wc -l)

if [[ "$PVC_COUNT" -eq 0 ]]; then
    echo "No PVCs found with storage class '$STORAGE_CLASS'"
else
    echo "Found $PVC_COUNT PVC(s):"
    while read -r name; do
        [[ -z "$name" ]] && continue
        echo "  - $NAMESPACE/$name"
    done <<<"$PVCS"
fi

echo ""
echo "Step 2: Listing PVs with storage class '$STORAGE_CLASS'..."
echo "----------------------------------------------------------"

PVS=$(list_pvs)
PV_COUNT=$(echo "$PVS" | grep -v '^$' | wc -l)

if [[ "$PV_COUNT" -eq 0 ]]; then
    echo "No PVs found with storage class '$STORAGE_CLASS'"
else
    echo "Found $PV_COUNT PV(s):"
    while read -r name; do
        [[ -z "$name" ]] && continue
        echo "  - $NAMESPACE/$name"
    done <<<"$PVS"
fi

echo ""
echo "Step 3: Listing available EC2 volumes (orphaned)..."
echo "---------------------------------------------------"

AVAILABLE_VOLUMES=$(list_available_volumes)
AVAILABLE_COUNT=$(echo "$AVAILABLE_VOLUMES" | tr ' \t' '\n' | grep -v '^$' | wc -l)

if [[ "$AVAILABLE_COUNT" -eq 0 ]]; then
    echo "No available EC2 volumes found"
else
    echo "Found $AVAILABLE_COUNT available EC2 volume(s):"
    echo "$AVAILABLE_VOLUMES" | tr ' \t' '\n' | grep -v '^$' | while read -r vol_id; do
        [[ -z "$vol_id" ]] && continue
        echo "  - $vol_id"
    done
fi

echo ""
echo "=========================================="

# Perform deletions if not in dry-run mode or show summary
if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY-RUN MODE: No resources will be deleted"
    echo "Run with --force to actually delete resources"
else
    echo "DELETING RESOURCES..."
    echo "---------------------"

    # Delete PVCs
    if [[ "$PVC_COUNT" -gt 0 ]]; then
        echo "Deleting PVCs..."
        while read -r name; do
            [[ -z "$name" ]] && continue
            delete_pvc "$NAMESPACE" "$name"
        done <<<"$PVCS"
    fi

    # Delete PVs
    if [[ "$PV_COUNT" -gt 0 ]]; then
        echo ""
        echo "Deleting PVs..."
        while read -r name; do
            [[ -z "$name" ]] && continue
            delete_pv "$NAMESPACE" "$name"
        done <<<"$PVS"
    fi

    # Delete available EC2 volumes (orphaned EBS volumes from deleted PVs)
    AVAILABLE_VOLUMES=$(list_available_volumes)
    AVAILABLE_COUNT=$(echo "$AVAILABLE_VOLUMES" | tr ' \t' '\n' | grep -v '^$' | wc -l)

    if [[ "$AVAILABLE_COUNT" -gt 0 ]]; then
        echo ""
        echo "Deleting available EC2 volumes (orphaned)..."
        echo "$AVAILABLE_VOLUMES" | tr ' \t' '\n' | grep -v '^$' | while read -r vol_id; do
            [[ -z "$vol_id" ]] && continue
            delete_volume "$vol_id"
        done
    fi

    echo ""
    echo "Deletion commands issued."
    echo "Note: PVs may remain in 'Terminating' state until underlying EBS volumes are deleted."
fi

echo ""
echo "Summary:"
echo "  - PVCs found: $PVC_COUNT"
echo "  - PVs found: $PV_COUNT"
echo "  - Available EC2 volumes found: $AVAILABLE_COUNT"
echo "=========================================="
