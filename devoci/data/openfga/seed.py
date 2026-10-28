#!/usr/bin/env python3
"""
Idempotent OpenFGA authorization model seed script.

Creates the ayuna-checkpoint store (if absent), writes the base authorization
model (if absent), and records OPENFGA_STORE_ID in the env file so downstream
services can consume it.

Environment variables:
  OPENFGA_API_URL    OpenFGA HTTP API base URL (default: http://ayuna-openfga:8080)
  OPENFGA_STORE_NAME Store display name       (default: ayuna-checkpoint)
  OPENFGA_ENV_FILE   Path to openfga.env      (default: /tmp/env/openfga.env)
  OPENFGA_MODEL_FILE Path to model.json       (default: /tmp/model/model.json)
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request


OPENFGA_API_URL = os.environ.get("OPENFGA_API_URL", "http://ayuna-openfga:8080")
OPENFGA_STORE_NAME = os.environ.get("OPENFGA_STORE_NAME", "ayuna-checkpoint")
OPENFGA_ENV_FILE = os.environ.get("OPENFGA_ENV_FILE", "/tmp/env/openfga.env")
OPENFGA_MODEL_FILE = os.environ.get("OPENFGA_MODEL_FILE", "/tmp/model/model.json")


def api(method: str, path: str, body: dict | None = None) -> dict:
    url = f"{OPENFGA_API_URL}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        body_text = exc.read().decode(errors="replace")
        print(f"HTTP {exc.code} from {method} {path}: {body_text}", file=sys.stderr)
        raise


def find_store(name: str) -> str | None:
    """Return the store ID for the named store, or None if it does not exist."""
    continuation_token = ""
    while True:
        path = "/stores"
        if continuation_token:
            path += f"?continuation_token={continuation_token}"
        resp = api("GET", path)
        for store in resp.get("stores", []):
            if store.get("name") == name:
                return store["id"]
        continuation_token = resp.get("continuation_token", "")
        if not continuation_token:
            return None


def has_model(store_id: str) -> bool:
    """Return True if the store already has at least one authorization model."""
    resp = api("GET", f"/stores/{store_id}/authorization-models")
    return bool(resp.get("authorization_models"))


def write_store_id(store_id: str) -> None:
    """Append or update OPENFGA_STORE_ID in the env file."""
    try:
        with open(OPENFGA_ENV_FILE) as fh:
            content = fh.read()
    except FileNotFoundError:
        content = ""

    if "OPENFGA_STORE_ID" in content:
        content = re.sub(
            r"^OPENFGA_STORE_ID=.*$",
            f"OPENFGA_STORE_ID={store_id}",
            content,
            flags=re.MULTILINE,
        )
    else:
        content = content.rstrip("\n") + f"\nOPENFGA_STORE_ID={store_id}\n"

    with open(OPENFGA_ENV_FILE, "w") as fh:
        fh.write(content)

    print(f"Recorded OPENFGA_STORE_ID={store_id} in {OPENFGA_ENV_FILE}")


def main() -> None:
    store_id = find_store(OPENFGA_STORE_NAME)
    if store_id:
        print(f"Store '{OPENFGA_STORE_NAME}' already exists: {store_id}")
    else:
        resp = api("POST", "/stores", {"name": OPENFGA_STORE_NAME})
        store_id = resp["id"]
        print(f"Created store '{OPENFGA_STORE_NAME}': {store_id}")

    if has_model(store_id):
        print("Authorization model already present, skipping write.")
    else:
        with open(OPENFGA_MODEL_FILE) as fh:
            model = json.load(fh)
        resp = api("POST", f"/stores/{store_id}/authorization-models", model)
        model_id = resp.get("authorization_model_id", "<unknown>")
        print(f"Written authorization model: {model_id}")

    write_store_id(store_id)
    print("Seed complete.")


if __name__ == "__main__":
    main()
