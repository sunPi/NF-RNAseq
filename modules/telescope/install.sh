#!/usr/bin/env bash
set -Eeuo pipefail

TELESCOPE_COMMIT="4cf18595eea1702775e8a8bbc7b37ebac9233fd5"
ANNOTATION_COMMIT="a8a282b1f1161a6a2ee5604b8037e45e31048bd6"
TELESCOPE_ENV="nf-telescope-env"
MEDIA_ROOT="https://media.githubusercontent.com/media/mlbendall/telescope_annotation_db/${ANNOTATION_COMMIT}/builds"
log() { printf '[telescope-install] %s\n' "$*"; }
die() { printf '[telescope-install] ERROR: %s\n' "$*" >&2; exit 1; }

ASSEMBLY=""; DB_ROOT=""; MODULE_DB_ROOT=""; CONDA_ENV=""; THREADS=8
while (( $# )); do
    case "$1" in
        --assembly) ASSEMBLY="$2"; shift 2 ;;
        --db-root) DB_ROOT="$2"; shift 2 ;;
        --module-db-root) MODULE_DB_ROOT="$2"; shift 2 ;;
        --conda-env) CONDA_ENV="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        -h|--help) printf 'Install with: ./install_pipe.sh --add-modules telescope --assembly GRCh38\n'; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
case "${ASSEMBLY,,}" in grch38|hg38) ASSEMBLY=GRCh38;; grch37|hg19) ASSEMBLY=GRCh37;; *) die "Unsupported assembly";; esac
[[ -d "$DB_ROOT" && -n "$MODULE_DB_ROOT" && -n "$CONDA_ENV" ]] || die "Missing installer arguments"
for command in conda curl awk git sed; do command -v "$command" >/dev/null 2>&1 || die "Missing command: $command"; done
mkdir -p "$MODULE_DB_ROOT/annotations/$ASSEMBLY" "$MODULE_DB_ROOT/config" "$MODULE_DB_ROOT/tools"

if conda env list | awk '{print $1}' | grep -Fxq "$TELESCOPE_ENV"; then
    conda install --name "$TELESCOPE_ENV" --channel conda-forge --yes \
        'python=3.11' pip 'numpy<2' scipy pandas pyyaml 'cython<3' intervaltree future
else
    conda create --name "$TELESCOPE_ENV" --channel conda-forge --yes \
        'python=3.11' pip 'numpy<2' scipy pandas pyyaml 'cython<3' intervaltree future
fi
conda run --name "$TELESCOPE_ENV" python -m pip install --upgrade 'pysam>=0.19'
TELESCOPE_SOURCE="$MODULE_DB_ROOT/tools/telescope-${TELESCOPE_COMMIT}"
if [[ ! -d "$TELESCOPE_SOURCE/.git" ]]; then
    [[ ! -e "$TELESCOPE_SOURCE" ]] || die "Incomplete Telescope source exists: $TELESCOPE_SOURCE"
    git clone https://github.com/mlbendall/telescope.git "$TELESCOPE_SOURCE"
    git -C "$TELESCOPE_SOURCE" checkout --detach "$TELESCOPE_COMMIT"
fi
[[ "$(git -C "$TELESCOPE_SOURCE" rev-parse HEAD)" == "$TELESCOPE_COMMIT" ]] ||
    die "Telescope source revision does not match the pinned commit"
# Upstream's Cython source uses a Python-2-style relative cimport. Make the
# package-qualified import explicit so the pinned source builds on Python 3.
sed -i 's/^from calignment cimport /from telescope.utils.calignment cimport /' \
    "$TELESCOPE_SOURCE/telescope/utils/calignment.pyx"
sed -i "s/'rU'/'r'/g" \
    "$TELESCOPE_SOURCE/telescope/utils/_annotation_bisect.py" \
    "$TELESCOPE_SOURCE/telescope/utils/_annotation_intervaltree.py" \
    "$TELESCOPE_SOURCE/telescope/utils/model.py"
conda run --name "$TELESCOPE_ENV" python -m pip install \
    --no-build-isolation --no-deps --upgrade "$TELESCOPE_SOURCE"
EXECUTABLE="$(conda run --name "$TELESCOPE_ENV" sh -c 'command -v telescope')"
[[ -x "$EXECUTABLE" ]] || die "Telescope executable was not installed"
conda run --name "$TELESCOPE_ENV" telescope --version >/dev/null

ANNOTATION_DIR="$MODULE_DB_ROOT/annotations/$ASSEMBLY"
ANNOTATION="$ANNOTATION_DIR/retro_transcripts.gtf"
download() {
    local url="$1" destination="$2"
    [[ -s "$destination" ]] && return
    curl --fail --location --retry 5 --output "${destination}.part" "$url"
    mv -- "${destination}.part" "$destination"
}
if [[ "$ASSEMBLY" == GRCh38 ]]; then
    download "$MEDIA_ROOT/retro.hg38.v1/transcripts.gtf" "$ANNOTATION"
    ANNOTATION_RELEASE="retro.hg38.v1"
else
    HERV="$ANNOTATION_DIR/HERV_rmsk.hg19.v2.gtf"
    L1="$ANNOTATION_DIR/L1Base.hg19.v1.gtf"
    download "$MEDIA_ROOT/HERV_rmsk.hg19.v2/transcripts.gtf" "$HERV"
    download "$MEDIA_ROOT/L1Base.hg19.v1/transcripts.gtf" "$L1"
    awk '!/^#/' "$HERV" "$L1" > "${ANNOTATION}.tmp"
    mv -- "${ANNOTATION}.tmp" "$ANNOTATION"
    ANNOTATION_RELEASE="HERV_rmsk.hg19.v2+L1Base.hg19.v1"
fi
awk -F '\t' 'NF >= 9 {ok=1; exit} END {exit(ok ? 0 : 1)}' "$ANNOTATION" ||
    die "Downloaded Telescope annotation is invalid"

CONFIG="$MODULE_DB_ROOT/config/${ASSEMBLY}.config"
{
    printf 'TELESCOPE_ASSEMBLY=%q\n' "$ASSEMBLY"
    printf 'TELESCOPE_COMMIT=%q\n' "$TELESCOPE_COMMIT"
    printf 'TELESCOPE_CONDA_ENV=%q\n' "$TELESCOPE_ENV"
    printf 'TELESCOPE_EXECUTABLE=%q\n' "$EXECUTABLE"
    printf 'TELESCOPE_ANNOTATION=%q\n' "$ANNOTATION"
    printf 'TELESCOPE_ANNOTATION_RELEASE=%q\n' "$ANNOTATION_RELEASE"
    printf 'TELESCOPE_ANNOTATION_COMMIT=%q\n' "$ANNOTATION_COMMIT"
} > "$CONFIG"
log "Installed Telescope for $ASSEMBLY"
