#!/bin/sh
set -eu
task_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec /usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)(deny process-exec (literal "/usr/bin/security"))' python3 "$task_dir/run.py" "$@"
