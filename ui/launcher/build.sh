#!/usr/bin/env bash
set -Eeuo pipefail

ui_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror \
  "$ui_dir/launcher/NFRNASEQ.c" -o "$ui_dir/NFRNASEQ"
printf 'Built %s\n' "$ui_dir/NFRNASEQ"
