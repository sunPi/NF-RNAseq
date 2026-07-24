#!/usr/bin/env bash

set -Eeuo pipefail

ARRIBA_VERSION="2.5.0"
STAR_FUSION_VERSION="1.15.1"
CTAT_BASE_URL="https://data.broadinstitute.org/Trinity/CTAT_RESOURCE_LIB"

log_info() {
    printf '[fusion-install] %s\n' "$*"
}

die() {
    printf '[fusion-install] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  install.sh --assembly GRCh37|GRCh38 --db-root DIR \
    --module-db-root DIR --conda-env NAME [--threads N]

This script is normally called by:
  ./install_pipe.sh --add-modules fusion --assembly GRCh38

Environment overrides:
  FUSION_CTAT_URL       Alternative CTAT plug-and-play archive URL
  FUSION_ARRIBA_URL     Alternative Arriba release archive URL
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command was not found: $1"
}

download_file() {
    local url="$1"
    local destination="$2"
    local partial_file="${destination}.part"

    if [[ -s "$destination" ]]; then
        log_info "Using existing download: $destination"
        return
    fi

    log_info "Downloading $url"
    curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 5 \
        --continue-at - \
        --output "$partial_file" \
        "$url"
    mv -- "$partial_file" "$destination"
}

ASSEMBLY=""
DB_ROOT=""
MODULE_DB_ROOT=""
CONDA_ENV=""
THREADS=8

while (( $# > 0 )); do
    case "$1" in
        --assembly)
            [[ $# -ge 2 ]] || die "--assembly requires a value"
            ASSEMBLY="$2"
            shift 2
            ;;
        --db-root)
            [[ $# -ge 2 ]] || die "--db-root requires a value"
            DB_ROOT="$2"
            shift 2
            ;;
        --module-db-root)
            [[ $# -ge 2 ]] || die "--module-db-root requires a value"
            MODULE_DB_ROOT="$2"
            shift 2
            ;;
        --conda-env)
            [[ $# -ge 2 ]] || die "--conda-env requires a value"
            CONDA_ENV="$2"
            shift 2
            ;;
        --threads)
            [[ $# -ge 2 ]] || die "--threads requires a value"
            THREADS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

case "${ASSEMBLY,,}" in
    grch38|hg38)
        ASSEMBLY="GRCh38"
        CTAT_ARCHIVE_NAME="GRCh38_gencode_v44_CTAT_lib_Oct292023.plug-n-play.tar.gz"
        ;;
    grch37|hg19)
        ASSEMBLY="GRCh37"
        CTAT_ARCHIVE_NAME="GRCh37_gencode_v19_CTAT_lib_Mar012021.STAR_v2.7.11a.plug-n-play.tar.gz"
        ;;
    *)
        die "--assembly must be GRCh37, hg19, GRCh38, or hg38"
        ;;
esac

[[ -n "$DB_ROOT" ]] || die "--db-root is required"
[[ -n "$MODULE_DB_ROOT" ]] || die "--module-db-root is required"
[[ -n "$CONDA_ENV" ]] || die "--conda-env is required"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] ||
    die "--threads must be a positive integer"

require_command conda
require_command curl
require_command tar

mkdir -p "$MODULE_DB_ROOT"
MODULE_DB_ROOT="$(cd -- "$MODULE_DB_ROOT" && pwd -P)"

DOWNLOAD_DIR="${MODULE_DB_ROOT}/downloads"
CTAT_ASSEMBLY_ROOT="${MODULE_DB_ROOT}/ctat/${ASSEMBLY}"
ARRIBA_ROOT="${MODULE_DB_ROOT}/arriba/v${ARRIBA_VERSION}"
CONFIG_DIR="${MODULE_DB_ROOT}/config"

mkdir -p \
    "$DOWNLOAD_DIR" \
    "$CTAT_ASSEMBLY_ROOT" \
    "$ARRIBA_ROOT" \
    "$CONFIG_DIR" \
    "${MODULE_DB_ROOT}/tools"

log_info "Installing Arriba in Conda environment '$CONDA_ENV'"
conda install \
    --name "$CONDA_ENV" \
    --channel conda-forge \
    --channel bioconda \
    --yes \
    arriba

conda run --name "$CONDA_ENV" arriba -h >/dev/null 2>&1

case "$(uname -m)" in
    x86_64|amd64)
        log_info "Installing STAR-Fusion in Conda environment '$CONDA_ENV'"
        conda install \
            --name "$CONDA_ENV" \
            --channel conda-forge \
            --channel bioconda \
            --yes \
            "star-fusion=${STAR_FUSION_VERSION}"
        STAR_FUSION_EXECUTABLE="$(
            conda run --name "$CONDA_ENV" \
                sh -c 'command -v STAR-Fusion'
        )"
        FUSION_INSPECTOR_EXECUTABLE="$(
            conda run --name "$CONDA_ENV" \
                sh -c 'command -v FusionInspector'
        )"
        ;;
    aarch64|arm64)
        require_command make

        STAR_FUSION_SOURCE="${MODULE_DB_ROOT}/tools/STAR-Fusion-v${STAR_FUSION_VERSION}"
        STAR_FUSION_PROGRAM="${STAR_FUSION_SOURCE}/STAR-Fusion"
        STAR_FUSION_EXECUTABLE="${MODULE_DB_ROOT}/tools/STAR-Fusion"
        FUSION_INSPECTOR_EXECUTABLE="${STAR_FUSION_SOURCE}/FusionInspector/FusionInspector"
        STAR_FUSION_BUILD_MARKER="${STAR_FUSION_SOURCE}/.fusion-module-build-complete"
        STAR_FUSION_PLUGIN_PM="${STAR_FUSION_SOURCE}/PerlLib/Set/IntervalTree.pm"
        STAR_FUSION_PLUGIN_SO="${STAR_FUSION_SOURCE}/PerlLib/auto/Set/IntervalTree/IntervalTree.so"
        SYSTEM_PERL="${FUSION_SYSTEM_PERL:-/usr/bin/perl}"
        STAR_FUSION_ARCHIVE_NAME="STAR-Fusion-v${STAR_FUSION_VERSION}.FULL.tar.gz"
        STAR_FUSION_ARCHIVE="${DOWNLOAD_DIR}/${STAR_FUSION_ARCHIVE_NAME}"
        STAR_FUSION_URL="https://github.com/STAR-Fusion/STAR-Fusion/releases/download/STAR-Fusion-v${STAR_FUSION_VERSION}/${STAR_FUSION_ARCHIVE_NAME}"

        if [[ ! -d "$STAR_FUSION_SOURCE" ]]; then
            download_file "$STAR_FUSION_URL" "$STAR_FUSION_ARCHIVE"
            log_info "Extracting the full STAR-Fusion release for $(uname -m)"
            tar -xzf "$STAR_FUSION_ARCHIVE" -C "${MODULE_DB_ROOT}/tools"
            [[ -d "$STAR_FUSION_SOURCE" ]] ||
                die "STAR-Fusion archive did not create: $STAR_FUSION_SOURCE"
        fi

        [[ -x "$SYSTEM_PERL" ]] ||
            die "System Perl was not found for the ARM build: $SYSTEM_PERL"

        if [[ -s "$STAR_FUSION_PLUGIN_PM" &&
              -s "$STAR_FUSION_PLUGIN_SO" ]] &&
           "$SYSTEM_PERL" -I "$STAR_FUSION_SOURCE/PerlLib" \
               -MSet::IntervalTree -e 'exit 0' 2>/dev/null; then
            printf 'STAR-Fusion %s plugins_only\n' "$STAR_FUSION_VERSION" \
                > "$STAR_FUSION_BUILD_MARKER"
            log_info "STAR-Fusion's required Perl plugin is already built"
        else
            make -C "${STAR_FUSION_SOURCE}/plugins" clean
            log_info "Building STAR-Fusion's required Perl plugin"
            env PATH="/usr/bin:/bin" \
                make -C "$STAR_FUSION_SOURCE" plugins_only
            "$SYSTEM_PERL" -I "$STAR_FUSION_SOURCE/PerlLib" \
                -MSet::IntervalTree -e 'exit 0'
            printf 'STAR-Fusion %s plugins_only\n' "$STAR_FUSION_VERSION" \
                > "$STAR_FUSION_BUILD_MARKER"
        fi

        {
            printf '#!/usr/bin/env bash\n'
            printf 'exec %q %q "$@"\n' "$SYSTEM_PERL" "$STAR_FUSION_PROGRAM"
        } > "$STAR_FUSION_EXECUTABLE"
        chmod +x "$STAR_FUSION_EXECUTABLE"
        ;;
    *)
        die "Unsupported CPU architecture for STAR-Fusion: $(uname -m)"
        ;;
esac

[[ -x "$STAR_FUSION_EXECUTABLE" ]] ||
    die "STAR-Fusion executable was not installed: $STAR_FUSION_EXECUTABLE"
[[ -x "$FUSION_INSPECTOR_EXECUTABLE" ]] ||
    die "FusionInspector executable was not installed: $FUSION_INSPECTOR_EXECUTABLE"
"$STAR_FUSION_EXECUTABLE" --version >/dev/null
"$FUSION_INSPECTOR_EXECUTABLE" --version >/dev/null

CTAT_URL="${FUSION_CTAT_URL:-${CTAT_BASE_URL}/${CTAT_ARCHIVE_NAME}}"
CTAT_ARCHIVE="${DOWNLOAD_DIR}/${CTAT_ARCHIVE_NAME}"
CTAT_GENOME_LIB="${CTAT_ASSEMBLY_ROOT}/ctat_genome_lib_build_dir"

if [[ ! -s "${CTAT_GENOME_LIB}/fusion_annot_lib.idx" ||
      ! -d "${CTAT_GENOME_LIB}/ref_genome.fa.star.idx" ]]; then
    download_file "$CTAT_URL" "$CTAT_ARCHIVE"

    temporary_ctat_dir="$(mktemp -d "${CTAT_ASSEMBLY_ROOT}/.extract.XXXXXX")"
    log_info "Extracting CTAT library for $ASSEMBLY (this can take a while)"
    tar -xzf "$CTAT_ARCHIVE" -C "$temporary_ctat_dir"

    extracted_ctat_lib="$(
        find "$temporary_ctat_dir" \
            -type d \
            -name ctat_genome_lib_build_dir \
            -print \
            -quit
    )"
    [[ -n "$extracted_ctat_lib" ]] ||
        die "The CTAT archive did not contain ctat_genome_lib_build_dir"

    if [[ -e "$CTAT_GENOME_LIB" ]]; then
        die "Incomplete CTAT target already exists: $CTAT_GENOME_LIB"
    fi
    mv -- "$extracted_ctat_lib" "$CTAT_GENOME_LIB"
    rm -rf -- "$temporary_ctat_dir"
else
    log_info "CTAT library is already installed for $ASSEMBLY"
fi

CTAT_REQUIRED_FILES=(
    "${CTAT_GENOME_LIB}/ref_genome.fa"
    "${CTAT_GENOME_LIB}/ref_annot.gtf"
    "${CTAT_GENOME_LIB}/fusion_annot_lib.idx"
)
for required_file in "${CTAT_REQUIRED_FILES[@]}"; do
    [[ -s "$required_file" ]] ||
        die "Required CTAT file is missing or empty: $required_file"
done
[[ -d "${CTAT_GENOME_LIB}/ref_genome.fa.star.idx" ]] ||
    die "CTAT STAR index is missing: ${CTAT_GENOME_LIB}/ref_genome.fa.star.idx"

ARRIBA_ARCHIVE_NAME="arriba_v${ARRIBA_VERSION}.tar.gz"
ARRIBA_URL="${FUSION_ARRIBA_URL:-https://github.com/suhrig/arriba/releases/download/v${ARRIBA_VERSION}/${ARRIBA_ARCHIVE_NAME}}"
ARRIBA_ARCHIVE="${DOWNLOAD_DIR}/${ARRIBA_ARCHIVE_NAME}"
ARRIBA_DATABASE="${ARRIBA_ROOT}/database"

if [[ ! -d "$ARRIBA_DATABASE" ]]; then
    download_file "$ARRIBA_URL" "$ARRIBA_ARCHIVE"

    temporary_arriba_dir="$(mktemp -d "${ARRIBA_ROOT}/.extract.XXXXXX")"
    log_info "Extracting Arriba reference databases"
    tar -xzf "$ARRIBA_ARCHIVE" -C "$temporary_arriba_dir"

    extracted_arriba_database="$(
        find "$temporary_arriba_dir" \
            -type d \
            -name database \
            -print \
            -quit
    )"
    [[ -n "$extracted_arriba_database" ]] ||
        die "The Arriba archive did not contain a database directory"

    mv -- "$extracted_arriba_database" "$ARRIBA_DATABASE"
    rm -rf -- "$temporary_arriba_dir"
else
    log_info "Arriba databases are already installed"
fi

ARRIBA_BLACKLIST="$(
    find "$ARRIBA_DATABASE" -maxdepth 1 -type f \
        -name "blacklist*${ASSEMBLY}*" -print -quit
)"
ARRIBA_KNOWN_FUSIONS="$(
    find "$ARRIBA_DATABASE" -maxdepth 1 -type f \
        -name "known_fusions*${ASSEMBLY}*" -print -quit
)"
ARRIBA_PROTEIN_DOMAINS="$(
    find "$ARRIBA_DATABASE" -maxdepth 1 -type f \
        -name "protein_domains*${ASSEMBLY}*" -print -quit
)"

[[ -n "$ARRIBA_BLACKLIST" ]] ||
    die "No Arriba blacklist matching $ASSEMBLY was found in $ARRIBA_DATABASE"
[[ -n "$ARRIBA_KNOWN_FUSIONS" ]] ||
    die "No Arriba known-fusions file matching $ASSEMBLY was found in $ARRIBA_DATABASE"
[[ -n "$ARRIBA_PROTEIN_DOMAINS" ]] ||
    die "No Arriba protein-domain file matching $ASSEMBLY was found in $ARRIBA_DATABASE"

CONFIG_FILE="${CONFIG_DIR}/${ASSEMBLY}.config"
{
    printf 'FUSION_ASSEMBLY=%q\n' "$ASSEMBLY"
    printf 'FUSION_CTAT_GENOME_LIB=%q\n' "$CTAT_GENOME_LIB"
    printf 'FUSION_ARRIBA_BLACKLIST=%q\n' "$ARRIBA_BLACKLIST"
    printf 'FUSION_ARRIBA_KNOWN_FUSIONS=%q\n' "$ARRIBA_KNOWN_FUSIONS"
    printf 'FUSION_ARRIBA_PROTEIN_DOMAINS=%q\n' "$ARRIBA_PROTEIN_DOMAINS"
    printf 'FUSION_STAR_FUSION_EXECUTABLE=%q\n' "$STAR_FUSION_EXECUTABLE"
    printf 'FUSION_INSPECTOR_EXECUTABLE=%q\n' "$FUSION_INSPECTOR_EXECUTABLE"
    printf 'FUSION_CONDA_ENV=%q\n' "$CONDA_ENV"
} > "$CONFIG_FILE"

log_info "Fusion module installation completed"
log_info "Configuration: $CONFIG_FILE"
