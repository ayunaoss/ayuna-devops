#!/bin/bash

# Script to convert a string to kebabcase and append an 8-character alphanumeric password
# Usage: ./gen-secure-keyref.sh <string>
# Example: ./gen-secure-keyref.sh "Hello World" -> hello-world-a1B2c3D4

set -e

# Get input string
INPUT="$1"

if [ -z "$INPUT" ]; then
    echo "Usage: $0 <string>"
    exit 1
fi

# Convert to kebabcase: lowercase, replace spaces and underscores with hyphens
KEBAB=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | sed 's/-\+/-/g; s/^-\|-$//g')

# Generate 8-character alphanumeric password
PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-z0-9' | head -c 8)

# Output result
echo "${KEBAB}-${PASSWORD}"
