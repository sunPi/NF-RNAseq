#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

###############################################################################
# RNA-seq reference and software installer
#
# Default:
#   - install GRCh38
#   - install SILVA rRNA mask
#
# Optional:
#   --with-hg19          install GRCh38 and GRCh37/hg19
#   --assembly hg19      install only GRCh37/hg19
#   --assembly hg38      install only GRCh38
#   --skip-software      skip Conda/Nextflow/R package installation
#   --skip-vep           skip VEP software and cache installation
#   --skip-rrna          skip SILVA rRNA reference installation
#   --threads N          number of threads
#   --read-length N      read length used for STAR sjdbOverhang
###############################################################################

###############################################################################
# Defaults
###############################################################################

SPECIES="homo_sapiens"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DB_ROOT="${SCRIPT_DIR}/db"

CONDA_ENV="nf-env"
VEP_CONDA_ENV="nf-vep-env"
VEP_CONDA_PREFIX=""
R_BASE_VERSION="4.3.3"
THREADS=8
READ_LENGTH=150

VEP_RELEASE="116"
SILVA_RELEASE="138.2"

INSTALL_GRCH38=true
INSTALL_GRCH37=false
INSTALL_SOFTWARE=true
INSTALL_VEP=true
INSTALL_RRNA=true
ADD_MODULES=""
VALIDATE_ONLY=false

###############################################################################
# Helpers
###############################################################################

log() {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    command_exists "$1" || die "Required command not found: $1"
}

usage() {
    cat <<'EOF'
Usage:
  install_pipe.sh [options]

Assembly options:
  --assembly GRCh38   Install only GRCh38
  --assembly hg38     Alias for GRCh38
  --assembly GRCh37   Install only GRCh37
  --assembly hg19     Alias for GRCh37
  --with-hg19         Install both GRCh38 and GRCh37

General options:
  --db-root PATH      Database root directory
  --threads N         Number of threads; default: 8
  --read-length N     STAR index read length; default: 150
  --skip-software     Skip Conda, Nextflow, and R package installation
  --skip-vep          Skip VEP software and cache installation
  --skip-rrna         Skip SILVA rRNA reference and Bowtie2 index
  --add-modules VALUE Install optional modules only: MODULE, comma-separated
                      MODULE list, or all
  --validate-only     Validate an existing core or module installation
  -h, --help          Show this help

Examples:
  ./install_pipe.sh
  ./install_pipe.sh --with-hg19
  ./install_pipe.sh --assembly hg19
  ./install_pipe.sh --assembly hg38 --threads 16
  ./install_pipe.sh --skip-software --with-hg19
  ./install_pipe.sh --add-modules fusion --assembly GRCh38
  ./install_pipe.sh --add-modules dge,gsea --assembly GRCh38
  ./install_pipe.sh --add-modules all --assembly GRCh38
  ./install_pipe.sh --assembly GRCh38 --validate-only
  ./install_pipe.sh --assembly GRCh38 --add-modules all --validate-only
EOF
}

###############################################################################
# Argument parsing
###############################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        --assembly)
            [[ $# -ge 2 ]] || die "--assembly requires a value."

            case "${2,,}" in
                grch38|hg38)
                    INSTALL_GRCH38=true
                    INSTALL_GRCH37=false
                    ;;
                grch37|hg19)
                    INSTALL_GRCH38=false
                    INSTALL_GRCH37=true
                    ;;
                *)
                    die "Unsupported assembly '$2'. Use GRCh38, hg38, GRCh37, or hg19."
                    ;;
            esac

            shift 2
            ;;

        --with-hg19)
            INSTALL_GRCH38=true
            INSTALL_GRCH37=true
            shift
            ;;

        --db-root)
            [[ $# -ge 2 ]] || die "--db-root requires a path."
            DB_ROOT="$2"
            shift 2
            ;;

        --threads)
            [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] ||
                die "--threads requires a positive integer."
            THREADS="$2"
            shift 2
            ;;

        --read-length)
            [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] ||
                die "--read-length requires a positive integer."
            READ_LENGTH="$2"
            shift 2
            ;;

        --skip-software)
            INSTALL_SOFTWARE=false
            shift
            ;;

        --skip-vep)
            INSTALL_VEP=false
            shift
            ;;

        --skip-rrna)
            INSTALL_RRNA=false
            shift
            ;;

        --add-modules)
            [[ $# -ge 2 ]] || die "--add-modules requires a module list."
            ADD_MODULES="$2"
            shift 2
            ;;

        --add-modules=*)
            ADD_MODULES="${1#*=}"
            shift
            ;;

        --validate-only)
            VALIDATE_ONLY=true
            shift
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            die "Unknown option: $1"
            ;;
    esac
done

mkdir -p "$DB_ROOT"
# Several installation steps run from a different working directory.  Resolve
# the database root now so paths passed to those tools remain valid after cd.
DB_ROOT="$(cd "$DB_ROOT" && pwd -P)"

install_optional_modules() {
    local requested_modules="$1"
    local assembly
    local module_name
    local module_db_root
    local module_installer
    local -a module_list
    local -a assembly_list=()

    if [[ "${requested_modules,,}" == "all" ]]; then
        mapfile -t module_list < <(
            find "${SCRIPT_DIR}/modules" \
                -mindepth 2 \
                -maxdepth 2 \
                -type f \
                -name install.sh \
                -executable \
                -printf '%h\n' |
                sed 's#.*/##' |
                sort -u
        )
    else
        IFS=',' read -r -a module_list <<< "$requested_modules"
    fi

    (( ${#module_list[@]} > 0 )) ||
        die "No installable optional modules were found."

    [[ "$INSTALL_GRCH38" != true ]] || assembly_list+=(GRCh38)
    [[ "$INSTALL_GRCH37" != true ]] || assembly_list+=(GRCh37)

    for module_name in "${module_list[@]}"; do
        module_name="${module_name#"${module_name%%[![:space:]]*}"}"
        module_name="${module_name%"${module_name##*[![:space:]]}"}"
        module_name="${module_name,,}"
        [[ "$module_name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] ||
            die "Invalid optional module name: $module_name"

        module_installer="${SCRIPT_DIR}/modules/${module_name}/install.sh"
        [[ -x "$module_installer" ]] ||
            die "Optional module has no executable installer: $module_name ($module_installer)"
        module_db_root="${DB_ROOT}/shared/${module_name}_module"
        mkdir -p "$module_db_root"

        for assembly in "${assembly_list[@]}"; do
            log "Installing optional module '$module_name' for $assembly"
            "$module_installer" \
                --assembly "$assembly" \
                --db-root "$DB_ROOT" \
                --module-db-root "$module_db_root" \
                --conda-env "$CONDA_ENV" \
                --threads "$THREADS"
            validate_optional_module "$module_name" "$assembly"
            record_installation "module" "$module_name" "$assembly" "installed"
        done
    done
}

record_installation() {
    local component_type="$1"
    local component_name="$2"
    local assembly="$3"
    local status="$4"
    local manifest="$DB_ROOT/install_manifest.tsv"
    local temporary_manifest

    temporary_manifest="$(mktemp "${DB_ROOT}/.install_manifest.XXXXXX")"
    if [[ -s "$manifest" ]]; then
        awk -F '\t' -v type="$component_type" -v name="$component_name" \
            -v assembly="$assembly" \
            'NR == 1 || !($1 == type && $2 == name && $3 == assembly)' \
            "$manifest" > "$temporary_manifest"
    else
        printf 'component_type\tcomponent_name\tassembly\tstatus\tupdated_utc\thost_architecture\tconda_environment\n' \
            > "$temporary_manifest"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$component_type" "$component_name" "$assembly" "$status" \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(uname -m)" "$CONDA_ENV" \
        >> "$temporary_manifest"
    mv -- "$temporary_manifest" "$manifest"
}

validate_optional_module() {
    local module_name="$1"
    local assembly="$2"
    local module_config="${DB_ROOT}/shared/${module_name}_module/config/${assembly}.config"
    local assignment
    local variable_name
    local variable_value

    [[ -s "$module_config" ]] ||
        die "Module '$module_name' is missing its $assembly configuration: $module_config"
    bash -n "$module_config" ||
        die "Module '$module_name' has invalid configuration syntax: $module_config"

    while IFS= read -r assignment; do
        variable_name="${assignment%%=*}"
        [[ "$variable_name" =~ ^[A-Z][A-Z0-9_]*$ ]] || continue
        variable_value="$(
            # shellcheck disable=SC1090
            source "$module_config"
            printf '%s' "${!variable_name:-}"
        )"
        if [[ "$variable_value" == /* && ! -e "$variable_value" ]]; then
            die "Module '$module_name' references a missing resource: $variable_value"
        fi
    done < <(grep -E '^[A-Z][A-Z0-9_]*=' "$module_config")

    log "Module '$module_name' passed $assembly installation validation"
}

validate_requested_modules() {
    local requested_modules="$1"
    local module_name
    local assembly
    local -a module_list
    local -a assembly_list=()

    if [[ "${requested_modules,,}" == "all" ]]; then
        mapfile -t module_list < <(
            find "${SCRIPT_DIR}/modules" -mindepth 2 -maxdepth 2 \
                -type f -name install.sh -executable -printf '%h\n' |
                sed 's#.*/##' | sort -u
        )
    else
        IFS=',' read -r -a module_list <<< "$requested_modules"
    fi
    [[ "$INSTALL_GRCH38" != true ]] || assembly_list+=(GRCh38)
    [[ "$INSTALL_GRCH37" != true ]] || assembly_list+=(GRCh37)

    for module_name in "${module_list[@]}"; do
        module_name="${module_name#"${module_name%%[![:space:]]*}"}"
        module_name="${module_name%"${module_name##*[![:space:]]}"}"
        module_name="${module_name,,}"
        for assembly in "${assembly_list[@]}"; do
            validate_optional_module "$module_name" "$assembly"
            record_installation "module" "$module_name" "$assembly" "validated"
        done
    done
}

###############################################################################
# Software installation
###############################################################################

initialise_conda() {
    if command_exists conda; then
        local conda_base
        conda_base="$(conda info --base)"
        # shellcheck disable=SC1091
        source "$conda_base/etc/profile.d/conda.sh"
        return
    fi

    die "Conda was not found. Install Miniconda, Miniforge, or Mambaforge first."
}

activate_pipeline_environment() {
    initialise_conda
    conda activate "$CONDA_ENV"
    [[ -n "${CONDA_PREFIX:-}" && -d "$CONDA_PREFIX/bin" ]] ||
        die "Conda environment '$CONDA_ENV' did not activate correctly."
    export PATH="$CONDA_PREFIX/bin:$PATH"
    hash -r
}

install_conda_environment() {
    initialise_conda
    if ! conda env list | awk '{print $1}' | grep -Fxq "$CONDA_ENV"; then
        log "Creating Conda environment: $CONDA_ENV"
        conda create --name "$CONDA_ENV" -y
    else
        log "Conda environment already exists: $CONDA_ENV"
    fi

    activate_pipeline_environment

    log "Installing RNA-seq software into Conda environment"

    conda install \
        -c conda-forge \
        -c bioconda \
        -y \
        nextflow \
        fastqc \
        fastp \
        multiqc \
        samtools \
        star \
        subread \
        rsem \
        gatk4 \
        arriba \
        trim-galore \
        bowtie2 \
        seqtk \
        picard \
        openjdk=17 \
        wget \
        curl \
        git \
        make \
        perl \
        perl-db_file \
        perl-dbi \
        python=3.11 \
        "r-base=${R_BASE_VERSION}"

    verify_conda_installation
}

verify_conda_installation() {
    local tools=(
        nextflow
        fastqc
        fastp
        multiqc
        STAR
        featureCounts
        rsem-prepare-reference
        rsem-calculate-expression
        samtools
        bowtie2
        bowtie2-build
        bowtie2-inspect
        seqtk
        gatk
        picard
        java
        wget
        curl
        git
        perl
        python3
        Rscript
    )

    printf '\n%-28s %-10s %s\n' "TOOL" "STATUS" "PATH"
    printf '%-28s %-10s %s\n' "----------------------------" "----------" "----"

    local tool
    local missing=0

    for tool in "${tools[@]}"; do
        if command_exists "$tool"; then
            printf '%-28s %-10s %s\n' "$tool" "FOUND" "$(command -v "$tool")"
        else
            printf '%-28s %-10s %s\n' "$tool" "MISSING" "-"
            missing=1
        fi
    done

    [[ "$missing" -eq 0 ]] ||
        die "One or more required tools are missing from the active environment."

    if perl -MDBI -e 'exit 0' 2>/dev/null; then
        printf '%-28s %-10s %s\n' "Perl DBI module" "FOUND" "$CONDA_PREFIX"
    else
        printf '%-28s %-10s %s\n' "Perl DBI module" "MISSING" "$CONDA_PREFIX"
        die "Perl DBI is missing from Conda environment '$CONDA_ENV'."
    fi

    if perl -MDB_File -e 'exit 0' 2>/dev/null; then
        printf '%-28s %-10s %s\n' "Perl DB_File module" "FOUND" "$CONDA_PREFIX"
    else
        printf '%-28s %-10s %s\n' "Perl DB_File module" "MISSING" "$CONDA_PREFIX"
        die "Perl DB_File is missing from Conda environment '$CONDA_ENV'."
    fi

    local installed_r_version
    installed_r_version="$(Rscript -e 'cat(paste(R.version$major, R.version$minor, sep="."))')"
    [[ "$installed_r_version" == "$R_BASE_VERSION" ]] ||
        die "R $installed_r_version is active, but renv.lock requires R $R_BASE_VERSION."
}

install_r_environment() {
    require_command Rscript

    local project_root
    local restore_script
    local lockfile

    project_root="$(
        cd "$(dirname "${BASH_SOURCE[0]}")" &&
        pwd
    )"

    restore_script="$project_root/setup/scripts/restore_renv.R"
    lockfile="$project_root/renv.lock"

    [[ -s "$restore_script" ]] ||
        die "renv restore script not found: $restore_script"

    [[ -s "$lockfile" ]] ||
        die "renv lockfile not found: $lockfile"

    log "Restoring project R environment with renv"
    printf '  Project root: %s\n' "$project_root"
    printf '  Restore script: %s\n' "$restore_script"
    printf '  Lockfile: %s\n' "$lockfile"

    Rscript \
        --vanilla \
        "$restore_script" \
        "$project_root"

    log "R environment restored successfully."
}

install_software() {
    install_conda_environment
    install_r_environment
}

###############################################################################
# VEP software installation
###############################################################################

VEP_REPOSITORY="https://github.com/Ensembl/ensembl-vep.git"
VEP_SOURCE_DIR="$DB_ROOT/tools/ensembl-vep/release-${VEP_RELEASE}"

install_vep_software() {
    require_command git

    log "Installing VEP $VEP_RELEASE in isolated Conda environment '$VEP_CONDA_ENV'"
    if conda env list | awk '{print $1}' | grep -Fxq "$VEP_CONDA_ENV"; then
        conda install --name "$VEP_CONDA_ENV" --channel conda-forge --channel bioconda \
            --yes "ensembl-vep=${VEP_RELEASE}"
    else
        conda create --name "$VEP_CONDA_ENV" --channel conda-forge --channel bioconda \
            --yes "ensembl-vep=${VEP_RELEASE}"
    fi
    VEP_CONDA_PREFIX="$(conda run --name "$VEP_CONDA_ENV" printenv CONDA_PREFIX)"

    mkdir -p "$(dirname "$VEP_SOURCE_DIR")"

    if [[ ! -d "$VEP_SOURCE_DIR/.git" ]]; then
        log "Downloading Ensembl VEP release ${VEP_RELEASE}"

        git clone \
            --branch "release/${VEP_RELEASE}" \
            --depth 1 \
            "$VEP_REPOSITORY" \
            "$VEP_SOURCE_DIR"
    else
        log "VEP source already exists: $VEP_SOURCE_DIR"
    fi

}

validate_vep_software() {
    VEP_CONDA_PREFIX="$(conda run --name "$VEP_CONDA_ENV" printenv CONDA_PREFIX)" ||
        die "VEP Conda environment is not installed: $VEP_CONDA_ENV"
    [[ -x "$VEP_CONDA_PREFIX/bin/vep" ]] ||
        die "VEP executable is missing: $VEP_CONDA_PREFIX/bin/vep"
    conda run --name "$VEP_CONDA_ENV" vep --help >/dev/null ||
        die "VEP executable validation failed in environment '$VEP_CONDA_ENV'."
    log "VEP software passed validation"
}

###############################################################################
# Assembly configuration
###############################################################################

configure_assembly() {
    local requested_assembly="$1"

    case "$requested_assembly" in
        GRCh38)
            ASSEMBLY="GRCh38"
            ASSEMBLY_ALIAS="hg38"

            REFERENCE_RELEASE="116"
            ANNOTATION_RELEASE="116"

            FTP_ROOT="https://ftp.ensembl.org/pub/release-${REFERENCE_RELEASE}"

            FASTA_NAME="Homo_sapiens.GRCh38.dna.primary_assembly.fa"
            GTF_NAME="Homo_sapiens.GRCh38.${ANNOTATION_RELEASE}.gtf"

            FASTA_URL="${FTP_ROOT}/fasta/homo_sapiens/dna/${FASTA_NAME}.gz"
            GTF_URL="${FTP_ROOT}/gtf/homo_sapiens/${GTF_NAME}.gz"
            ;;

        GRCh37)
            ASSEMBLY="GRCh37"
            ASSEMBLY_ALIAS="hg19"

            REFERENCE_RELEASE="87"
            ANNOTATION_RELEASE="87"

            FTP_ROOT="https://ftp.ensembl.org/pub/grch37/release-${REFERENCE_RELEASE}"

            FASTA_NAME="Homo_sapiens.GRCh37.dna.primary_assembly.fa"
            GTF_NAME="Homo_sapiens.GRCh37.${ANNOTATION_RELEASE}.gtf"

            FASTA_URL="${FTP_ROOT}/fasta/homo_sapiens/dna/${FASTA_NAME}.gz"
            GTF_URL="${FTP_ROOT}/gtf/homo_sapiens/${GTF_NAME}.gz"
            ;;

        *)
            die "Internal unsupported assembly: $requested_assembly"
            ;;
    esac

    ASSEMBLY_DIR="$DB_ROOT/$SPECIES/$ASSEMBLY"

    GENOME_DIR="$ASSEMBLY_DIR/genome"
    ANNOTATION_DIR="$ASSEMBLY_DIR/annotation"
    STAR_INDEX_DIR="$ASSEMBLY_DIR/STAR"
    RSEM_DIR="$ASSEMBLY_DIR/RSEM"

    VEP_ROOT="$ASSEMBLY_DIR/VEP"
    VEP_CACHE_DIR="$VEP_ROOT/cache"

    FASTA="$GENOME_DIR/$FASTA_NAME"
    FASTA_GZ="${FASTA}.gz"
    FASTA_DICT="${FASTA%.*}.dict"

    GTF="$ANNOTATION_DIR/$GTF_NAME"
    GTF_GZ="${GTF}.gz"
    GENE_ANNOTATION="$ANNOTATION_DIR/gene_annotation.tsv"

    RSEM_REFERENCE_PREFIX="$RSEM_DIR/reference"
    SJDB_OVERHANG=$((READ_LENGTH - 1))

    mkdir -p \
        "$GENOME_DIR" \
        "$ANNOTATION_DIR" \
        "$STAR_INDEX_DIR" \
        "$RSEM_DIR" \
        "$VEP_CACHE_DIR"

    log "Configured reference bundle"
    printf '  Assembly:           %s\n' "$ASSEMBLY"
    printf '  Alias:              %s\n' "$ASSEMBLY_ALIAS"
    printf '  Reference release:  %s\n' "$REFERENCE_RELEASE"
    printf '  Annotation release: %s\n' "$ANNOTATION_RELEASE"
    printf '  Destination:        %s\n' "$ASSEMBLY_DIR"
}

###############################################################################
# Genome preparation
###############################################################################

prepare_genome() {
    require_command wget
    require_command gzip
    require_command samtools
    require_command gatk

    log "Preparing $ASSEMBLY genome"

    if [[ ! -s "$FASTA" ]]; then
        if [[ ! -s "$FASTA_GZ" ]]; then
            log "Downloading $ASSEMBLY FASTA"
            printf '  %s\n' "$FASTA_URL"

            wget \
                --continue \
                --output-document "$FASTA_GZ" \
                "$FASTA_URL"
        else
            log "Compressed FASTA already exists: $FASTA_GZ"
        fi

        gzip -t "$FASTA_GZ"

        log "Decompressing FASTA"

        gzip -dc "$FASTA_GZ" > "${FASTA}.tmp"

        [[ -s "${FASTA}.tmp" ]] || {
            rm -f "${FASTA}.tmp"
            die "Decompressed FASTA is empty: ${FASTA}.tmp"
        }

        mv "${FASTA}.tmp" "$FASTA"
    else
        log "Reference FASTA already exists: $FASTA"
    fi

    if [[ ! -s "${FASTA}.fai" ]]; then
        log "Building samtools FASTA index"
        samtools faidx "$FASTA"
    else
        log "FASTA index already exists: ${FASTA}.fai"
    fi

    if [[ ! -s "$FASTA_DICT" ]]; then
        log "Creating GATK sequence dictionary"

        gatk CreateSequenceDictionary \
            --REFERENCE "$FASTA" \
            --OUTPUT "$FASTA_DICT"
    else
        log "Sequence dictionary already exists: $FASTA_DICT"
    fi
}

###############################################################################
# Annotation preparation
###############################################################################

prepare_annotations() {
    require_command wget
    require_command gzip
    require_command awk
    require_command python3

    log "Preparing $ASSEMBLY annotation"

    if [[ ! -s "$GTF" ]]; then
        if [[ ! -s "$GTF_GZ" ]]; then
            log "Downloading GTF"
            printf '  %s\n' "$GTF_URL"

            wget \
                --continue \
                --output-document "$GTF_GZ" \
                "$GTF_URL"
        else
            log "Compressed GTF already exists: $GTF_GZ"
        fi

        gzip -t "$GTF_GZ"

        log "Decompressing GTF"

        gzip -dc "$GTF_GZ" > "${GTF}.tmp"

        [[ -s "${GTF}.tmp" ]] || {
            rm -f "${GTF}.tmp"
            die "Decompressed GTF is empty: ${GTF}.tmp"
        }

        mv "${GTF}.tmp" "$GTF"
    else
        log "GTF already exists: $GTF"
    fi

    if ! awk -F '\t' '
        $0 !~ /^#/ && NF >= 9 {
            valid = 1
            exit
        }
        END {
            exit(valid ? 0 : 1)
        }
    ' "$GTF"; then
        die "GTF does not appear to contain valid annotation records: $GTF"
    fi

    log "GTF annotation appears valid."

    if [[ ! -s "$GENE_ANNOTATION" ]]; then
        log "Building reproducible gene annotation table"
        python3 "$SCRIPT_DIR/lib/map_gene_ids.py" \
            --build-mapping \
            --gtf "$GTF" \
            --output "$GENE_ANNOTATION"
    else
        log "Gene annotation table already exists: $GENE_ANNOTATION"
    fi
}

###############################################################################
# FASTA/GTF compatibility
###############################################################################

check_compatibility() {
    log "Checking FASTA/GTF contig compatibility"

    local fasta_contig_example
    local gtf_contig_example

    fasta_contig_example="$(
        awk '
            /^>/ {
                sub(/^>/, "")
                split($0, fields, /[[:space:]]+/)
                print fields[1]
                exit
            }
        ' "$FASTA"
    )"

    gtf_contig_example="$(
        awk -F '\t' '
            $0 !~ /^#/ {
                print $1
                exit
            }
        ' "$GTF"
    )"

    [[ -n "$fasta_contig_example" ]] ||
        die "No FASTA contig header found in: $FASTA"

    [[ -n "$gtf_contig_example" ]] ||
        die "No annotation contig found in: $GTF"

    printf '  FASTA example contig: %s\n' "$fasta_contig_example"
    printf '  GTF example contig:   %s\n' "$gtf_contig_example"

    if [[ "$fasta_contig_example" == chr* &&
          "$gtf_contig_example" != chr* ]]; then
        die "FASTA uses chr-prefixed contigs but GTF does not."
    fi

    if [[ "$fasta_contig_example" != chr* &&
          "$gtf_contig_example" == chr* ]]; then
        die "GTF uses chr-prefixed contigs but FASTA does not."
    fi

    log "FASTA and GTF chromosome naming schemes appear compatible."
}

###############################################################################
# STAR index
###############################################################################

build_star_index() {
    require_command STAR

    mkdir -p "$STAR_INDEX_DIR"

    local required_files=(
        "$STAR_INDEX_DIR/Genome"
        "$STAR_INDEX_DIR/SA"
        "$STAR_INDEX_DIR/SAindex"
        "$STAR_INDEX_DIR/chrName.txt"
        "$STAR_INDEX_DIR/chrLength.txt"
        "$STAR_INDEX_DIR/genomeParameters.txt"
    )

    local complete=true
    local file

    for file in "${required_files[@]}"; do
        if [[ ! -s "$file" ]]; then
            complete=false
            break
        fi
    done

    if [[ "$complete" == true ]]; then
        log "STAR index already exists: $STAR_INDEX_DIR"
        return
    fi

    log "Building STAR index"
    printf '  FASTA:        %s\n' "$FASTA"
    printf '  GTF:          %s\n' "$GTF"
    printf '  Output:       %s\n' "$STAR_INDEX_DIR"
    printf '  Threads:      %s\n' "$THREADS"
    printf '  sjdbOverhang: %s\n' "$SJDB_OVERHANG"

    find "$STAR_INDEX_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -delete

    STAR \
        --runMode genomeGenerate \
        --runThreadN "$THREADS" \
        --genomeDir "$STAR_INDEX_DIR" \
        --genomeFastaFiles "$FASTA" \
        --sjdbGTFfile "$GTF" \
        --sjdbOverhang "$SJDB_OVERHANG"

    for file in "${required_files[@]}"; do
        [[ -s "$file" ]] ||
            die "STAR index build did not produce: $file"
    done

    log "STAR index created successfully."
}

###############################################################################
# RSEM reference
###############################################################################

prepare_rsem_reference() {
    require_command rsem-prepare-reference

    mkdir -p "$RSEM_DIR"

    local required_files=(
        "${RSEM_REFERENCE_PREFIX}.grp"
        "${RSEM_REFERENCE_PREFIX}.ti"
        "${RSEM_REFERENCE_PREFIX}.seq"
        "${RSEM_REFERENCE_PREFIX}.idx.fa"
        "${RSEM_REFERENCE_PREFIX}.n2g.idx.fa"
        "${RSEM_REFERENCE_PREFIX}.transcripts.fa"
    )

    local complete=true
    local file

    for file in "${required_files[@]}"; do
        if [[ ! -s "$file" ]]; then
            complete=false
            break
        fi
    done

    if [[ "$complete" == true ]]; then
        log "RSEM reference already exists: $RSEM_REFERENCE_PREFIX"
        return
    fi

    log "Building RSEM reference"
    printf '  FASTA:   %s\n' "$FASTA"
    printf '  GTF:     %s\n' "$GTF"
    printf '  Prefix:  %s\n' "$RSEM_REFERENCE_PREFIX"
    printf '  Threads: %s\n' "$THREADS"

    find "$RSEM_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -delete

    rsem-prepare-reference \
        --gtf "$GTF" \
        --num-threads "$THREADS" \
        "$FASTA" \
        "$RSEM_REFERENCE_PREFIX"

    for file in "${required_files[@]}"; do
        [[ -s "$file" ]] ||
            die "RSEM reference build did not produce: $file"
    done

    log "RSEM reference created successfully."
}

###############################################################################
# VEP cache
###############################################################################

install_vep_cache() {
    local expected_cache_dir
    expected_cache_dir="$VEP_CACHE_DIR/$SPECIES/${VEP_RELEASE}_${ASSEMBLY}"

    if [[ -s "$expected_cache_dir/info.txt" ]]; then
        log "VEP cache already exists: $expected_cache_dir"
        return
    fi

    log "Installing VEP ${VEP_RELEASE} cache for ${ASSEMBLY}"

    (
        cd "$VEP_SOURCE_DIR"

        conda run --name "$VEP_CONDA_ENV" perl INSTALL.pl \
            --AUTO c \
            --SPECIES "$SPECIES" \
            --ASSEMBLY "$ASSEMBLY" \
            --CACHEDIR "$VEP_CACHE_DIR" \
            --NO_UPDATE
    )

    [[ -s "$expected_cache_dir/info.txt" ]] ||
        die "VEP cache installation did not create: $expected_cache_dir/info.txt"
}

###############################################################################
# Metadata
###############################################################################

write_metadata() {
    local metadata_file="$ASSEMBLY_DIR/metadata.yaml"

    log "Writing metadata"

    cat > "$metadata_file" <<EOF
species: "$SPECIES"
assembly: "$ASSEMBLY"
assembly_alias: "$ASSEMBLY_ALIAS"

reference:
  source: "Ensembl"
  release: "$REFERENCE_RELEASE"
  fasta:
    file: "$FASTA_NAME"
    url: "$FASTA_URL"

annotation:
  source: "Ensembl"
  release: "$ANNOTATION_RELEASE"
  gtf:
    file: "$GTF_NAME"
    url: "$GTF_URL"
  gene_mapping:
    file: "$(basename "$GENE_ANNOTATION")"

star:
  read_length: $READ_LENGTH
  sjdb_overhang: $SJDB_OVERHANG

vep:
  enabled: $INSTALL_VEP
  release: "$VEP_RELEASE"
  conda_environment: "$VEP_CONDA_ENV"
  cache_directory: "$VEP_CACHE_DIR"

build:
  threads: $THREADS
  host_architecture: "$(uname -m)"
  conda_environment: "$CONDA_ENV"
  r_version: "$R_BASE_VERSION"
  date_utc: "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF

    log "Metadata written: $metadata_file"
}

###############################################################################
# Sourceable pipeline configuration
###############################################################################

write_bash_config() {
    local config_file="$SCRIPT_DIR/config/main.config"
    local default_assembly

    if [[ "$INSTALL_GRCH38" == true ]]; then
        default_assembly="GRCh38"
    else
        default_assembly="GRCh37"
    fi

    log "Writing sourceable Bash configuration"
    mkdir -p "$(dirname "$config_file")"

    {
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            '# Generated by install_pipe.sh. Do not edit by hand.' \
            '# Source this file, then call select_reference_assembly with the' \
            '# assembly flag parsed by main.sh, for example:' \
            '#   source config/main.config' \
            '#   select_reference_assembly "$assembly_flag"' \
            ''

        printf 'DB_ROOT=%q\n' "$DB_ROOT"
        printf 'SPECIES=%q\n' "$SPECIES"
        printf 'CONDA_ENV=%q\n' "$CONDA_ENV"
        printf 'R_BASE_VERSION=%q\n' "$R_BASE_VERSION"
        printf 'THREADS=%q\n' "$THREADS"
        printf 'READ_LENGTH=%q\n' "$READ_LENGTH"
        printf 'VEP_RELEASE=%q\n' "$VEP_RELEASE"
        printf 'VEP_CONDA_ENV=%q\n' "$VEP_CONDA_ENV"
        printf 'VEP_CONDA_PREFIX=%q\n' "$VEP_CONDA_PREFIX"
        printf 'VEP_SOURCE_DIR=%q\n' "$VEP_SOURCE_DIR"
        printf 'SILVA_RELEASE=%q\n' "$SILVA_RELEASE"
        printf 'INSTALL_GRCH38=%q\n' "$INSTALL_GRCH38"
        printf 'INSTALL_GRCH37=%q\n' "$INSTALL_GRCH37"
        printf 'INSTALL_VEP=%q\n' "$INSTALL_VEP"
        printf 'INSTALL_RRNA=%q\n' "$INSTALL_RRNA"
        printf 'DEFAULT_ASSEMBLY=%q\n' "$default_assembly"

        printf '%s\n' \
            'SILVA_DIR="$DB_ROOT/shared/rRNA/SILVA/$SILVA_RELEASE"' \
            'RRNA_FASTA="$SILVA_DIR/SILVA_${SILVA_RELEASE}_SSU_LSU_NR99_rRNA_mask.fa"' \
            'RRNA_BOWTIE2_PREFIX="$SILVA_DIR/SILVA_${SILVA_RELEASE}_SSU_LSU_NR99"' \
            '' \
            'select_reference_assembly() {' \
            '    local requested_assembly="${1:-}"' \
            '' \
            '    case "${requested_assembly,,}" in'

        printf '%s\n' \
                '    grch38|hg38)' \
                '        ASSEMBLY="GRCh38"' \
                '        ASSEMBLY_ALIAS="hg38"' \
                '        REFERENCE_RELEASE="116"' \
                '        ANNOTATION_RELEASE="116"' \
                '        FASTA_NAME="Homo_sapiens.GRCh38.dna.primary_assembly.fa"' \
                '        GTF_NAME="Homo_sapiens.GRCh38.116.gtf"' \
                '        ;;'

        printf '%s\n' \
                '    grch37|hg19)' \
                '        ASSEMBLY="GRCh37"' \
                '        ASSEMBLY_ALIAS="hg19"' \
                '        REFERENCE_RELEASE="87"' \
                '        ANNOTATION_RELEASE="87"' \
                '        FASTA_NAME="Homo_sapiens.GRCh37.dna.primary_assembly.fa"' \
                '        GTF_NAME="Homo_sapiens.GRCh37.87.gtf"' \
                '        ;;'

        printf '%s\n' \
            '    *)' \
            '        printf "ERROR: Unsupported assembly: %s (use GRCh38/hg38 or GRCh37/hg19)\n" "$requested_assembly" >&2' \
            '        return 2' \
            '        ;;' \
            'esac' \
            '' \
            'ASSEMBLY_DIR="$DB_ROOT/$SPECIES/$ASSEMBLY"' \
            'GENOME_DIR="$ASSEMBLY_DIR/genome"' \
            'ANNOTATION_DIR="$ASSEMBLY_DIR/annotation"' \
            'STAR_INDEX_DIR="$ASSEMBLY_DIR/STAR"' \
            'RSEM_DIR="$ASSEMBLY_DIR/RSEM"' \
            'RSEM_REFERENCE_PREFIX="$RSEM_DIR/reference"' \
            'VEP_ROOT="$ASSEMBLY_DIR/VEP"' \
            'VEP_EXECUTABLE="$VEP_CONDA_PREFIX/bin/vep"' \
            'VEP_CACHE_DIR="$VEP_ROOT/cache"' \
            'VEP_ASSEMBLY_CACHE_DIR="$VEP_CACHE_DIR/$SPECIES/${VEP_RELEASE}_${ASSEMBLY}"' \
            'FASTA="$GENOME_DIR/$FASTA_NAME"' \
            'FASTA_FAI="${FASTA}.fai"' \
            'FASTA_DICT="${FASTA%.*}.dict"' \
            'GTF="$ANNOTATION_DIR/$GTF_NAME"' \
            'GENE_ANNOTATION="$ANNOTATION_DIR/gene_annotation.tsv"' \
            'SJDB_OVERHANG=$((READ_LENGTH - 1))' \
            '' \
            '# Convenient pipeline-facing aliases.' \
            'STAR_INDEX="$STAR_INDEX_DIR"' \
            'GENOME_FASTA="$FASTA"' \
            'RSEM_REFERENCE="$RSEM_REFERENCE_PREFIX"' \
            '' \
            '    local required_path' \
            '    for required_path in \' \
            '        "$FASTA" \' \
            '        "$GTF" \' \
            '        "$STAR_INDEX_DIR/Genome" \' \
            '        "${RSEM_REFERENCE_PREFIX}.grp"; do' \
            '        if [[ ! -s "$required_path" ]]; then' \
            '            printf "ERROR: %s reference is not completely installed; missing: %s\n" "$ASSEMBLY" "$required_path" >&2' \
            '            return 1' \
            '        fi' \
            '    done' \
            '' \
            '    if [[ "$INSTALL_VEP" == true ]]; then' \
            '        if [[ ! -x "$VEP_EXECUTABLE" ]]; then' \
            '            printf "ERROR: VEP executable is not installed: %s\n" "$VEP_EXECUTABLE" >&2' \
            '            return 1' \
            '        fi' \
            '        if [[ ! -s "$VEP_ASSEMBLY_CACHE_DIR/info.txt" ]]; then' \
            '            printf "ERROR: %s VEP cache is not installed: %s\n" "$ASSEMBLY" "$VEP_ASSEMBLY_CACHE_DIR/info.txt" >&2' \
            '            return 1' \
            '        fi' \
            '    fi' \
            '}' \
            '' \
            '# No assembly is selected merely by sourcing this file.' \
            '# main.sh must call select_reference_assembly explicitly.'
    } > "$config_file"

    bash -n "$config_file" ||
        die "Generated Bash configuration is invalid: $config_file"

    log "Bash configuration written: $config_file"
    printf '  Source with: source %q\n' "$config_file"
}

###############################################################################
# Validate generated runtime contract
###############################################################################

validate_runtime_contract() {
    local config_file="$SCRIPT_DIR/config/main.config"
    local required_project_file

    log "Validating generated configuration and pipeline runtime files"

    for required_project_file in \
        "$SCRIPT_DIR/main.sh" \
        "$SCRIPT_DIR/config/qc.config" \
        "$SCRIPT_DIR/lib/map_gene_ids.py" \
        "$SCRIPT_DIR/lib/handle_gene_dups.R" \
        "$SCRIPT_DIR/modules/qc/qc_validator.py"; do
        [[ -s "$required_project_file" ]] ||
            die "Required base repository file is missing or empty: $required_project_file"
    done

    (
        # shellcheck disable=SC1090
        source "$config_file"

        if [[ "$INSTALL_GRCH38" == true ]]; then
            select_reference_assembly GRCh38
        fi

        if [[ "$INSTALL_GRCH37" == true ]]; then
            select_reference_assembly GRCh37
        fi
    ) || die "Generated pipeline configuration failed reference validation."

    mkdir -p "$SCRIPT_DIR/results"
    log "Pipeline runtime contract passed validation."
}

###############################################################################
# Validate completed assembly
###############################################################################

validate_reference_bundle() {
    log "Validating $ASSEMBLY reference bundle"

    local required_files=(
        "$FASTA"
        "${FASTA}.fai"
        "$FASTA_DICT"
        "$GTF"
        "$GENE_ANNOTATION"
        "$STAR_INDEX_DIR/Genome"
        "$STAR_INDEX_DIR/SA"
        "$STAR_INDEX_DIR/SAindex"
        "${RSEM_REFERENCE_PREFIX}.grp"
        "${RSEM_REFERENCE_PREFIX}.ti"
        "${RSEM_REFERENCE_PREFIX}.seq"
        "$ASSEMBLY_DIR/metadata.yaml"
    )

    local file
    for file in "${required_files[@]}"; do
        [[ -s "$file" ]] ||
            die "Reference validation failed; missing or empty: $file"
    done

    if [[ "$INSTALL_VEP" == true ]]; then
        local cache_info
        cache_info="$VEP_CACHE_DIR/$SPECIES/${VEP_RELEASE}_${ASSEMBLY}/info.txt"

        [[ -s "$cache_info" ]] ||
            die "Reference validation failed; missing VEP cache metadata: $cache_info"
    fi

    log "$ASSEMBLY reference bundle passed validation."
}

###############################################################################
# SILVA rRNA mask
###############################################################################

prepare_silva_rrna_reference() {
    require_command wget
    require_command gzip
    require_command awk
    require_command bowtie2-build
    require_command bowtie2-inspect

    local rrna_dir
    local base_url
    local ssu_name
    local lsu_name
    local ssu_gz
    local lsu_gz
    local ssu_url
    local lsu_url
    local rrna_fasta
    local bowtie2_prefix

    rrna_dir="$DB_ROOT/shared/rRNA/SILVA/$SILVA_RELEASE"
    base_url="https://www.arb-silva.de/fileadmin/silva_databases/current/Exports"

    ssu_name="SILVA_${SILVA_RELEASE}_SSURef_NR99_tax_silva.fasta.gz"
    lsu_name="SILVA_${SILVA_RELEASE}_LSURef_NR99_tax_silva.fasta.gz"

    ssu_gz="$rrna_dir/$ssu_name"
    lsu_gz="$rrna_dir/$lsu_name"

    ssu_url="$base_url/$ssu_name"
    lsu_url="$base_url/$lsu_name"

    rrna_fasta="$rrna_dir/SILVA_${SILVA_RELEASE}_SSU_LSU_NR99_rRNA_mask.fa"
    bowtie2_prefix="$rrna_dir/SILVA_${SILVA_RELEASE}_SSU_LSU_NR99"

    mkdir -p "$rrna_dir"

    if [[ ! -s "$ssu_gz" ]]; then
        log "Downloading SILVA SSURef NR99"
        wget \
            --continue \
            --output-document "$ssu_gz" \
            "$ssu_url"
    else
        log "SILVA SSU file already exists: $ssu_gz"
    fi

    if [[ ! -s "$lsu_gz" ]]; then
        log "Downloading SILVA LSURef NR99"
        wget \
            --continue \
            --output-document "$lsu_gz" \
            "$lsu_url"
    else
        log "SILVA LSU file already exists: $lsu_gz"
    fi

    gzip -t "$ssu_gz"
    gzip -t "$lsu_gz"

    if [[ ! -s "$rrna_fasta" ]]; then
        log "Combining SILVA SSU and LSU references"

        local temporary_fasta="${rrna_fasta}.tmp"
        rm -f "$temporary_fasta"

        gzip -dc "$ssu_gz" |
            awk '
                /^>/ {
                    sub(/^>/, ">SSU|")
                    print
                    next
                }
                {
                    gsub(/U/, "T")
                    gsub(/u/, "t")
                    print
                }
            ' > "$temporary_fasta"

        gzip -dc "$lsu_gz" |
            awk '
                /^>/ {
                    sub(/^>/, ">LSU|")
                    print
                    next
                }
                {
                    gsub(/U/, "T")
                    gsub(/u/, "t")
                    print
                }
            ' >> "$temporary_fasta"

        [[ -s "$temporary_fasta" ]] || {
            rm -f "$temporary_fasta"
            die "Combined SILVA FASTA is empty."
        }

        mv "$temporary_fasta" "$rrna_fasta"
    else
        log "Combined SILVA FASTA already exists: $rrna_fasta"
    fi

    local sequence_count
    sequence_count="$(grep -c '^>' "$rrna_fasta")"

    [[ "$sequence_count" -gt 0 ]] ||
        die "No FASTA records detected in $rrna_fasta"

    log "Combined SILVA FASTA contains $sequence_count records."

    if grep -v '^>' "$rrna_fasta" |
       grep -qiE '[^ACGTNRYKMSWBDHVacgtnrykmswbdhv]'; then
        die "Unexpected characters detected in the SILVA FASTA."
    fi

    local small_index_files=(
        "${bowtie2_prefix}.1.bt2"
        "${bowtie2_prefix}.2.bt2"
        "${bowtie2_prefix}.3.bt2"
        "${bowtie2_prefix}.4.bt2"
        "${bowtie2_prefix}.rev.1.bt2"
        "${bowtie2_prefix}.rev.2.bt2"
    )

    local large_index_files=(
        "${bowtie2_prefix}.1.bt2l"
        "${bowtie2_prefix}.2.bt2l"
        "${bowtie2_prefix}.3.bt2l"
        "${bowtie2_prefix}.4.bt2l"
        "${bowtie2_prefix}.rev.1.bt2l"
        "${bowtie2_prefix}.rev.2.bt2l"
    )

    bowtie2_index_complete() {
        local file
        local small_complete=true
        local large_complete=true

        for file in "${small_index_files[@]}"; do
            [[ -s "$file" ]] || small_complete=false
        done

        for file in "${large_index_files[@]}"; do
            [[ -s "$file" ]] || large_complete=false
        done

        [[ "$small_complete" == true || "$large_complete" == true ]]
    }

    if bowtie2_index_complete; then
        log "SILVA Bowtie2 index already exists: ${bowtie2_prefix}.*"
    else
        log "Building SILVA Bowtie2 index"

        rm -f \
            "${bowtie2_prefix}".*.bt2 \
            "${bowtie2_prefix}".*.bt2l

        bowtie2-build \
            --threads "$THREADS" \
            "$rrna_fasta" \
            "$bowtie2_prefix"

        bowtie2_index_complete ||
            die "Bowtie2 did not produce a complete SILVA index."
    fi

    bowtie2-inspect \
        --summary \
        "$bowtie2_prefix"

    cat > "$rrna_dir/metadata.yaml" <<EOF
source: "SILVA"
release: "$SILVA_RELEASE"
components:
  - "$ssu_name"
  - "$lsu_name"
combined_fasta: "$(basename "$rrna_fasta")"
bowtie2_prefix: "$(basename "$bowtie2_prefix")"
build:
  threads: $THREADS
  date_utc: "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF

    log "SILVA rRNA reference completed successfully."
}

validate_silva_rrna_reference() {
    require_command bowtie2-inspect

    local rrna_dir="$DB_ROOT/shared/rRNA/SILVA/$SILVA_RELEASE"
    local rrna_fasta="$rrna_dir/SILVA_${SILVA_RELEASE}_SSU_LSU_NR99_rRNA_mask.fa"
    local bowtie2_prefix="$rrna_dir/SILVA_${SILVA_RELEASE}_SSU_LSU_NR99"
    local suffix
    local small_complete=true
    local large_complete=true

    [[ -s "$rrna_fasta" ]] ||
        die "SILVA validation failed; missing combined FASTA: $rrna_fasta"
    for suffix in 1 2 3 4 rev.1 rev.2; do
        [[ -s "${bowtie2_prefix}.${suffix}.bt2" ]] || small_complete=false
        [[ -s "${bowtie2_prefix}.${suffix}.bt2l" ]] || large_complete=false
    done
    [[ "$small_complete" == true || "$large_complete" == true ]] ||
        die "SILVA validation failed; incomplete Bowtie2 index: $bowtie2_prefix"

    bowtie2-inspect --summary "$bowtie2_prefix" >/dev/null ||
        die "SILVA validation failed; Bowtie2 could not inspect: $bowtie2_prefix"
    log "SILVA rRNA reference passed validation."
}

###############################################################################
# Build one assembly
###############################################################################

build_reference_bundle() {
    local assembly="$1"

    configure_assembly "$assembly"
    prepare_genome
    prepare_annotations
    check_compatibility
    build_star_index
    prepare_rsem_reference

    if [[ "$INSTALL_VEP" == true ]]; then
        install_vep_cache
    fi

    write_metadata
    validate_reference_bundle
    record_installation "core" "reference_bundle" "$ASSEMBLY" "installed"

    log "$ASSEMBLY reference bundle completed successfully."
}

###############################################################################
# Main
###############################################################################

main() {
    log "RNA-seq installer started"

    printf '  Database root: %s\n' "$DB_ROOT"
    printf '  Threads:       %s\n' "$THREADS"
    printf '  Read length:   %s\n' "$READ_LENGTH"
    printf '  Install hg38:  %s\n' "$INSTALL_GRCH38"
    printf '  Install hg19:  %s\n' "$INSTALL_GRCH37"
    printf '  Install VEP:   %s\n' "$INSTALL_VEP"
    printf '  Install rRNA:  %s\n' "$INSTALL_RRNA"

    if [[ -n "$ADD_MODULES" ]]; then
        activate_pipeline_environment
        verify_conda_installation
        if [[ "$VALIDATE_ONLY" == true ]]; then
            validate_requested_modules "$ADD_MODULES"
            log "Requested optional modules passed validation"
        else
            install_optional_modules "$ADD_MODULES"
            log "Optional-module installation completed"
        fi
        return
    fi

    if [[ "$VALIDATE_ONLY" == true ]]; then
        activate_pipeline_environment
        verify_conda_installation
        if [[ "$INSTALL_VEP" == true ]]; then
            validate_vep_software
        fi
        if [[ "$INSTALL_GRCH38" == true ]]; then
            configure_assembly GRCh38
            validate_reference_bundle
            record_installation "core" "reference_bundle" "GRCh38" "validated"
        fi
        if [[ "$INSTALL_GRCH37" == true ]]; then
            configure_assembly GRCh37
            validate_reference_bundle
            record_installation "core" "reference_bundle" "GRCh37" "validated"
        fi
        if [[ "$INSTALL_RRNA" == true ]]; then
            validate_silva_rrna_reference
        fi
        validate_runtime_contract
        log "Existing installation passed validation"
        return
    fi

    if [[ "$INSTALL_SOFTWARE" == true ]]; then
        install_software
    else
        activate_pipeline_environment
        verify_conda_installation
    fi

    if [[ "$INSTALL_VEP" == true ]]; then
        install_vep_software
        validate_vep_software
    fi

    if [[ "$INSTALL_GRCH38" == true ]]; then
        build_reference_bundle "GRCh38"
    fi

    if [[ "$INSTALL_GRCH37" == true ]]; then
        build_reference_bundle "GRCh37"
    fi

    if [[ "$INSTALL_RRNA" == true ]]; then
        prepare_silva_rrna_reference
        validate_silva_rrna_reference
    fi

    write_bash_config
    validate_runtime_contract

    log "All requested installations completed successfully."
}

main "$@"
