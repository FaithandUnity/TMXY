#!/usr/bin/env python3
"""CLI for deterministic P2-19 resource-budget generation."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from budget_common import canonical_json
from budget_program import build_report
from budget_render import describe, render_markdown, self_test


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--root")
    parser.add_argument("--policy")
    parser.add_argument("--pilot")
    parser.add_argument("--json-output")
    parser.add_argument("--markdown-output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        result = self_test()
        print(json.dumps(result, sort_keys=True))
        return 0 if result["result"] == "PASS" else 1
    if not all((args.root, args.policy, args.pilot, args.json_output, args.markdown_output)):
        raise ValueError("root, policy, pilot, and both outputs are required")
    report = build_report(Path(args.root), Path(args.policy), Path(args.pilot))
    json_path, markdown_path = Path(args.json_output), Path(args.markdown_output)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(canonical_json(report), encoding="utf-8", newline="\n")
    markdown_path.write_text(render_markdown(report), encoding="utf-8", newline="\n")
    print(json.dumps({"json": describe(json_path), "markdown": describe(markdown_path), "result": report["result"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"resource_budget: {error}", file=sys.stderr)
        raise SystemExit(2)
