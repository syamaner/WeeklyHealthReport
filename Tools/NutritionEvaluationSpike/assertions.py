"""Check a pinned case expectation, not a weighted nutrition-quality score."""
import json


def get_assert(output, context):
    row = json.loads(output)
    if row["id"] != context["vars"]["case_id"]:
        raise ValueError("Observation identity mismatch")
    passed = row["expectation_met"] is True
    return {"pass": passed, "score": int(passed),
            "reason": row["reason"]}
