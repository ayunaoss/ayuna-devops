"""Script to setup OCI environment for Ayuna local development"""

import argparse
import datetime
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

import yaml
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from dotenv import dotenv_values
from jinja2 import Environment, FileSystemLoader

# Enable ANSI escape codes on Windows via VT processing
if platform.system() == "Windows":
    try:
        import ctypes

        _k32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
        _k32.SetConsoleMode(_k32.GetStdHandle(-11), 0x0007)
    except (OSError, AttributeError) as exc:
        print(f"Warning: could not enable ANSI color support: {exc}", file=sys.stderr)

TRML_HL = "\033[1;35m"
TRML_NC = "\033[0m"

_SCRIPT_DIR = Path(__file__).resolve().parent
_SETUP_CFG_PATH = Path(f"{_SCRIPT_DIR}/setup.yaml")

if not _SETUP_CFG_PATH.exists():
    print(
        f"\033[31m[ERROR]\033[0m Setup config not found: {_SETUP_CFG_PATH}",
        file=sys.stderr,
    )
    sys.exit(1)

with _SETUP_CFG_PATH.open() as _f:
    _cfg = yaml.safe_load(_f)

ENV_TEMPLATES: dict[str, str] = _cfg["env_templates"]
NETWORK_NAME: str = _cfg["network_name"]
BACKEND_VOLUMES: list[str] = _cfg["backend_volumes"]
SQL_DBS: list[str] = _cfg["sql_dbs"]


def echo_info(msg: str) -> None:
    print(f"{TRML_HL}{msg}{TRML_NC}")


def echo_error(msg: str) -> None:
    print(f"\033[31m[ERROR]\033[0m {msg}", file=sys.stderr)


def run(
    cmd: list[str],
    *,
    check: bool = True,
    capture: bool = False,
    env: dict | None = None,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture,
        text=True,
        env={**os.environ, **(env or {})},
    )


def cmd_output(cmd: list[str], env: dict | None = None) -> str:
    result = run(cmd, capture=True, check=False, env=env)
    return result.stdout.strip()


def generate_env_files(oci_path: Path, data_file: Path) -> None:
    tmpl_dir = oci_path / "data" / "tmpl"

    missing = [t for t in ENV_TEMPLATES if not (tmpl_dir / t).exists()]
    if missing:
        for t in missing:
            echo_error(f"Template not found: {tmpl_dir / t}")
        sys.exit(1)

    echo_info("All template files found. Proceeding with env generation.")

    with open(data_file) as f:
        data = yaml.safe_load(f)

    j2env = Environment(  # NOSONAR
        loader=FileSystemLoader(tmpl_dir),
        autoescape=False,
        trim_blocks=True,
        lstrip_blocks=True,
    )

    env_dir = oci_path / "env"
    if env_dir.exists():
        shutil.rmtree(env_dir)

    env_dir.mkdir(parents=True, exist_ok=True)

    for tmpl_name, output_name in ENV_TEMPLATES.items():
        output_path = env_dir / output_name
        output_path.write_text(j2env.get_template(tmpl_name).render(data))
        echo_info(f"Generated {output_path}")


def generate_caddy_certs(oci_path: Path) -> None:
    certs_dir = oci_path / "env" / "ssl"
    certs_dir.mkdir(parents=True, exist_ok=True)

    key_path = certs_dir / "ayunaio.key"
    crt_path = certs_dir / "ayunaio.crt"

    echo_info("Generating self-signed TLS certificates for Caddy...")

    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    key_path.write_bytes(
        private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )

    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "*.ayunaio.internal")])
    now = datetime.datetime.now(datetime.UTC)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=1825))
        .add_extension(
            x509.SubjectAlternativeName(
                [
                    x509.DNSName("*.ayunaio.internal"),
                    x509.DNSName("ayunaio.internal"),
                ]
            ),
            critical=False,
        )
        .sign(private_key, hashes.SHA256())
    )
    crt_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))

    echo_info(f"Certificates written to {certs_dir}")


def check_docker(oci_path: Path) -> None:
    if shutil.which("docker") is None:
        echo_error("Docker could not be found. Please install Docker first.")
        sys.exit(1)

    echo_info("Found Docker installation.")
    echo_info(f"Docker version: {cmd_output(['docker', '--version'])}")
    echo_info(
        f"Docker info: {cmd_output(['docker', 'info', '--format', '{{.ServerVersion}}'])}"
    )

    if not (oci_path / "docker-compose.yaml").is_file():
        echo_error("docker-compose.yaml file not found in the current directory.")
        sys.exit(1)


def clean_environment(force_clean: bool) -> None:
    echo_info("Stopping all running containers...")
    run(["docker", "compose", "down"], check=False)

    dangling = cmd_output(["docker", "images", "-q", "--filter", "dangling=true"])
    if dangling:
        echo_info("Removing dangling docker images...")
        run(["docker", "rmi"] + dangling.split())

    if not force_clean:
        return

    echo_info("Force clean mode enabled. Removing volumes...")
    existing_volumes = cmd_output(["docker", "volume", "ls"])

    for volume in BACKEND_VOLUMES:
        if volume in existing_volumes:
            echo_info(f"Removing Docker volume: {volume}")
            run(["docker", "volume", "rm", volume], check=False)
        else:
            echo_info(f"Docker volume {volume} does not exist.")

    time.sleep(3)


def ensure_network_and_volumes() -> None:
    existing_networks = cmd_output(["docker", "network", "ls"])

    if NETWORK_NAME not in existing_networks:
        echo_info(f"Creating Docker network: {NETWORK_NAME}")
        run(["docker", "network", "create", NETWORK_NAME])
    else:
        echo_info(f"Docker network {NETWORK_NAME} already exists.")

    echo_info("Checking and creating volumes...")
    existing_volumes = cmd_output(["docker", "volume", "ls"])

    for volume in BACKEND_VOLUMES:
        if volume not in existing_volumes:
            echo_info(f"Creating Docker volume: {volume}")
            run(["docker", "volume", "create", volume])
        else:
            echo_info(f"Docker volume {volume} already exists.")


def setup_postgres(pg_env: dict[str, str]) -> None:
    pg_container = "ayuna-pgsql"

    if pg_container not in cmd_output(["docker", "ps", "-a"]):
        echo_info(f"Starting PostgreSQL server {pg_container}")
        # :Z is an SELinux relabeling option; only meaningful on Linux
        vol_mount = f"pgsql_data:/var/lib/postgresql/data{':Z' if platform.system() == 'Linux' else ''}"
        run(
            [
                "docker",
                "run",
                "-d",
                "--name",
                pg_container,
                "--network",
                NETWORK_NAME,
                "-e",
                f"POSTGRES_USER={pg_env['POSTGRES_USER']}",
                "-e",
                f"POSTGRES_PASSWORD={pg_env['POSTGRES_PASSWORD']}",
                "-v",
                vol_mount,
                "-p",
                "5432:5432",
                "pgvector/pgvector:pg17",
            ]
        )
    else:
        echo_info(f"PostgreSQL server {pg_container} is already running.")

    echo_info(f"Waiting for PostgreSQL server {pg_container} to be ready...")
    while True:
        result = run(
            [
                "docker",
                "exec",
                pg_container,
                "pg_isready",
                "-U",
                pg_env["POSTGRES_USER"],
            ],
            check=False,
            capture=True,
        )

        if result.returncode == 0:
            break

        echo_info("PostgreSQL server is not ready yet. Waiting...")
        time.sleep(5)

    echo_info(f"PostgreSQL server {pg_container} is ready.")

    pg_exec_base = [
        "docker",
        "exec",
        "-e",
        f"PGPASSWORD={pg_env['POSTGRES_PASSWORD']}",
        pg_container,
        "psql",
        "-U",
        pg_env["POSTGRES_USER"],
    ]

    for db in SQL_DBS:
        if (
            run(pg_exec_base + [db, "-c", r"\q"], check=False, capture=True).returncode
            == 0
        ):
            echo_info(f"Database {db} already exists.")
        else:
            echo_info(f"Creating database {db} in PostgreSQL server {pg_container}")
            run(pg_exec_base + ["-c", f"CREATE DATABASE {db};"], check=False)
            echo_info(f"Creating pgvector extension in database {db}")
            run(
                pg_exec_base
                + ["-d", db, "-c", "CREATE EXTENSION IF NOT EXISTS vector;"],
                check=False,
            )

    time.sleep(5)
    run(["docker", "stop", pg_container])
    run(["docker", "rm", pg_container])
    echo_info(f"PostgreSQL server {pg_container} has been setup and stopped")


def main() -> None:
    os.chdir(_SCRIPT_DIR)

    parser = argparse.ArgumentParser(
        description="Setup Docker environment for Ayuna local development",
        add_help=False,
    )
    parser.add_argument(
        "--force-clean",
        action="store_true",
        help="Force clean the Docker environment (remove all containers and volumes).",
    )
    parser.add_argument(
        "--env-data",
        metavar="FILE",
        type=Path,
        required=True,
        help="Path to the YAML env-data file.",
    )
    parser.add_argument(
        "--help", "-h", action="store_true", help="Show this help message."
    )
    args = parser.parse_args()

    if args.help:
        echo_info(f"Usage: {sys.argv[0]} [--force-clean] [--env-data FILE]")
        echo_info("Options:")
        echo_info(
            "  --force-clean       Force clean the Docker environment (remove all containers and volumes)."
        )
        echo_info("  --env-data FILE     Path to the YAML env-data file (Required).")
        echo_info("  --help, -h          Show this help message.")
        sys.exit(0)

    original_cwd = Path.cwd()
    data_file = Path(args.env_data).resolve()

    if not data_file.exists():
        echo_error(f"Env-data file not found: {data_file}")
        sys.exit(1)

    check_docker(_SCRIPT_DIR)

    echo_info(f"Using env-data file: {data_file}")
    generate_env_files(_SCRIPT_DIR, data_file)
    generate_caddy_certs(_SCRIPT_DIR)

    ## Push to oci_path and come back to the original directory after the setup is complete
    os.chdir(_SCRIPT_DIR)

    echo_info("Loading environment variables from env/pgsql.env")
    pg_env: dict[str, str] = {
        k: v for k, v in dotenv_values("env/pgsql.env").items() if v is not None
    }
    os.environ.update(pg_env)

    if args.force_clean:
        echo_info(
            "Force clean mode enabled. All existing containers and volumes will be removed."
        )

    clean_environment(args.force_clean)
    ensure_network_and_volumes()
    setup_postgres(pg_env)

    os.chdir(original_cwd)
    echo_info("Docker setup completed successfully.")
    echo_info("You can now run 'docker compose up' to start the services.")
    echo_info(
        "If you want to run the services in detached mode, use 'docker compose up -d'."
    )
    echo_info("To stop the services, use 'docker compose down'.")
    echo_info("To view the logs, use 'docker compose logs -f'.")


if __name__ == "__main__":
    main()
