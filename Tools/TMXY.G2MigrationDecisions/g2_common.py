"""Shared deterministic helpers for P2-20B."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def file_digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), f"JSON root must be an object: {path.name}")
    return value


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    result = []
    with path.open("r", encoding="utf-8-sig") as stream:
        for number, line in enumerate(stream, 1):
            value = json.loads(line)
            require(isinstance(value, dict), f"JSONL record {number} must be an object")
            result.append(value)
    return result


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def safe_repo_path(root: Path, relative: str) -> Path:
    candidate = Path(relative)
    require(relative and "\\" not in relative and not candidate.is_absolute() and
            ".." not in candidate.parts, "Unsafe repository-relative path")
    resolved = (root / candidate).resolve()
    require(resolved.is_relative_to(root) and resolved.is_file(), f"Missing repository input: {relative}")
    return resolved


def manifest_digest(decisions: Iterable[dict[str, Any]]) -> str:
    members = [{"decision_id": item["decision_id"],
                "subject_membership_sha256": item["subject_membership_sha256"]}
               for item in decisions]
    return digest(members)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    path.write_text(normalized, encoding="utf-8", newline="\n")
