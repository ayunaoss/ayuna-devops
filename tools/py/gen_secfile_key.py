# /// script
# requires-python = ">=3.12,<3.14"
# dependencies = [
#   "cryptography",
# ]
# ///

from cryptography.fernet import Fernet

master_key = Fernet.generate_key().decode()

print(f"Generated Fernet key: {master_key}")
print("\n# To pass this via env, add the following to your .env file:")
print(f"AYUNA_SECFILE_MASTER_KEY='{master_key}'")
