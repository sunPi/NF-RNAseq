#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror \
  "$root/launcher/NFRNASEQ.c" -o "$root/NFRNASEQ"
printf 'Built %s\n' "$root/NFRNASEQ"
