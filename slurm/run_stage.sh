#!/usr/bin/env bash

set -Eeuo pipefail

[[ $# -ge 2 ]] || {
    printf '[ERROR] Usage: %s PROFILE MAIN_ARGUMENT...\n' "$0" >&2
    exit 2
}

profile="$1"
shift

[[ -f "$profile" ]] || {
    printf '[ERROR] SLURM profile not found: %s\n' "$profile" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$profile"

if [[ -n "${SLURM_JOB_SETUP:-}" ]]; then
    eval "$SLURM_JOB_SETUP"
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
arguments=("$@")
for index in "${!arguments[@]}"; do
    if [[ "${arguments[$index]}" == "__SLURM_ARRAY_TASK_ID__" ]]; then
        [[ -n "${SLURM_ARRAY_TASK_ID:-}" ]] || {
            printf '[ERROR] SLURM_ARRAY_TASK_ID is not set\n' >&2
            exit 1
        }
        arguments[$index]="$SLURM_ARRAY_TASK_ID"
    fi
done
exec "${script_dir}/main.sh" "${arguments[@]}"
