#!/bin/bash

set -euo pipefail

# Script to generate NATS secrets: operator JWT, account JWT, user JWT, password, xkey, auth secret
# Uses nsc for generating NATS security context and JWTs
# For xkey, generates the seed; to get the public key, use: nk -inkey <seed> -pubout

# Check if nsc is available
if ! command -v nsc &>/dev/null; then
    echo "nsc is not installed. Please install nsc from https://github.com/nats-io/nsc"
    exit 1
fi

# Check if nk is available
if ! command -v nk &>/dev/null; then
    echo "nk is not installed. You will need nk to convert xkey seed to public key."
    exit 1
fi

# Create temporary directory for nsc store
TEMP_DIR=$(mktemp -d --suffix _nats_secrets)
trap "rm -rf $TEMP_DIR" EXIT

export NSC_HOME="$TEMP_DIR"

# Initialize nsc with operator, account, user
echo "Initializing NATS security context..."
nsc init --name ayuna-nats --dir "$TEMP_DIR" >/dev/null 2>&1

# Get JWTs
echo "Generating JWTs..."
OPERATOR_JWT=$(nsc describe operator --raw)
ACCOUNT_JWT=$(nsc describe account --raw)
USER_JWT=$(nsc describe user --raw)

# Generate xkey seed
echo "Generating xkey..."
# Note: XKEY should be the public key. To get it, run: nk -inkey "$XKEY_SEED" -pubout
XKEY_SEED=$(nk -gen curve)
echo "$XKEY_SEED" >"$NSC_HOME/xkey_seed.txt"
XKEY=$(nk -inkey "$NSC_HOME/xkey_seed.txt" -pubout)

# Generate random password
PASSWORD=$(openssl rand -base64 32)

# Generate random auth secret
AUTH_SECRET=$(openssl rand -base64 32)

# Output the secrets
echo "NATS Secrets Generated:"
echo "======================"
echo "Operator JWT: $OPERATOR_JWT"
echo "Account JWT: $ACCOUNT_JWT"
echo "User JWT: $USER_JWT"
echo "XKEY Seed: $XKEY_SEED"
echo "XKey (public): $XKEY"
echo "Password: $PASSWORD"
echo "Auth Secret: $AUTH_SECRET"
echo ""
