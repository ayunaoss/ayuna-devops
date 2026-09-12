#!/usr/bin/env python3
"""
Utility script for converting between JSON and Base64.
"""

import base64
import json
import sys
from pathlib import Path


def json_to_base64(json_file_path: str) -> str:
    """
    Read a JSON file and convert it into a Base64 string.

    Args:
        json_file_path: Path to the JSON file

    Returns:
        Base64 encoded string

    Raises:
        FileNotFoundError: If the file doesn't exist
        json.JSONDecodeError: If the file isn't valid JSON
    """
    file_path = Path(json_file_path)

    if not file_path.exists():
        raise FileNotFoundError(f"JSON file not found: {json_file_path}")

    with open(file_path, "r", encoding="utf-8") as f:
        json_content = json.load(f)

    json_bytes = json.dumps(json_content).encode("utf-8")
    base64_bytes = base64.b64encode(json_bytes)

    return base64_bytes.decode("utf-8")


def base64_to_json(base64_string: str):
    """
    Read a Base64 string and convert it into a JSON object.

    Args:
        base64_string: Base64 encoded string

    Returns:
        JSON object (dict, list, etc.)

    Raises:
        ValueError: If the Base64 string is invalid
        json.JSONDecodeError: If the decoded content isn't valid JSON
    """
    try:
        base64_bytes = base64_string.encode("utf-8")
        json_bytes = base64.b64decode(base64_bytes)
        json_content = json.loads(json_bytes.decode("utf-8"))
        return json_content
    except Exception as e:
        raise ValueError(f"Failed to decode Base64 to JSON: {e}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="JSON <-> Base64 converter")
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # Encode command
    encode_parser = subparsers.add_parser("encode", help="Convert JSON file to Base64")
    encode_parser.add_argument("file", help="Path to JSON file")

    # Decode command
    decode_parser = subparsers.add_parser("decode", help="Convert Base64 to JSON")
    decode_parser.add_argument("string", help="Base64 encoded string")

    args = parser.parse_args()

    if args.command == "encode":
        try:
            result = json_to_base64(args.file)
            print(result)
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
    elif args.command == "decode":
        try:
            result = base64_to_json(args.string)
            print(json.dumps(result, indent=2))
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        parser.print_help()
        sys.exit(1)
