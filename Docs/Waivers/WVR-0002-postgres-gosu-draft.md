# WVR-0002 draft: PostgreSQL gosu standard-library findings

> Status: Draft, not approved, not effective
>
> Decision owner: Project lead (`FaithandUnity`)
>
> Execution owner: Codex
>
> Maximum duration if approved: 30 days
> Effective and expiry timestamps: Unassigned

## Purpose

This document is a decision package, not a waiver grant. It prepares the
component-specific, time-bounded path allowed by the PostgreSQL vulnerability
disposition after the reachability and security review. The current policy
state remains blocking, and no merge or release authority is created.

The proposed scope is only the `gosu` v1.19 binary embedded in the immutable
PostgreSQL 18.6 development image. It does not cover PostgreSQL itself, Alpine,
another image digest, another `gosu` build, a future vulnerability-database
snapshot, the backend builder, licenses, Secrets, or any other component.

## Reviewed risk

- Hosted Trivy reports 22 HIGH/CRITICAL Go standard-library findings in the
  locked `gosu` binary.
- Official `govulncheck v1.7.0` binary-mode evidence maps the same set to zero
  symbol-reachable, one package-only, and 21 module-only results.
- The package-only result is `GO-2026-4970` in `os`; none of its 12 official
  vulnerable symbols is reported called.
- The locked PostgreSQL entrypoint invokes `gosu` once, only for the root-owned
  `postgres` command, to drop privileges and execute the entrypoint again.
- Binary mode has no complete call graph. Zero reported reachable symbols
  lowers assessed reachability but is not proof of absence.

## Mandatory approval conditions

Activation requires all of the following. Editing the JSON request alone is
insufficient.

1. The project lead explicitly sets the exact effective and expiry timestamps;
   the interval must be positive and no longer than 30 days.
2. A non-draft GitHub PR contains the exact request bytes and current evidence
   bindings.
3. At least two unique non-author reviewers approve the PR at its current HEAD;
   one approval must be from `FaithandUnity`.
4. An authenticated GitHub API observation verifies the request hash, PR HEAD,
   review commit IDs, reviewer identities, and absence of stale approvals.
5. The hosted supply-chain gate evaluates the live observation. Offline
   fixtures can test structure but can never activate the exception.

## Boundaries if approved

- The exception applies only to the 22 recorded findings for the exact image
  digest and exact `gosu` SHA-256 in the machine request.
- The image remains immutable and may not be promoted as generally remediated.
- Current hosted scanning, SBOM/license checks, Secret rules, PostgreSQL
  migration tests, and all other required checks remain mandatory.
- The exception cannot authorize a public repository, new collaborator,
  Runner, GHCR publication, signing key, branch protection change, G0, or G1.
- `release_authority` remains false in the waiver evaluator; release authority
  still requires every separate P0-12 governance and provenance condition.

## Immediate invalidation

The decision becomes ineffective on expiry or whenever the image digest,
`gosu` bytes/build, finding set, reachability report, scanner/database identity,
entrypoint, source binding, approval PR HEAD, or required reviews change. A
patched official image that passes qualification replaces this path.

Machine request:
`Data/Security/p0-12-postgres-gosu-waiver-request.json`.

Machine evaluation:
`Data/Security/p0-12-postgres-gosu-waiver-decision.json`.
