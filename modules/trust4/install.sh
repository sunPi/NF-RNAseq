#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.1.9"
REPOSITORY="https://github.com/liulab-dfci/TRUST4.git"
log() { printf '[trust4-install] %s\n' "$*"; }
die() { printf '[trust4-install] ERROR: %s\n' "$*" >&2; exit 1; }

ASSEMBLY=""; DB_ROOT=""; MODULE_DB_ROOT=""; CONDA_ENV=""; THREADS=8
while (( $# )); do
    case "$1" in
        --assembly) ASSEMBLY="$2"; shift 2 ;;
        --db-root) DB_ROOT="$2"; shift 2 ;;
        --module-db-root) MODULE_DB_ROOT="$2"; shift 2 ;;
        --conda-env) CONDA_ENV="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        -h|--help) printf 'Install with: ./install_pipe.sh --add-modules trust4 --assembly GRCh38\n'; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
case "${ASSEMBLY,,}" in grch38|hg38) ASSEMBLY=GRCh38; REF_NAME=hg38_bcrtcr.fa;; grch37|hg19) ASSEMBLY=GRCh37; REF_NAME=hg19_bcrtcr.fa;; *) die "Unsupported assembly";; esac
[[ -d "$DB_ROOT" && -n "$MODULE_DB_ROOT" && -n "$CONDA_ENV" ]] || die "Missing installer arguments"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "Invalid thread count"
for command in git make g++ perl; do command -v "$command" >/dev/null 2>&1 || die "Missing command: $command"; done

SOURCE="$MODULE_DB_ROOT/tools/TRUST4-v${VERSION}"
mkdir -p "$MODULE_DB_ROOT/tools" "$MODULE_DB_ROOT/config"
if [[ ! -d "$SOURCE/.git" ]]; then
    [[ ! -e "$SOURCE" ]] || die "Incomplete source directory exists: $SOURCE"
    git clone --branch "v${VERSION}" --depth 1 "$REPOSITORY" "$SOURCE"
fi
git -C "$SOURCE" rev-parse "v${VERSION}^{commit}" >/dev/null
make -C "$SOURCE" -j "$THREADS"

EXECUTABLE="$SOURCE/run-trust4"
VDJC_REFERENCE="$SOURCE/$REF_NAME"
IMGT_REFERENCE="$SOURCE/human_IMGT+C.fa"
[[ -x "$EXECUTABLE" ]] || die "run-trust4 was not built"
[[ -s "$VDJC_REFERENCE" && -s "$IMGT_REFERENCE" ]] || die "Bundled human references are missing"

CONFIG="$MODULE_DB_ROOT/config/${ASSEMBLY}.config"
{
    printf 'TRUST4_ASSEMBLY=%q\n' "$ASSEMBLY"
    printf 'TRUST4_VERSION=%q\n' "$VERSION"
    printf 'TRUST4_EXECUTABLE=%q\n' "$EXECUTABLE"
    printf 'TRUST4_VDJC_REFERENCE=%q\n' "$VDJC_REFERENCE"
    printf 'TRUST4_IMGT_REFERENCE=%q\n' "$IMGT_REFERENCE"
} > "$CONFIG"
log "Installed TRUST4 $VERSION for $ASSEMBLY"
