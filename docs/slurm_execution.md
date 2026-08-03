# SLURM execution

The SLURM backend submits compute work and returns immediately. Core processing
uses one array task per sample. A cohort job is submitted with an `afterok`
dependency on the complete array and performs QC, matrix construction, MultiQC,
and optional modules. A modules-only invocation is submitted as one standalone
batch job against completed core results.

## Cluster profile

Create the untracked local profile:

```bash
cp config/slurm.config.example config/slurm.config
```

Set the partition and, where required, account and QoS. Resource values are
passed directly to `sbatch`:

```bash
SLURM_PARTITION="compute"
SLURM_ACCOUNT="rna_project"
SLURM_QOS="normal"
SLURM_CORE_CPUS=8
SLURM_CORE_MEMORY="64G"
SLURM_CORE_TIME="24:00:00"
SLURM_COHORT_CPUS=4
SLURM_COHORT_MEMORY="32G"
SLURM_COHORT_TIME="08:00:00"
SLURM_ARRAY_CONCURRENCY=20
```

`SLURM_ARRAY_CONCURRENCY` limits simultaneous samples and protects shared
filesystems. Set it to zero for no throttle. Put compute-node initialization in
`SLURM_JOB_SETUP`, for example `module load miniconda/py310 && conda activate
nf-env`. Jobs normally inherit the submitter environment, but explicit setup is
safer on clusters that do not export login-node environments.

Additional site options can be supplied as a Bash array:

```bash
SLURM_EXTRA_ARGS=(--constraint localssd --mail-type FAIL)
```

## Submission

Activate the installed environment and validate the generated commands first:

```bash
conda activate nf-env

./main.sh \
  --assembly GRCh38 \
  --layout paired \
  --experiment study_01 \
  --input /shared/fastq/study_01 \
  --pipeline core \
  --executor slurm \
  --slurm-profile config/slurm.config \
  --dry-run
```

Submit by removing `--dry-run`. The controller writes:

- `results/<experiment>/QC/logs/samples.tsv`: immutable array-index mapping
- `results/<experiment>/QC/logs/slurm/submitted_jobs.tsv`: submitted job IDs
- `results/<experiment>/QC/logs/slurm/core-<job>_<task>.out/.err`: array logs
- `results/<experiment>/QC/logs/slurm/cohort-<job>.out/.err`: cohort logs
- `results/<experiment>/QC/logs/sample_timings/<index>.tsv`: race-free timings

Each array task writes only within its sample directory. Shared QC manifests,
matrices, reports, and merged timings are created by the cohort job after the
array succeeds.

## Failure and restart

If any array task fails, SLURM keeps the `afterok` cohort job from running.
Inspect `sacct` and the corresponding array log, correct the problem, and
resubmit with the same experiment plus `--resume`:

```bash
./main.sh ... --executor slurm --resume
```

Samples containing `results/<experiment>/<sample>/.core_complete` are skipped.
The saved sample manifest is validated before resubmission; changed sample
names or FASTQ paths are rejected instead of being mixed into an existing run.

## Operational requirements

The repository, input FASTQs, references, Conda environments, and results path
must be visible at identical absolute paths on submit and compute nodes. The
SLURM CPU allocation overrides the installed `THREADS` setting, ensuring tools
do not use more worker threads than requested from the scheduler.
