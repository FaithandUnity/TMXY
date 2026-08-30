"""Disclosure-safe support for source-derived malformed-XML diagnostics.

No function in this module serializes an input path, XML name, XML scalar, or
parser error text.  TinyXML results are rebuilt from source and are diagnostic
only; they are not historical binary, runtime, Windows CRT, or memory-tail
parity evidence.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


KNOWN_PARTIAL_CONTENT_SHA256 = (
    "10302e38d179050923d4088bbb785a658aac16d1037a6c4c6ff4caf3240730ba"
)
EXPECTED_INPUT_SHA256 = frozenset({
    "06de05771dd777fe08a82ffa761f14c3173e169f32b84a22ab1df1c120cc927b",
    KNOWN_PARTIAL_CONTENT_SHA256,
    "1de6d26e2b8aadd0dc83aba03d3d6bfe920881c584b2fe33e5afb89e1d42f9ec",
    "39f83e58609ee8e88c455d650eeabcc24ee61c40545606aa466bddf92ef04970",
    "a9f147bd54c1354d48919e6d3f4bec13a4c19fbe5628923fb4d08786456c547b",
    "c1c84447a7cfaa11b934e55020ce7f29725001b5701339f26eef4d844d5eae01",
})
SOURCE_FILES = (
    "tinystr.cpp", "tinystr.h", "tinyxml.cpp", "tinyxml.h",
    "tinyxmlerror.cpp", "tinyxmlparser.cpp",
)
COMPILE_UNITS = (
    "tinyxml.cpp", "tinyxmlerror.cpp", "tinyxmlparser.cpp", "tinystr.cpp",
)
EXPECTED_SOURCE_HASHES: dict[str, dict[str, str]] = {
    "client": {
        "tinystr.cpp": "5c69220764ca7575abf59e062a1bf40dbc94aa20ab1989a92e5d5d0afbf86052",
        "tinystr.h": "9045654e46ea0f1f0fae25b89768e66723fab27754baa6090df4febd732c0412",
        "tinyxml.cpp": "30630b58cf6e4c984fa1a692b6daadf95caeb5af444ba729f57a45c89af378fc",
        "tinyxml.h": "f8d69dc35242d9ba7132203f14122b29fb7b95798f35fc29dc4d63abfcad6d98",
        "tinyxmlerror.cpp": "d74ff9be4a320f0933d399799220d2b2f5ff0acc9c40c951aa5694b92b9871ef",
        "tinyxmlparser.cpp": "c586adaee04634fa0d8f4063f83a7f6fe510cfb70d95401724b692676bc9859b",
    },
    "server": {
        "tinystr.cpp": "5c69220764ca7575abf59e062a1bf40dbc94aa20ab1989a92e5d5d0afbf86052",
        "tinystr.h": "9045654e46ea0f1f0fae25b89768e66723fab27754baa6090df4febd732c0412",
        "tinyxml.cpp": "bd6b363b0b43c9cb059831e04978879f9d8758197e63dd9e0562406c5db96246",
        "tinyxml.h": "e4ea963af819f872750c278912c51eb0a313895256cfde7774d3a250ce56af44",
        "tinyxmlerror.cpp": "d74ff9be4a320f0933d399799220d2b2f5ff0acc9c40c951aa5694b92b9871ef",
        "tinyxmlparser.cpp": "c586adaee04634fa0d8f4063f83a7f6fe510cfb70d95401724b692676bc9859b",
    },
}
EXPECTED_SOURCE_SET_SHA256 = {
    "client": "0f26c4e1f3630576635bffdba16b03a921ee5921896c12e386cde711d37499c2",
    "server": "1056cbb66b3b0f429871422c2d6698f8ca8a7ca75ca379dd7e8b0e6b80e9b575",
}
EXPECTED_TREE_TOTALS = {
    "nodes": 13319, "elements": 12673, "attributes": 59141,
    "texts": 28, "comments": 618,
}
TREE_FIELDS = tuple(EXPECTED_TREE_TOTALS)
_HEX_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_DTD = re.compile(r"<!\s*DOCTYPE\b", re.IGNORECASE)
_ENTITY = re.compile(r"<!\s*ENTITY\b", re.IGNORECASE)
_PROBE_FIELDS = frozenset({
    "family", "member", "content_sha256", "input_read_success",
    "load_file_success", "load_file_error_flag", "load_file_error_id",
    "load_file_error_line", "load_file_error_column", "load_file_root_present",
    "direct_parse_returned_null", "direct_parse_returned_offset",
    "direct_parse_error_flag", "direct_parse_error_id",
    "direct_parse_error_line", "direct_parse_error_column",
    "direct_parse_root_present", "full_input_consumed",
    "direct_parse_null_partial_tree", "probe_input_nul_appended",
    *TREE_FIELDS,
})


class EvidenceError(RuntimeError):
    """Raised when a disclosure or evidence boundary fails closed."""


@dataclass(frozen=True)
class ProbeInput:
    """An input binding whose filesystem location is never serialized."""

    member: int
    content_sha256: str
    path: Path = field(repr=False)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def sha256_bytes(value: bytes | bytearray | memoryview) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def string_set_sha256(values: Iterable[str]) -> str:
    digest = hashlib.sha256()
    for value in sorted(set(values)):
        raw = value.encode("utf-8", errors="strict")
        digest.update(len(raw).to_bytes(8, "big"))
        digest.update(raw)
    return digest.hexdigest()


def _domain_hash(domain: str, *parts: str) -> str:
    return string_set_sha256((f"{domain}:{index}:{part}"
                              for index, part in enumerate(parts)))


def resolve_inside(root: Path, relative: object, label: str) -> Path:
    resolved_root = root.resolve(strict=True)
    require(resolved_root.is_dir(), f"{label} root is not a directory")
    require(isinstance(relative, str) and relative and "\\" not in relative and
            "\x00" not in relative, f"{label} path is not portable")
    candidate = Path(relative)
    require(not candidate.is_absolute() and ".." not in candidate.parts,
            f"{label} path escaped its root")
    resolved = (resolved_root / candidate).resolve(strict=True)
    require(resolved.is_file() and resolved.is_relative_to(resolved_root),
            f"{label} path escaped its root")
    return resolved


def strict_gbk_decode(source: bytes | bytearray | memoryview) -> str:
    try:
        return bytes(source).decode("gbk", errors="strict")
    except UnicodeDecodeError as error:
        raise EvidenceError("input is not strict GBK") from error


def profile_bytes(source: bytes | bytearray | memoryview) -> dict[str, Any]:
    raw = bytes(source)
    crlf = raw.count(b"\r\n")
    lone_lf = raw.count(b"\n") - crlf
    lone_cr = raw.count(b"\r") - crlf
    try:
        text = strict_gbk_decode(raw)
    except EvidenceError:
        text = None
    return {
        "bytes": len(raw),
        "gbk_strict_decodable": text is not None,
        "crlf": crlf,
        "lone_lf": lone_lf,
        "lone_cr": lone_cr,
        "nul": raw.count(b"\x00"),
        "trailing_crlf": raw.endswith(b"\r\n"),
        "dtd_declaration_detected": None if text is None else bool(_DTD.search(text)),
        "entity_declaration_detected": None if text is None else bool(_ENTITY.search(text)),
    }


def _elementtree_shape(root: ET.Element) -> dict[str, int]:
    result = {"nodes": 0, "elements": 0, "attributes": 0, "texts": 0}

    def visit(element: ET.Element) -> None:
        result["nodes"] += 1
        result["elements"] += 1
        result["attributes"] += len(element.attrib)
        result["texts"] += int(bool(element.text))
        for child in list(element):
            visit(child)
            result["texts"] += int(bool(child.tail))

    visit(root)
    return result


def probe_elementtree(text: str) -> dict[str, Any]:
    require(isinstance(text, str), "ElementTree input is not text")
    if _DTD.search(text) or _ENTITY.search(text):
        return {
            "accepted": False,
            "error_code": -2,
            "error_class_code": "ELEMENTTREE_PARSE_ERROR",
            "failure_location_sha256": _domain_hash(
                "g2-a11-elementtree-location-v1", "not-exposed"),
            "tree_shape": None,
        }
    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        line, column = getattr(error, "position", (-1, -1))
        return {
            "accepted": False,
            "error_code": int(getattr(error, "code", -1)),
            "error_class_code": "ELEMENTTREE_PARSE_ERROR",
            "failure_location_sha256": _domain_hash(
                "g2-a11-elementtree-location-v1", str(line), str(column)),
            "tree_shape": None,
        }
    return {
        "accepted": True,
        "error_code": None,
        "error_class_code": None,
        "failure_location_sha256": None,
        "tree_shape": _elementtree_shape(root),
    }


def _source_set_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for name in sorted(SOURCE_FILES):
        raw = (root / name).read_bytes()
        encoded = name.encode("utf-8")
        digest.update(encoded)
        digest.update(b"\x00")
        digest.update(str(len(raw)).encode("ascii"))
        digest.update(b"\x00")
        digest.update(raw)
        digest.update(b"\x00")
    return digest.hexdigest()


def load_source_bindings(client_root: Path, server_root: Path) -> dict[str, Any]:
    roots = {"client": client_root.resolve(strict=True),
             "server": server_root.resolve(strict=True)}
    result: dict[str, Any] = {}
    for family, root in roots.items():
        require(root.is_dir(), f"{family} TinyXML source root is absent")
        discovered = {path.name for path in root.iterdir()
                      if path.is_file() and path.suffix.lower() in {".cpp", ".h"}}
        require(discovered == set(SOURCE_FILES),
                f"{family} TinyXML source membership drifted")
        files = []
        for member, name in enumerate(sorted(SOURCE_FILES)):
            path = root / name
            digest = sha256_file(path)
            require(digest == EXPECTED_SOURCE_HASHES[family][name],
                    f"{family} TinyXML source hash drifted")
            files.append({"member": member, "bytes": path.stat().st_size,
                          "sha256": digest})
        source_set = _source_set_sha256(root)
        require(source_set == EXPECTED_SOURCE_SET_SHA256[family],
                f"{family} TinyXML source-set hash drifted")
        result[family] = {
            "family": family,
            "source_file_count": len(files),
            "source_set_sha256": source_set,
            "files": files,
        }
    return result


def make_probe_input(root: Path, relative: object, member: int) -> ProbeInput:
    require(isinstance(member, int) and not isinstance(member, bool) and member >= 0,
            "probe member is invalid")
    path = resolve_inside(root, relative, "malformed XML input")
    return ProbeInput(member=member, content_sha256=sha256_file(path), path=path)


def _run_closed(command: Sequence[str], timeout: int) -> subprocess.CompletedProcess[bytes]:
    environment = dict(os.environ)
    environment.update({"LC_ALL": "C", "LANG": "C"})
    try:
        result = subprocess.run(command, check=False, capture_output=True,
                                timeout=timeout, env=environment)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise EvidenceError("closed subprocess did not complete") from error
    require(len(result.stdout) <= 4 * 1024 * 1024 and
            len(result.stderr) <= 4 * 1024 * 1024,
            "closed subprocess output exceeded its limit")
    return result


def _validate_probe_record(record: object, family: str,
                           binding: ProbeInput) -> dict[str, Any]:
    require(isinstance(record, dict) and frozenset(record) == _PROBE_FIELDS,
            "TinyXML probe record violates its closed schema")
    require(record["family"] == family and
            isinstance(record["member"], int) and not isinstance(record["member"], bool) and
            record["member"] == binding.member and
            record["content_sha256"] == binding.content_sha256,
            "TinyXML probe identity binding drifted")
    bool_fields = (
        "input_read_success", "load_file_success", "load_file_error_flag",
        "load_file_root_present", "direct_parse_returned_null",
        "direct_parse_error_flag", "direct_parse_root_present",
        "full_input_consumed", "direct_parse_null_partial_tree",
        "probe_input_nul_appended",
    )
    require(all(isinstance(record[field], bool) for field in bool_fields) and
            record["input_read_success"] and record["probe_input_nul_appended"],
            "TinyXML probe boolean contract drifted")
    for field in ("load_file_error_id", "direct_parse_error_id", *TREE_FIELDS):
        require(isinstance(record[field], int) and not isinstance(record[field], bool)
                and record[field] >= 0, "TinyXML probe count is invalid")
    for field in ("load_file_error_line", "load_file_error_column",
                  "direct_parse_returned_offset", "direct_parse_error_line",
                  "direct_parse_error_column"):
        value = record[field]
        require(value is None or (isinstance(value, int) and not isinstance(value, bool)
                                  and value >= 0),
                "TinyXML probe optional offset is invalid")
    require(sha256_file(binding.path) == binding.content_sha256,
            "TinyXML probe input hash drifted")
    return record


def _parse_probe_output(raw: bytes, family: str,
                        inputs: Sequence[ProbeInput]) -> list[dict[str, Any]]:
    lines = raw.splitlines()
    require(len(lines) == len(inputs), "TinyXML probe result count drifted")
    records: list[dict[str, Any]] = []
    for line, binding in zip(lines, inputs, strict=True):
        require(len(line) <= 16384, "TinyXML probe record exceeded its limit")
        try:
            record = json.loads(line)
        except (UnicodeError, json.JSONDecodeError) as error:
            raise EvidenceError("TinyXML probe emitted invalid JSON") from error
        records.append(_validate_probe_record(record, family, binding))
    return records


def compile_and_run_tinyxml_probes(
        probe_source: Path,
        client_source_root: Path,
        server_source_root: Path,
        inputs: Sequence[ProbeInput],
        compiler: str = "clang++-21",
        timeout_seconds: int = 180,
        work_root: Path | None = None) -> dict[str, Any]:
    """Build two non-STL source probes and return only closed anonymous JSON."""
    require(Path(compiler).name == "clang++-21", "compiler must be clang++-21")
    compiler_path = shutil.which(compiler)
    require(compiler_path is not None, "clang++-21 is unavailable")
    version = _run_closed((compiler_path, "--version"), 30)
    require(version.returncode == 0 and re.search(rb"clang version 21(?:\.|\s)",
                                                  version.stdout + version.stderr),
            "compiler is not Clang 21")
    probe_path = probe_source.resolve(strict=True)
    require(probe_path.is_file(), "TinyXML probe source is absent")
    bindings = load_source_bindings(client_source_root, server_source_root)
    roots = {"client": client_source_root.resolve(strict=True),
             "server": server_source_root.resolve(strict=True)}
    ordered = sorted(inputs, key=lambda item: item.member)
    require([item.member for item in ordered] == list(range(6)) and
            len({item.content_sha256 for item in ordered}) == 6 and
            {item.content_sha256 for item in ordered} == EXPECTED_INPUT_SHA256,
            "malformed XML probe population drifted")
    for item in ordered:
        require(_HEX_SHA256.fullmatch(item.content_sha256) is not None and
                sha256_file(item.path) == item.content_sha256,
                "malformed XML probe content binding drifted")

    records: list[dict[str, Any]] = []
    builds: dict[str, Any] = {}
    temporary_parent = None if work_root is None else work_root.resolve(strict=True)
    require(temporary_parent is None or temporary_parent.is_dir(),
            "TinyXML probe work root is not a directory")
    with tempfile.TemporaryDirectory(prefix="tmxy-a11-tinyxml-",
                                     dir=temporary_parent) as temporary:
        temporary_root = Path(temporary)
        for family in ("client", "server"):
            binary = temporary_root / f"probe-{family}"
            source_root = roots[family]
            command = [
                compiler_path, "-std=c++20", "-O2", "-g0", "-Wall", "-Wextra",
                "-Wpedantic", "-Werror=return-type", "-fno-diagnostics-color",
                "-UTIXML_USE_STL", f"-I{source_root}", str(probe_path),
                *(str(source_root / unit) for unit in COMPILE_UNITS),
                "-o", str(binary),
            ]
            compiled = _run_closed(command, timeout_seconds)
            require(compiled.returncode == 0 and binary.is_file(),
                    f"{family} source-derived TinyXML compilation failed")
            run_command = [str(binary), family]
            for item in ordered:
                run_command.extend((str(item.path), item.content_sha256))
            executed = _run_closed(run_command, timeout_seconds)
            require(executed.returncode == 0 and not executed.stderr,
                    f"{family} source-derived TinyXML probe failed")
            family_records = _parse_probe_output(executed.stdout, family, ordered)
            records.extend(family_records)
            builds[family] = {
                "binary_sha256": sha256_file(binary),
                "compile_warning_count": compiled.stderr.count(b"warning:"),
            }

    totals: dict[str, dict[str, int]] = {}
    for family in ("client", "server"):
        family_records = [item for item in records if item["family"] == family]
        totals[family] = {field: sum(item[field] for item in family_records)
                          for field in TREE_FIELDS}
        require(totals[family] == EXPECTED_TREE_TOTALS,
                f"{family} TinyXML anonymous tree totals drifted")
    comparable = lambda item: {key: value for key, value in item.items()
                               if key != "family"}
    require([comparable(item) for item in records[:6]] ==
            [comparable(item) for item in records[6:]],
            "client and server TinyXML probe results diverged")
    partial = [item for item in records
               if item["content_sha256"] == KNOWN_PARTIAL_CONTENT_SHA256]
    require(len(partial) == 2 and all(
        item["load_file_success"] and not item["load_file_error_flag"] and
        item["load_file_root_present"] and item["direct_parse_returned_null"] and
        not item["direct_parse_error_flag"] and item["direct_parse_root_present"] and
        not item["full_input_consumed"] and item["direct_parse_null_partial_tree"] and
        item["elements"] == 132 and item["attributes"] == 529
        for item in partial),
        "known TinyXML API-success/Parse-null partial tree was not captured")
    return {
        "compiler": {
            "executable": "clang++-21",
            "major": 21,
            "version_output_sha256": sha256_bytes(version.stdout + version.stderr),
        },
        "probe_source_sha256": sha256_file(probe_path),
        "source_bindings": bindings,
        "builds": builds,
        "records": records,
        "totals": totals,
        "known_partial_content": {
            "content_sha256": KNOWN_PARTIAL_CONTENT_SHA256,
            "family_records": 2,
            "load_file_api_success": True,
            "direct_parse_returned_null": True,
            "partial_tree_elements": 132,
            "partial_tree_attributes": 529,
        },
        "evidence_boundary": {
            "source_derived_only": True,
            "legacy_binary_executed": False,
            "runtime_parity_claimed": False,
            "windows_crt_parity_claimed": False,
            "null_tail_parity_claimed": False,
            "probe_input_nul_appended": True,
            "client_input_null_termination_proven": False,
            "runtime_memory_tail_observed": False,
            "api_success_grants_disposition": False,
        },
    }


def run_self_test() -> dict[str, Any]:
    assertions = 0
    require(string_set_sha256(("b", "a", "a")) ==
            string_set_sha256(("a", "b")), "string-set hash drifted")
    assertions += 1
    encoded = "严格".encode("gbk")
    require(strict_gbk_decode(encoded) == "严格", "strict GBK decode drifted")
    assertions += 1
    try:
        strict_gbk_decode(b"\x81")
    except EvidenceError:
        assertions += 1
    else:
        raise EvidenceError("invalid GBK was accepted")
    profile = profile_bytes(b"a\r\nb\nc\rd\x00")
    require(profile["crlf"] == 1 and profile["lone_lf"] == 1 and
            profile["lone_cr"] == 1 and profile["nul"] == 1,
            "CRLF or NUL profile drifted")
    assertions += 1
    accepted = probe_elementtree("<r><c/></r>")
    rejected = probe_elementtree("<r>")
    require(accepted["accepted"] and accepted["tree_shape"]["elements"] == 2 and
            not rejected["accepted"] and rejected["failure_location_sha256"] and
            "error_line" not in rejected and "error_text" not in rejected,
            "ElementTree probe disclosure contract drifted")
    assertions += 1
    require(len(EXPECTED_INPUT_SHA256) == 6 and
            all(set(hashes) == set(SOURCE_FILES)
                for hashes in EXPECTED_SOURCE_HASHES.values()) and
            not ({"path", "name", "value", "tag", "error_text"} & _PROBE_FIELDS),
            "closed source or probe schema drifted")
    assertions += 1
    return {
        "result": "PASS",
        "assertions": assertions,
        "negative_cases": {
            "invalid_gbk_rejected": True,
            "elementtree_error_text_absent": True,
            "raw_failure_location_absent": True,
            "probe_path_name_value_fields_absent": True,
        },
    }
