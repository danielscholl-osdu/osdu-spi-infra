#!/usr/bin/env python3
# Copyright 2026, Microsoft
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Bootstrap data seed — runs inside a Kubernetes Job.

Creates a default legal tag and loads OSDU reference data via the Storage API.
All service calls use in-cluster FQDNs (no kubectl port-forward).

Environment variables:
  KEYCLOAK_URL              Keycloak base URL (e.g. http://keycloak.platform:8080)
  LEGAL_URL                 Legal service base URL (e.g. http://legal.osdu)
  STORAGE_URL               Storage service base URL (e.g. http://storage.osdu)
  DATA_PARTITION            Data partition ID (e.g. "osdu")
  LEGAL_TAG_NAME            Name for the default legal tag
  DATA_BRANCH               Git ref of data-definitions repo (e.g. "v0.27.0")
  BATCH_SIZE                Records per Storage API PUT (default 500)
  OPENID_PROVIDER_CLIENT_ID      Keycloak client ID (from datafier-secret)
  OPENID_PROVIDER_CLIENT_SECRET  Keycloak client secret (from datafier-secret)

See ADR 0022 for rationale.
"""

import json
import os
import shutil
import sys
import tempfile
import time
import zipfile
from io import BytesIO
from pathlib import Path
import requests as http_requests

# ─── Configuration ───────────────────────────────────────────────────────────

KEYCLOAK_URL = os.environ["KEYCLOAK_URL"]
LEGAL_URL = os.environ["LEGAL_URL"]
STORAGE_URL = os.environ["STORAGE_URL"]
DATA_PARTITION = os.environ["DATA_PARTITION"]
LEGAL_TAG_NAME = os.environ.get("LEGAL_TAG_NAME", "osdu-demo-legaltag")
DATA_BRANCH = os.environ.get("DATA_BRANCH", "v0.27.0")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "500"))
CLIENT_ID = os.environ["OPENID_PROVIDER_CLIENT_ID"]
CLIENT_SECRET = os.environ["OPENID_PROVIDER_CLIENT_SECRET"]

DATA_DEFS_URL = (
    f"https://community.opengroup.org/osdu/data/data-definitions/-/archive/"
    f"{DATA_BRANCH}/data-definitions-{DATA_BRANCH}.zip"
    f"?path=ReferenceValues/Manifests/reference-data"
)

ACL_OWNERS = f"data.default.owners@{DATA_PARTITION}.group"
ACL_VIEWERS = f"data.default.viewers@{DATA_PARTITION}.group"

TEMPLATE_VARS = {
    "{{NAMESPACE}}": DATA_PARTITION,
    "{{DATA_PARTITION_ID}}": DATA_PARTITION,
    "{{DATA_OWNERS_GROUP}}": ACL_OWNERS,
    "{{DATA_VIEWERS_GROUP}}": ACL_VIEWERS,
    "{{LEGAL_TAG}}": LEGAL_TAG_NAME,
}

# ─── Token management ───────────────────────────────────────────────────────

_token: str | None = None
_token_expiry: float = 0.0


def get_token() -> str:
    """Get a Keycloak token, refreshing if within 60 seconds of expiry."""
    global _token, _token_expiry
    if _token and time.time() + 60 < _token_expiry:
        return _token

    token_url = f"{KEYCLOAK_URL}/realms/osdu/protocol/openid-connect/token"
    resp = http_requests.post(token_url, data={
        "grant_type": "client_credentials",
        "scope": "openid",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    }, headers={"Content-Type": "application/x-www-form-urlencoded"}, timeout=15)
    resp.raise_for_status()
    data = resp.json()

    _token = data.get("id_token") or data.get("access_token")
    if not _token:
        raise RuntimeError("Keycloak returned neither id_token nor access_token")
    _token_expiry = time.time() + data.get("expires_in", 300)
    return _token


# ─── HTTP helpers ────────────────────────────────────────────────────────────

def api_request(method: str, url: str, body: bytes | None = None,
                max_retries: int = 3) -> tuple[int, bytes]:
    """Make an authenticated API request with retry and token refresh."""
    for attempt in range(1, max_retries + 1):
        token = get_token()
        headers = {
            "Content-Type": "application/json",
            "data-partition-id": DATA_PARTITION,
            "Authorization": f"Bearer {token}",
        }
        try:
            resp = http_requests.request(method, url, data=body,
                                         headers=headers, timeout=120)
            if resp.status_code == 409:
                return 409, resp.content
            resp.raise_for_status()
            return resp.status_code, resp.content
        except http_requests.exceptions.HTTPError as e:
            status = e.response.status_code if e.response is not None else 0
            resp_body = e.response.content if e.response is not None else b""
            if status == 401:
                global _token
                _token = None  # force refresh
            if attempt == max_retries:
                print(f"  HTTP {status}: {resp_body[:200].decode(errors='replace')}")
                raise
            print(f"  Retry {attempt}/{max_retries} (HTTP {status})...")
            time.sleep(attempt * 2)
        except Exception:
            if attempt == max_retries:
                raise
            print(f"  Retry {attempt}/{max_retries} (connection error)...")
            time.sleep(attempt * 2)
    raise RuntimeError("Unreachable")


# ─── Template substitution ───────────────────────────────────────────────────

def substitute_templates(content: str) -> str:
    for placeholder, value in TEMPLATE_VARS.items():
        content = content.replace(placeholder, value)
    return content


def repair_record(record: dict) -> dict:
    record["acl"] = {"owners": [ACL_OWNERS], "viewers": [ACL_VIEWERS]}
    record["legal"] = {
        "legaltags": [LEGAL_TAG_NAME],
        "otherRelevantDataCountries": ["US"],
    }
    return record


# ─── Phase 1: Legal tag ─────────────────────────────────────────────────────

def create_legal_tag() -> None:
    body = json.dumps({
        "name": LEGAL_TAG_NAME,
        "description": "A legal tag used for uploading initial sample data",
        "properties": {
            "countryOfOrigin": ["US"],
            "contractId": "No Contract Related",
            "expirationDate": "2099-01-01",
            "dataType": "Public Domain Data",
            "originator": "OSDU",
            "securityClassification": "Public",
            "exportClassification": "EAR99",
            "personalData": "No Personal Data",
        },
    }).encode()

    url = f"{LEGAL_URL}/api/legal/v1/legaltags"
    status, _ = api_request("POST", url, body)
    if status == 201:
        print(f"  Legal tag '{LEGAL_TAG_NAME}' created.")
    elif status == 409:
        print(f"  Legal tag '{LEGAL_TAG_NAME}' already exists (OK).")


# ─── Phase 2: Download and load reference data ──────────────────────────────

def download_reference_data() -> Path:
    """Download and extract reference data, return extraction path."""
    print(f"  Downloading reference data (branch: {DATA_BRANCH})...")
    resp = http_requests.get(DATA_DEFS_URL, timeout=180)
    resp.raise_for_status()
    data = resp.content

    size_mb = len(data) / (1024 * 1024)
    print(f"  Downloaded {size_mb:.1f} MB")

    extract_path = Path(tempfile.mkdtemp(prefix="cimpl-refdata-"))

    with zipfile.ZipFile(BytesIO(data)) as zf:
        zf.extractall(extract_path)

    return extract_path


def collect_manifests(extract_path: Path) -> list[Path]:
    """Collect manifest files using IngestionSequence.json when available."""
    sequence_files = list(extract_path.rglob("IngestionSequence.json"))
    skip_names = {"IngestionSequence.json", "ReferenceValueTypeDependencies.json"}

    if sequence_files:
        seq_file = sequence_files[0]
        print("  Using IngestionSequence.json for manifest ordering")
        with open(seq_file) as f:
            sequence = json.load(f)
        manifests = []
        for entry in sequence:
            rel_path = entry.get("FileName", "")
            if not rel_path:
                continue
            filename = Path(rel_path).name
            matches = list(extract_path.rglob(filename))
            for m in matches:
                if m.name not in skip_names:
                    manifests.append(m)
                    break
        if manifests:
            return manifests

    print("  Using filename sort order")
    return sorted(
        p for p in extract_path.rglob("*.json")
        if p.name not in skip_names
    )


def extract_records(manifest: dict) -> list[dict]:
    """Extract records from a parsed manifest."""
    records = []
    for key in ("ReferenceData", "MasterData", "Data"):
        val = manifest.get(key)
        if isinstance(val, list):
            records.extend(r for r in val if isinstance(r, dict))
    return records


def load_reference_data() -> tuple[int, int]:
    """Download, parse, and load reference data. Returns (loaded, failed)."""
    extract_path = download_reference_data()

    try:
        manifests = collect_manifests(extract_path)
        print(f"  Found {len(manifests)} manifest files")

        loaded = 0
        failed = 0
        seen_ids: set[str] = set()
        storage_url = f"{STORAGE_URL}/api/storage/v2/records?skipdupes=true"

        for idx, manifest_path in enumerate(manifests, 1):
            try:
                raw = manifest_path.read_text(encoding="utf-8")
                content = substitute_templates(raw)
                manifest = json.loads(content)

                records = []
                for record in extract_records(manifest):
                    rid = record.get("id", "")
                    if not rid or rid in seen_ids:
                        continue
                    seen_ids.add(rid)
                    records.append(repair_record(record))

                # Submit in batches
                for i in range(0, len(records), BATCH_SIZE):
                    batch = records[i:i + BATCH_SIZE]
                    body = json.dumps(batch).encode()
                    try:
                        status, _ = api_request("PUT", storage_url, body)
                        if status in (200, 201, 409):
                            loaded += len(batch)
                        else:
                            failed += len(batch)
                    except Exception as e:
                        failed += len(batch)
                        print(f"  WARNING: {manifest_path.name} batch failed: {e}")

            except Exception as e:
                print(f"  WARNING: {manifest_path.name}: {e}")

            if idx % 50 == 0 or idx == len(manifests):
                print(f"  PROGRESS: [{idx}/{len(manifests)}] loaded={loaded} failed={failed}")

    finally:
        shutil.rmtree(extract_path, ignore_errors=True)

    return loaded, failed


# ─── Service readiness ──────────────────────────────────────────────────────

def wait_for_services(max_wait: int = 300, interval: int = 10) -> None:
    """Wait for Keycloak, Legal, and Storage to respond before proceeding."""
    endpoints = {
        "Keycloak": f"{KEYCLOAK_URL}/realms/osdu/.well-known/openid-configuration",
        "Legal": f"{LEGAL_URL}/api/legal/v1/info",
        "Storage": f"{STORAGE_URL}/api/storage/v2/info",
    }

    for name, url in endpoints.items():
        elapsed = 0
        while elapsed < max_wait:
            try:
                resp = http_requests.get(url, timeout=5)
                if resp.status_code < 500:
                    print(f"  {name}: ready (HTTP {resp.status_code})")
                    break
            except Exception:
                pass
            if elapsed == 0:
                print(f"  Waiting for {name} at {url}...")
            time.sleep(interval)
            elapsed += interval
        else:
            raise RuntimeError(
                f"{name} not ready after {max_wait}s at {url}"
            )


# ─── Main ────────────────────────────────────────────────────────────────────

def main() -> int:
    print("\n" + "=" * 56)
    print("  Phase 0: Waiting for service readiness")
    print("=" * 56)
    wait_for_services()

    print("\n" + "=" * 56)
    print("  Phase 1: Verifying credentials")
    print("=" * 56)
    get_token()
    print(f"  Credentials verified for client '{CLIENT_ID}'")

    print("\n" + "=" * 56)
    print("  Phase 2: Creating default legal tag")
    print("=" * 56)
    create_legal_tag()

    print("\n" + "=" * 56)
    print(f"  Phase 3: Loading reference data (branch: {DATA_BRANCH})")
    print("=" * 56)
    loaded, failed = load_reference_data()

    total = loaded + failed
    fail_rate = failed / total if total > 0 else 0.0

    print("\n" + "=" * 56)
    print(f"  Bootstrap complete: {loaded} loaded, {failed} failed")
    print("=" * 56 + "\n")

    if failed > 0 and fail_rate > 0.01:
        print(f"  FAIL: failure rate {fail_rate * 100:.2f}% exceeds 1% threshold")
        return 1
    if failed > 0:
        print(f"  WARNING: {failed} records failed ({fail_rate * 100:.2f}%) — below threshold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
