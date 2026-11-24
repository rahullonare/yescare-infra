#!/usr/bin/env python3
"""
YesCare DigitalOcean Infrastructure Validation Script
======================================================
Validates: API health, Load Balancer, Database connectivity, Spaces upload/download.

Usage:
    # Export terraform outputs first:
    cd digitalocean/envs/prod   # or dev
    export DB_HOST=$(terraform output -raw database_host)
    export DB_PORT=$(terraform output -raw database_port)
    export DB_NAME=$(terraform output -raw database_name)
    export DB_USER=$(terraform output -raw database_user)
    export DB_PASS=$(terraform output -raw database_password)
    export LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    export SPACES_BUCKET=$(terraform output -raw spaces_app_bucket)
    export SPACES_REGION=$(terraform output -raw spaces_endpoint | cut -d/ -f3 | cut -d. -f1)
    export AWS_ACCESS_KEY_ID=$SPACES_ACCESS_KEY
    export AWS_SECRET_ACCESS_KEY=$SPACES_SECRET_KEY

    python3 digitalocean/scripts/validate.py
"""

import os
import sys
import json
import subprocess
import time
import urllib.request
import urllib.error
import socket

PASS = "\033[92m[PASS]\033[0m"
FAIL = "\033[91m[FAIL]\033[0m"
SKIP = "\033[93m[SKIP]\033[0m"
INFO = "\033[94m[INFO]\033[0m"

results = []


def check(name: str, fn):
    try:
        msg = fn()
        print(f"{PASS} {name}: {msg}")
        results.append((name, True, msg))
    except Exception as e:
        print(f"{FAIL} {name}: {e}")
        results.append((name, False, str(e)))


# ─── 1. Load Balancer health ───────────────────────────────────────────────────

def test_lb_reachable():
    lb_ip = os.environ.get("LB_IP", "")
    if not lb_ip:
        raise RuntimeError("LB_IP not set — run: kubectl get svc ingress-nginx-controller -n ingress-nginx ...")
    try:
        req = urllib.request.Request(
            f"http://{lb_ip}/healthz",
            headers={"Host": "healthz"},
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return f"HTTP {resp.status} from {lb_ip}"
    except urllib.error.HTTPError as e:
        if e.code in (404, 200, 301, 302, 308):
            return f"HTTP {e.code} from {lb_ip} (LB is up)"
        raise RuntimeError(f"HTTP {e.code}")
    except urllib.error.URLError as e:
        raise RuntimeError(str(e.reason))


# ─── 2. API health check ───────────────────────────────────────────────────────

def test_api_health():
    domain = os.environ.get("DOMAIN_NAME", "")
    lb_ip = os.environ.get("LB_IP", "")
    api_path = os.environ.get("API_HEALTH_PATH", "/actuator/health")

    if not domain and not lb_ip:
        raise RuntimeError("Neither DOMAIN_NAME nor LB_IP is set")

    base = f"https://{domain}" if domain else f"http://{lb_ip}"
    url = f"{base}{api_path}"
    try:
        req = urllib.request.Request(url)
        ctx = None
        if not domain:
            import ssl
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
            body = resp.read(200).decode("utf-8", errors="replace")
            return f"HTTP {resp.status} — {body[:80]}"
    except urllib.error.HTTPError as e:
        return f"HTTP {e.code} (endpoint exists)"
    except Exception as e:
        raise RuntimeError(f"{url}: {e}")


# ─── 3. Database connectivity ─────────────────────────────────────────────────

def test_db_connection():
    try:
        import psycopg2  # type: ignore
    except ImportError:
        raise RuntimeError("psycopg2 not installed — pip install psycopg2-binary")

    host = os.environ.get("DB_HOST")
    port = int(os.environ.get("DB_PORT", "25060"))
    name = os.environ.get("DB_NAME")
    user = os.environ.get("DB_USER")
    password = os.environ.get("DB_PASS")

    if not all([host, name, user, password]):
        raise RuntimeError("Missing DB_HOST / DB_NAME / DB_USER / DB_PASS env vars")

    conn = psycopg2.connect(
        host=host, port=port, dbname=name, user=user, password=password,
        sslmode="require", connect_timeout=10
    )
    cur = conn.cursor()
    cur.execute("SELECT version();")
    version = cur.fetchone()[0]
    cur.close()
    conn.close()
    return version.split(",")[0]


# ─── 4. Redis reachability (TCP port check) ───────────────────────────────────

def test_redis_tcp():
    host = os.environ.get("REDIS_HOST")
    port = int(os.environ.get("REDIS_PORT", "25061"))

    if not host:
        raise RuntimeError("REDIS_HOST not set — set from terraform output redis_host")

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    try:
        s.connect((host, port))
        s.close()
        return f"{host}:{port} TCP open"
    except Exception as e:
        raise RuntimeError(f"Cannot reach {host}:{port} — {e}")


# ─── 5. Spaces upload / download ─────────────────────────────────────────────

def test_spaces_upload_download():
    try:
        import boto3  # type: ignore
        from botocore.config import Config  # type: ignore
    except ImportError:
        raise RuntimeError("boto3 not installed — pip install boto3")

    bucket = os.environ.get("SPACES_BUCKET")
    region = os.environ.get("SPACES_REGION", "blr1")
    access_key = os.environ.get("AWS_ACCESS_KEY_ID")
    secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY")

    if not all([bucket, access_key, secret_key]):
        raise RuntimeError("Missing SPACES_BUCKET / AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY")

    s3 = boto3.client(
        "s3",
        region_name=region,
        endpoint_url=f"https://{region}.digitaloceanspaces.com",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4"),
    )

    key = f"validate/test-{int(time.time())}.txt"
    payload = b"yescare-infra-validate-ok"

    s3.put_object(Bucket=bucket, Key=key, Body=payload)
    response = s3.get_object(Bucket=bucket, Key=key)
    downloaded = response["Body"].read()
    s3.delete_object(Bucket=bucket, Key=key)

    if downloaded != payload:
        raise RuntimeError("Downloaded content does not match uploaded content")
    return f"Wrote and read {len(payload)} bytes to s3://{bucket}/{key}"


# ─── 6. Kubernetes nodes ready ────────────────────────────────────────────────

def test_k8s_nodes():
    try:
        result = subprocess.run(
            ["kubectl", "get", "nodes", "-o", "json"],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip())

        nodes = json.loads(result.stdout)["items"]
        ready_nodes = []
        for node in nodes:
            conditions = node["status"].get("conditions", [])
            for cond in conditions:
                if cond["type"] == "Ready" and cond["status"] == "True":
                    ready_nodes.append(node["metadata"]["name"])

        if not ready_nodes:
            raise RuntimeError("No nodes in Ready state")
        return f"{len(ready_nodes)}/{len(nodes)} nodes ready: {', '.join(ready_nodes)}"
    except FileNotFoundError:
        raise RuntimeError("kubectl not found — install and configure KUBECONFIG")


# ─── Run all checks ───────────────────────────────────────────────────────────

if __name__ == "__main__":
    print(f"\n{INFO} YesCare DigitalOcean Infrastructure Validation")
    print("=" * 55)

    check("Load Balancer reachable",    test_lb_reachable)
    check("API health endpoint",        test_api_health)
    check("PostgreSQL connectivity",    test_db_connection)
    check("Redis TCP reachable",        test_redis_tcp)
    check("Spaces upload/download",     test_spaces_upload_download)
    check("Kubernetes nodes ready",     test_k8s_nodes)

    print("\n" + "=" * 55)
    passed = sum(1 for _, ok, _ in results if ok)
    total  = len(results)
    print(f"Result: {passed}/{total} checks passed")

    if passed < total:
        print(f"\nFailed checks:")
        for name, ok, msg in results:
            if not ok:
                print(f"  - {name}: {msg}")
        sys.exit(1)
    else:
        print("All checks passed.")
        sys.exit(0)
