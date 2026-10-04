"""Bounded Swift integration probe; the existing private loader owns credentials."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        raise ValueError('plan required')
    plan_path = Path(sys.argv[1]).resolve()
    plan = json.loads(plan_path.read_text())
    if plan['max_requests'] != 2 or plan['status'] != 'development_integration_not_independent_acceptance':
        raise ValueError('invalid plan')
    for name, expected in plan['input_hashes'].items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest() != expected:
            raise ValueError('input changed')
    output = plan_path.parent / 'live'
    if output.exists():
        raise ValueError('output already exists')
    original = Path('/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1')
    sys.path.insert(0, str(original / 'evaluation-v4'))
    from run_private_env import load_credentials
    load_credentials(original / 'evaluation-v2')
    # Values stay in the child environment, never arguments, logs, or artifacts.
    completed = subprocess.run([plan['executable'], 'extract-and-select', plan['document'],
                                plan['query'], str(output)], check=False, capture_output=True,
                               text=True, timeout=210, env=os.environ.copy())
    # Do not forward arbitrary child stdout/stderr; print only a fixed outcome.
    print('Swift provider probe completed.' if completed.returncode == 0 else 'Swift provider probe failed; inspect its bounded receipt.')
    return completed.returncode


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception:
        raise SystemExit('Probe stopped; no configuration or exception contents displayed.')
