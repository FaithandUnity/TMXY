"""Fail-closed decision-state and anonymous review-packet workflow for P2-20B.1."""

from __future__ import annotations

from collections import Counter, defaultdict
from copy import deepcopy
from typing import Any

from g2_common import digest, require


KIND_POLICY_KEYS = {
    "SCHEMA_TABLE": "schema_table",
    "SCHEMA_REFERENCE": "schema_reference",
    "CANONICAL_ID_DOMAIN": "canonical_id_domain",
    "ID_COMPONENT": "id_component",
    "FIXED_LIMIT_SIGNAL": "fixed_limit_signal",
}
KIND_PACKET_CODES = {
    "SCHEMA_TABLE": "SCHEMA-TABLE",
    "SCHEMA_REFERENCE": "SCHEMA-REFERENCE",
    "CANONICAL_ID_DOMAIN": "CANONICAL-ID",
    "ID_COMPONENT": "ID-COMPONENT",
    "FIXED_LIMIT_SIGNAL": "FIXED-LIMIT",
}


def pending_state() -> dict[str, Any]:
    return {
        "decision": {
            "status": "PENDING", "revision": 0, "chosen_action": None,
            "rationale_codes": [], "migration_plan_sha256": None,
            "rollback_plan_sha256": None, "compatibility_impact": "UNKNOWN",
            "effective_schema_version": None,
            "supersedes_decision_digest_sha256": None,
            "decision_digest_sha256": None,
        },
        "approval": {
            "status": "PENDING", "approval_count": 0,
            "external_authority_verified": False, "approval_refs": [],
        },
        "verification": {
            "status": "NOT_RUN", "evidence_sha256": None,
            "decision_digest_sha256": None,
        },
        "superseded_revisions": [],
    }


def revision_material(decision_id: str, member: str, revision: dict[str, Any]) -> dict[str, Any]:
    return {
        "decision_id": decision_id,
        "subject_membership_sha256": member,
        "revision": revision["revision"],
        "chosen_action": revision["chosen_action"],
        "rationale_codes": revision["rationale_codes"],
        "migration_plan_sha256": revision["migration_plan_sha256"],
        "rollback_plan_sha256": revision["rollback_plan_sha256"],
        "compatibility_impact": revision["compatibility_impact"],
        "effective_schema_version": revision["effective_schema_version"],
        "supersedes_decision_digest_sha256": revision["supersedes_decision_digest_sha256"],
    }


def validate_approval(approval: dict[str, Any], decision_sha: str,
                      required_roles: list[str], allow_rejected: bool) -> bool:
    status, refs = approval["status"], approval["approval_refs"]
    require(approval["approval_count"] == len(refs), "Approval count differs from references")
    if status == "PENDING":
        require(not refs and approval["external_authority_verified"] is False,
                "Pending approval contains authority")
        return False
    require(status in ({"APPROVED", "REJECTED"} if allow_rejected else {"APPROVED"}),
            "Active decision cannot carry a rejected approval")
    require(approval["external_authority_verified"] is True and refs,
            "Non-pending approval lacks verified external authority")
    roles = [item["role"] for item in refs]
    require(len(roles) == len(set(roles)), "Approval role is duplicated")
    require(all(item["verified"] is True and
                item["decision_digest_sha256"] == decision_sha and
                item["authority_record_sha256"] != item["authority_verification_sha256"]
                for item in refs), "Approval does not bind verified decision authority")
    if status == "APPROVED":
        require(sorted(roles) == sorted(required_roles), "Required approval roles are incomplete")
        return True
    require(set(roles).issubset(set(required_roles)), "Rejected approval has an invalid role")
    return False


def validate_verification(verification: dict[str, Any], decision_sha: str,
                          approved: bool) -> bool:
    status = verification["status"]
    if status == "NOT_RUN":
        require(verification["evidence_sha256"] is None and
                verification["decision_digest_sha256"] is None,
                "NOT_RUN verification contains evidence")
        return False
    require(status in {"PASS", "FAIL"} and approved,
            "Verification requires an approved decision")
    require(verification["evidence_sha256"] and
            verification["decision_digest_sha256"] == decision_sha,
            "Verification evidence does not bind the decision")
    return status == "PASS"


def validate_revision(decision_id: str, member: str, subject_kind: str,
                      revision: dict[str, Any], required_roles: list[str],
                      policy: dict[str, Any], allow_rejected: bool) -> tuple[str, bool, bool]:
    key = KIND_POLICY_KEYS[subject_kind]
    require(revision["chosen_action"] in policy["allowed_actions"][key],
            "Chosen action is not allowed for the subject kind")
    rationales = revision["rationale_codes"]
    require(rationales == sorted(set(rationales)) and rationales and
            set(rationales).issubset(set(policy["allowed_decision_rationale_codes"])),
            "Decision rationale codes are not closed or canonical")
    require(revision["compatibility_impact"] in
            {"NONE", "BACKWARD_COMPATIBLE", "BREAKING"},
            "Decided compatibility impact is unknown")
    require(revision["migration_plan_sha256"] and revision["rollback_plan_sha256"] and
            int(revision["effective_schema_version"]) >= 1,
            "Decided revision lacks migration rollback or schema-version evidence")
    expected = digest(revision_material(decision_id, member, revision))
    require(revision["decision_digest_sha256"] == expected, "Decision digest is invalid")
    approved = validate_approval(revision["approval"], expected, required_roles, allow_rejected)
    verified = validate_verification(revision["verification"], expected, approved)
    return expected, approved, verified


def apply_authority(decisions: list[dict[str, Any]], ledger: dict[str, Any],
                    policy: dict[str, Any]) -> list[dict[str, Any]]:
    require(ledger["schema_version"] == 2 and ledger["workflow_version"] == 2 and
            ledger["task_id"] == "P2-20B" and
            ledger["authority_mode"] == "EXTERNAL_VERIFIED_RECORDS_ONLY" and
            ledger["machine_can_assert_authority"] is False,
            "Authority ledger boundary is invalid")
    by_id = {item["decision_id"]: item for item in decisions}
    records = ledger["records"]
    require(len(records) == len({item["decision_id"] for item in records}),
            "Authority ledger contains duplicate subjects")
    for record in records:
        identifier = record["decision_id"]
        require(identifier in by_id, "Authority ledger contains an orphan subject")
        subject = by_id[identifier]
        require(record["subject_kind"] == subject["subject_kind"] and
                record["subject_membership_sha256"] == subject["subject_membership_sha256"],
                "Authority ledger subject binding drifted")
        required_roles = subject["ownership"]["required_approver_roles"]
        history, active = record["superseded_revisions"], record["active_revision"]
        revisions = [item["revision"] for item in history] + [active["revision"]]
        require(revisions == list(range(1, len(revisions) + 1)),
                "Decision revisions are not contiguous")
        prior = None
        for index, old in enumerate(history):
            require(old["status"] == "SUPERSEDED" and
                    old["supersedes_decision_digest_sha256"] == prior,
                    "Superseded revision chain is invalid")
            old_sha, old_approved, _ = validate_revision(
                identifier, subject["subject_membership_sha256"], subject["subject_kind"],
                old, required_roles, policy, True)
            next_revision = history[index + 1] if index + 1 < len(history) else active
            require(old["superseded_by_decision_digest_sha256"] ==
                    next_revision["decision_digest_sha256"],
                    "Superseded revision does not bind its replacement")
            if old["approval"]["status"] == "REJECTED":
                require(next_revision["approval"]["status"] == "APPROVED",
                        "Rejected candidate lacks an approved replacement")
            prior = old_sha
            require(old_approved or old["approval"]["status"] == "REJECTED",
                    "Superseded revision lacks external authority")
        require(active["status"] == "DECIDED" and
                active["supersedes_decision_digest_sha256"] == prior,
                "Active revision chain is invalid")
        active_sha, _, _ = validate_revision(
            identifier, subject["subject_membership_sha256"], subject["subject_kind"],
            active, required_roles, policy, False)
        merged = deepcopy(active)
        approval, verification = merged.pop("approval"), merged.pop("verification")
        require(merged["decision_digest_sha256"] == active_sha, "Active digest drifted")
        subject["decision"], subject["approval"], subject["verification"] = merged, approval, verification
        subject["superseded_revisions"] = deepcopy(history)
    return decisions


def risk_signature(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "subject_kind": item["subject_kind"], "risk_class": item["risk_class"],
        "suggested_action_code": item["machine_suggestion"]["action_code"],
        "risk_codes": item["risk_codes"],
        "suggestion_rationale_codes": item["machine_suggestion"]["rationale_codes"],
        "required_approver_roles": item["ownership"]["required_approver_roles"],
    }


def build_review_packets(decisions: list[dict[str, Any]], policy: dict[str, Any]) -> dict[str, Any]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    signatures: dict[str, dict[str, Any]] = {}
    for item in decisions:
        signature = risk_signature(item)
        key = digest(signature)
        signatures[key] = signature
        groups[key].append(item)
    packets, kind_ordinals = [], Counter()
    for key in sorted(groups, key=lambda value: (signatures[value]["subject_kind"], value)):
        signature, items = signatures[key], groups[key]
        kind = signature["subject_kind"]
        kind_ordinals[kind] += 1
        members = [{"decision_id": item["decision_id"],
                    "subject_membership_sha256": item["subject_membership_sha256"]}
                   for item in sorted(items, key=lambda value: value["decision_id"])]
        packets.append({
            "review_packet_id": f"G2R-{KIND_PACKET_CODES[kind]}-{kind_ordinals[kind]:02d}",
            "subject_kind": kind, "risk_signature_sha256": key,
            "suggested_action_code": signature["suggested_action_code"],
            "risk_codes": signature["risk_codes"],
            "suggestion_rationale_codes": signature["suggestion_rationale_codes"],
            "required_approver_roles": signature["required_approver_roles"],
            "member_count": len(members), "membership_sha256": digest(members),
            "members": members, "counts_as_decision": False,
        })
    all_members = [member for packet in packets for member in packet["members"]]
    unique = {(item["decision_id"], item["subject_membership_sha256"]) for item in all_members}
    expected = policy["expected_review_packets"]
    require(len(packets) == expected["total"] and len(all_members) == policy["expected_units"]["total"] and
            len(unique) == len(all_members), "Review packet population is incomplete")
    for kind, key in KIND_POLICY_KEYS.items():
        require(kind_ordinals[kind] == expected[key], "Review packet kind count drifted")
    member_counts = Counter(item["subject_kind"] for item in decisions)
    packet_counts = Counter(item["subject_kind"] for item in packets)
    return {
        "schema_version": 2, "workflow_version": 2, "task_id": "P2-20B",
        "source_build": policy["source_build"], "generation_result": "PASS",
        "counts_as_decision": False,
        "summary": {
            "packet_count": len(packets), "member_count": len(all_members),
            "unique_member_count": len(unique),
            "by_subject_kind_packets": {KIND_POLICY_KEYS[k]: packet_counts[k] for k in KIND_POLICY_KEYS},
            "by_subject_kind_members": {KIND_POLICY_KEYS[k]: member_counts[k] for k in KIND_POLICY_KEYS},
            "aggregate_membership_sha256": digest(all_members),
        },
        "packets": packets,
        "disclosure": {
            "anonymous_subjects_only": True, "private_source_paths": False,
            "primary_keys": False, "observed_extrema": False,
            "raw_rows": False, "legacy_source_lines": False,
        },
    }


def workflow_self_test() -> dict[str, Any]:
    pending = pending_state()
    require(pending["decision"]["status"] == "PENDING" and
            pending["approval"]["status"] == "PENDING" and
            pending["verification"]["status"] == "NOT_RUN", "Pending state drifted")
    require(digest({"a": 1}) != digest({"a": 2}), "Decision digest drift not detected")
    policy = {
        "allowed_actions": {"schema_table": ["MIGRATE_WITH_TRANSFORM"]},
        "allowed_decision_rationale_codes": ["DATA_OWNER_JUDGMENT"],
    }
    identifier, member, roles = "MIG-SCHEMA-TABLE-0001", "0" * 64, ["data-owner"]
    revision = {
        "revision": 1, "status": "DECIDED", "chosen_action": "MIGRATE_WITH_TRANSFORM",
        "rationale_codes": ["DATA_OWNER_JUDGMENT"], "migration_plan_sha256": "1" * 64,
        "rollback_plan_sha256": "2" * 64, "compatibility_impact": "BREAKING",
        "effective_schema_version": 1, "supersedes_decision_digest_sha256": None,
        "decision_digest_sha256": None,
        "approval": {"status": "PENDING", "approval_count": 0,
                     "external_authority_verified": False, "approval_refs": []},
        "verification": {"status": "NOT_RUN", "evidence_sha256": None,
                         "decision_digest_sha256": None},
    }
    revision["decision_digest_sha256"] = digest(revision_material(identifier, member, revision))
    validate_revision(identifier, member, "SCHEMA_TABLE", revision, roles, policy, False)

    def rejected(change: str) -> bool:
        candidate = deepcopy(revision)
        if change == "action":
            candidate["chosen_action"] = "UNBOUNDED_ACTION"
        elif change == "plan":
            candidate["migration_plan_sha256"] = None
        elif change == "compatibility":
            candidate["compatibility_impact"] = "UNKNOWN"
        elif change == "digest":
            candidate["decision_digest_sha256"] = "f" * 64
        elif change in {"role", "approval_digest", "verification_digest"}:
            decision_sha = candidate["decision_digest_sha256"]
            candidate["approval"] = {"status": "APPROVED", "approval_count": 1,
                "external_authority_verified": True, "approval_refs": [{
                    "role": "project-owner" if change == "role" else "data-owner",
                    "authority_kind": "SIGNED_DECISION_RECORD",
                    "authority_record_sha256": "3" * 64,
                    "authority_verification_sha256": "4" * 64,
                    "decision_digest_sha256": "5" * 64 if change == "approval_digest" else decision_sha,
                    "verified": True}]}
            if change == "verification_digest":
                candidate["verification"] = {"status": "PASS", "evidence_sha256": "6" * 64,
                    "decision_digest_sha256": "7" * 64}
        try:
            validate_revision(identifier, member, "SCHEMA_TABLE", candidate, roles, policy, False)
            return False
        except (KeyError, TypeError, ValueError):
            return True

    negatives = {f"{name}_rejected": rejected(name) for name in
                 ("action", "plan", "compatibility", "digest", "role",
                  "approval_digest", "verification_digest")}
    old = deepcopy(revision)
    old["status"] = "SUPERSEDED"
    old_sha = old["decision_digest_sha256"]
    old["approval"] = {"status": "APPROVED", "approval_count": 1,
        "external_authority_verified": True, "approval_refs": [{
            "role": "data-owner", "authority_kind": "SIGNED_DECISION_RECORD",
            "authority_record_sha256": "3" * 64, "authority_verification_sha256": "4" * 64,
            "decision_digest_sha256": old_sha, "verified": True}]}
    active = deepcopy(revision)
    active["revision"] = 2
    active["supersedes_decision_digest_sha256"] = old_sha
    active["decision_digest_sha256"] = digest(revision_material(identifier, member, active))
    base_record = {"decision_id": identifier, "subject_kind": "SCHEMA_TABLE",
                   "subject_membership_sha256": member, "active_revision": active,
                   "superseded_revisions": [old]}
    ledger = {"schema_version": 2, "workflow_version": 2, "task_id": "P2-20B",
              "authority_mode": "EXTERNAL_VERIFIED_RECORDS_ONLY",
              "machine_can_assert_authority": False, "records": [base_record]}
    subject = {"decision_id": identifier, "subject_kind": "SCHEMA_TABLE",
               "subject_membership_sha256": member,
               "ownership": {"required_approver_roles": roles}}
    old["superseded_by_decision_digest_sha256"] = "8" * 64
    try:
        apply_authority([deepcopy(subject)], ledger, policy)
        negatives["supersession_binding_rejected"] = False
    except ValueError:
        negatives["supersession_binding_rejected"] = True
    old["superseded_by_decision_digest_sha256"] = active["decision_digest_sha256"]
    old["approval"]["status"] = "REJECTED"
    try:
        apply_authority([deepcopy(subject)], ledger, policy)
        negatives["rejected_without_approved_replacement_rejected"] = False
    except ValueError:
        negatives["rejected_without_approved_replacement_rejected"] = True
    require(all(negatives.values()), "V2 state negative case was accepted")
    return {"assertions": 12, "negative_cases": negatives}
