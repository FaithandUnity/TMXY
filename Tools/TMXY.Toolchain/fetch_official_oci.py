#!/usr/bin/env python3
"""Fetch one official Registry platform image into a verified OCI layout."""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
from pathlib import Path
import socket
import ssl
import subprocess
import tarfile
import urllib.parse
import urllib.request


REGISTRY_HOST = "registry-1.docker.io"
REPOSITORY = "library/debian"
INDEX_ACCEPT = (
    "application/vnd.oci.image.index.v1+json, "
    "application/vnd.docker.distribution.manifest.list.v2+json"
)
MANIFEST_ACCEPT = (
    "application/vnd.oci.image.manifest.v1+json, "
    "application/vnd.docker.distribution.manifest.v2+json"
)


class ResolvedHttpsConnection(http.client.HTTPSConnection):
    def __init__(self, host: str, address: str, timeout: int = 30) -> None:
        super().__init__(host, timeout=timeout, context=ssl.create_default_context())
        self._address = address

    def connect(self) -> None:
        raw_socket = socket.create_connection((self._address, self.port), self.timeout)
        self.sock = self._context.wrap_socket(raw_socket, server_hostname=self.host)


def sha256_bytes(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def fetch_token() -> str:
    query = urllib.parse.urlencode(
        {"service": "registry.docker.io", "scope": f"repository:{REPOSITORY}:pull"}
    )
    request = urllib.request.Request(f"https://auth.docker.io/token?{query}")
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
    token = payload.get("token")
    if not isinstance(token, str) or not token:
        raise RuntimeError("Docker authorization service returned no bearer token")
    return token


def registry_response(
    address: str, token: str, path: str, accept: str | None = None
) -> tuple[http.client.HTTPResponse, str]:
    connection = ResolvedHttpsConnection(REGISTRY_HOST, address)
    headers = {"Authorization": f"Bearer {token}"}
    if accept:
        headers["Accept"] = accept
    connection.request("GET", path, headers=headers)
    certificate = connection.sock.getpeercert(binary_form=True)
    response = connection.getresponse()
    if response.status not in (200, 302, 307):
        body = response.read(512).decode("utf-8", errors="replace")
        raise RuntimeError(f"Registry request failed: {response.status} {body}")
    return response, hashlib.sha256(certificate).hexdigest()


def fetch_manifest(
    address: str, token: str, reference: str, accept: str
) -> tuple[bytes, dict[str, str], str]:
    path = f"/v2/{REPOSITORY}/manifests/{reference}"
    response, certificate_hash = registry_response(address, token, path, accept)
    body = response.read()
    headers = {key.lower(): value for key, value in response.getheaders()}
    return body, headers, certificate_hash


def fetch_blob(address: str, token: str, descriptor: dict, destination: Path) -> dict:
    digest = str(descriptor["digest"])
    expected_size = int(descriptor["size"])
    path = f"/v2/{REPOSITORY}/blobs/{digest}"
    command = [
        "curl",
        "--config",
        "-",
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--max-time",
        "180",
        "--resolve",
        f"{REGISTRY_HOST}:443:{address}",
        "--output",
        str(destination),
        f"https://{REGISTRY_HOST}{path}",
    ]
    curl_config = f'header = "Authorization: Bearer {token}"\n'.encode("utf-8")
    result = subprocess.run(command, input=curl_config, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"Blob download failed for {digest}: curl={result.returncode}")
    actual_size = destination.stat().st_size
    actual_digest = sha256_file(destination)
    if actual_size != expected_size or actual_digest != digest:
        raise RuntimeError(
            f"Blob verification failed for {digest}: size={actual_size}, hash={actual_digest}"
        )
    return {"digest": digest, "size": actual_size, "media_type": descriptor["mediaType"]}


def write_json(path: Path, payload: object) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry-address", required=True)
    parser.add_argument("--tag", default="bookworm-slim")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output).resolve()
    layout = output / "layout"
    blob_root = layout / "blobs" / "sha256"
    evidence_root = output / "evidence"
    blob_root.mkdir(parents=True, exist_ok=False)
    evidence_root.mkdir(parents=True, exist_ok=False)

    token = fetch_token()
    index_body, index_headers, certificate_hash = fetch_manifest(
        args.registry_address, token, args.tag, INDEX_ACCEPT
    )
    index_digest = sha256_bytes(index_body)
    header_digest = index_headers.get("docker-content-digest", "")
    if index_digest != header_digest:
        raise RuntimeError(
            f"Index digest mismatch: body={index_digest}, header={header_digest}"
        )
    source_index_path = evidence_root / "official-index.json"
    source_index_path.write_bytes(index_body)
    (blob_root / index_digest.removeprefix("sha256:")).write_bytes(index_body)
    source_index = json.loads(index_body)
    candidates = [
        item
        for item in source_index.get("manifests", [])
        if item.get("platform", {}).get("os") == "linux"
        and item.get("platform", {}).get("architecture") == "amd64"
    ]
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one linux/amd64 manifest, found {len(candidates)}")
    platform_descriptor = candidates[0]
    manifest_digest = str(platform_descriptor["digest"])
    manifest_body, manifest_headers, manifest_certificate_hash = fetch_manifest(
        args.registry_address, token, manifest_digest, MANIFEST_ACCEPT
    )
    if sha256_bytes(manifest_body) != manifest_digest:
        raise RuntimeError("Platform manifest body digest does not match its descriptor")
    if int(platform_descriptor["size"]) != len(manifest_body):
        raise RuntimeError("Platform manifest body size does not match its descriptor")
    returned_manifest_digest = manifest_headers.get("docker-content-digest", "")
    if returned_manifest_digest and returned_manifest_digest != manifest_digest:
        raise RuntimeError("Registry returned a different platform manifest digest")
    manifest_path = blob_root / manifest_digest.removeprefix("sha256:")
    manifest_path.write_bytes(manifest_body)
    manifest = json.loads(manifest_body)

    descriptors = [manifest["config"], *manifest.get("layers", [])]
    verified_blobs = []
    for descriptor in descriptors:
        digest = str(descriptor["digest"])
        destination = blob_root / digest.removeprefix("sha256:")
        verified_blobs.append(fetch_blob(args.registry_address, token, descriptor, destination))

    write_json(layout / "oci-layout", {"imageLayoutVersion": "1.0.0"})
    imported_descriptor = {
        "mediaType": source_index["mediaType"],
        "digest": index_digest,
        "size": len(index_body),
        "annotations": {
            "containerd.io/distribution.source.docker.io": REPOSITORY,
            "io.containerd.image.name": f"docker.io/{REPOSITORY}:{args.tag}",
            "org.opencontainers.image.ref.name": args.tag,
        },
    }
    write_json(
        layout / "index.json",
        {
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.index.v1+json",
            "manifests": [imported_descriptor],
        },
    )
    write_json(
        layout / "manifest.json",
        [
            {
                "Config": f"blobs/sha256/{str(manifest['config']['digest']).removeprefix('sha256:')}",
                "RepoTags": [f"debian:{args.tag}"],
                "Layers": [
                    f"blobs/sha256/{str(layer['digest']).removeprefix('sha256:')}"
                    for layer in manifest.get("layers", [])
                ],
            }
        ],
    )
    archive_path = output / "debian-bookworm-slim.oci.tar"
    with tarfile.open(archive_path, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for name in ("oci-layout", "index.json", "manifest.json", "blobs"):
            archive.add(layout / name, arcname=name, recursive=True)

    result = {
        "registry": REGISTRY_HOST,
        "repository": REPOSITORY,
        "tag": args.tag,
        "tls_verified": True,
        "registry_certificate_sha256": certificate_hash,
        "manifest_certificate_same": certificate_hash == manifest_certificate_hash,
        "official_index": {
            "digest": index_digest,
            "size": len(index_body),
            "media_type": source_index["mediaType"],
        },
        "platform_manifest": {
            "digest": manifest_digest,
            "size": len(manifest_body),
            "media_type": platform_descriptor["mediaType"],
            "os": "linux",
            "architecture": "amd64",
        },
        "config": verified_blobs[0],
        "layers": verified_blobs[1:],
        "archive": {
            "file": archive_path.name,
            "size": archive_path.stat().st_size,
            "sha256": sha256_file(archive_path),
        },
    }
    write_json(output / "fetch-result.json", result)
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    main()
