"""Local observation adapter. No inference, credentials or transport."""
import json
from pathlib import Path


def call_api(prompt, options, context):
    rows = json.loads(Path(options["config"]["observations"]).read_text())
    case_id = context["vars"]["case_id"]
    matches = [row for row in rows if row["id"] == case_id]
    if len(matches) != 1:
        raise ValueError("Missing or duplicate observation: " + case_id)
    return {"output": json.dumps(matches[0], allow_nan=False)}
