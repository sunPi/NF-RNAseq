#!/usr/bin/env python3

"""Create an NF-RNAseq sample sheet from an experiment FASTQ directory."""

from __future__ import annotations

import argparse
import csv
import os
import re
from pathlib import Path


FASTQ_EXTENSIONS = (".fastq.gz", ".fq.gz")
SAFE_IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
PAIRED_STEMS = (
    re.compile(r"^(?P<sample>.+)_R(?P<mate>[12])(?:_\d{3})?$"),
    re.compile(r"^(?P<sample>.+)_(?P<mate>[12])$"),
)
FIELDNAMES = (
    "experiment_id",
    "sample_id",
    "read_layout",
    "fastq_1",
    "fastq_2",
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Recursively discover .fastq.gz or .fq.gz files below one "
            "experiment directory and create an NF-RNAseq CSV sample sheet. "
            "Biological metadata are not inferred from underscore-delimited "
            "filenames; the complete sample stem is preserved."
        )
    )
    parser.add_argument(
        "--experiment-dir",
        "--input",
        dest="experiment_dir",
        required=True,
        type=Path,
        help="Directory containing one experiment's FASTQ files.",
    )
    parser.add_argument(
        "--layout",
        required=True,
        choices=("single", "paired"),
        help="Read layout. It is explicit because replicate suffixes can look like mates.",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="CSV sample sheet to create; its parent directory must exist.",
    )
    parser.add_argument(
        "--experiment-id",
        help="Experiment identifier; default: experiment directory name.",
    )
    parser.add_argument(
        "--relative-paths",
        action="store_true",
        help="Write FASTQ paths relative to the sample sheet directory.",
    )
    return parser.parse_args()


def remove_fastq_extension(filename: str) -> str:
    for extension in FASTQ_EXTENSIONS:
        if filename.endswith(extension):
            return filename[: -len(extension)]
    raise ValueError(f"Unsupported FASTQ filename: {filename}")


def discover_fastqs(experiment_dir: Path) -> list[Path]:
    fastqs = sorted(
        (
            path.resolve()
            for path in experiment_dir.rglob("*")
            if path.is_file() and path.name.endswith(FASTQ_EXTENSIONS)
        ),
        key=lambda path: str(path),
    )
    if not fastqs:
        raise ValueError(
            f"No .fastq.gz or .fq.gz files found below: {experiment_dir}"
        )
    for fastq in fastqs:
        if fastq.stat().st_size == 0:
            raise ValueError(f"FASTQ file is empty: {fastq}")
    return fastqs


def validate_identifier(value: str, label: str) -> None:
    if not SAFE_IDENTIFIER.fullmatch(value):
        raise ValueError(
            f"{label} must start with a letter or number and contain only "
            f"letters, numbers, dots, underscores, or hyphens: {value!r}"
        )


def parse_paired_stem(path: Path) -> tuple[str, int]:
    stem = remove_fastq_extension(path.name)
    for pattern in PAIRED_STEMS:
        match = pattern.fullmatch(stem)
        if match:
            return match.group("sample"), int(match.group("mate"))
    raise ValueError(
        "Paired FASTQ name must end in _1/_2, _R1/_R2, or "
        f"_R1_001/_R2_001 before its extension: {path}"
    )


def format_path(path: Path, output: Path, relative_paths: bool) -> str:
    if relative_paths:
        return os.path.relpath(path, start=output.parent.resolve())
    return str(path)


def build_single_records(
    fastqs: list[Path],
    experiment_id: str,
    output: Path,
    relative_paths: bool,
) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    seen_samples: dict[str, Path] = {}

    for fastq in fastqs:
        sample_id = remove_fastq_extension(fastq.name)
        validate_identifier(sample_id, "sample_id")
        if sample_id in seen_samples:
            raise ValueError(
                f"Duplicate sample_id {sample_id!r} from {seen_samples[sample_id]} "
                f"and {fastq}. Rename one file or use separate experiment sheets."
            )
        seen_samples[sample_id] = fastq
        records.append(
            {
                "experiment_id": experiment_id,
                "sample_id": sample_id,
                "read_layout": "single",
                "fastq_1": format_path(fastq, output, relative_paths),
                "fastq_2": "",
            }
        )
    return records


def build_paired_records(
    fastqs: list[Path],
    experiment_id: str,
    output: Path,
    relative_paths: bool,
) -> list[dict[str, str]]:
    pairs: dict[tuple[Path, str], dict[int, Path]] = {}

    for fastq in fastqs:
        sample_id, mate = parse_paired_stem(fastq)
        validate_identifier(sample_id, "sample_id")
        pair_key = (fastq.parent, sample_id)
        if mate in pairs.setdefault(pair_key, {}):
            raise ValueError(
                f"Duplicate R{mate} FASTQ for sample {sample_id!r}: "
                f"{pairs[pair_key][mate]} and {fastq}"
            )
        pairs[pair_key][mate] = fastq

    records: list[dict[str, str]] = []
    seen_samples: dict[str, Path] = {}
    for (_, sample_id), mates in sorted(
        pairs.items(), key=lambda item: (item[0][1], str(item[0][0]))
    ):
        if set(mates) != {1, 2}:
            present = ", ".join(f"R{mate}" for mate in sorted(mates))
            raise ValueError(
                f"Incomplete pair for sample {sample_id!r}; found {present}"
            )
        if sample_id in seen_samples:
            raise ValueError(
                f"Duplicate sample_id {sample_id!r} in multiple directories: "
                f"{seen_samples[sample_id]} and {mates[1].parent}"
            )
        seen_samples[sample_id] = mates[1].parent
        records.append(
            {
                "experiment_id": experiment_id,
                "sample_id": sample_id,
                "read_layout": "paired",
                "fastq_1": format_path(mates[1], output, relative_paths),
                "fastq_2": format_path(mates[2], output, relative_paths),
            }
        )
    return records


def create_samplesheet(
    experiment_dir: Path,
    layout: str,
    output: Path,
    experiment_id: str | None = None,
    relative_paths: bool = False,
) -> int:
    experiment_dir = experiment_dir.expanduser().resolve()
    output = output.expanduser().resolve()

    if not experiment_dir.is_dir():
        raise ValueError(f"Experiment directory does not exist: {experiment_dir}")
    if not output.parent.is_dir():
        raise ValueError(f"Output directory does not exist: {output.parent}")

    resolved_experiment_id = experiment_id or experiment_dir.name
    validate_identifier(resolved_experiment_id, "experiment_id")
    fastqs = discover_fastqs(experiment_dir)

    if layout == "single":
        records = build_single_records(
            fastqs, resolved_experiment_id, output, relative_paths
        )
    elif layout == "paired":
        records = build_paired_records(
            fastqs, resolved_experiment_id, output, relative_paths
        )
    else:
        raise ValueError(f"Unsupported read layout: {layout}")

    with output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(records)
    return len(records)


def main() -> None:
    args = parse_arguments()
    try:
        record_count = create_samplesheet(
            experiment_dir=args.experiment_dir,
            layout=args.layout,
            output=args.output,
            experiment_id=args.experiment_id,
            relative_paths=args.relative_paths,
        )
    except (OSError, ValueError) as error:
        raise SystemExit(f"ERROR: {error}") from error

    print(f"Created {args.output} with {record_count} {args.layout}-end sample(s).")


if __name__ == "__main__":
    main()
