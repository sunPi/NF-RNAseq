#!/usr/bin/env python3

"""Aggregate core RSEM transcript results into experiment-level matrices."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


METRICS = {
    "expected_counts": "expected_count",
    "TPM": "TPM",
    "FPKM": "FPKM",
    "isoform_fraction": "IsoPct",
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aggregate RSEM isoform results across QC-included samples."
    )
    parser.add_argument("--results-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    sample_group = parser.add_mutually_exclusive_group(required=True)
    sample_group.add_argument(
        "--sample",
        action="append",
        dest="samples",
        help="QC-included sample to aggregate; repeat for each sample",
    )
    sample_group.add_argument(
        "--samples-file",
        type=Path,
        help="File containing one QC-included sample name per line",
    )
    return parser.parse_args()


def load_samples(args: argparse.Namespace) -> list[str]:
    if args.samples_file:
        with args.samples_file.open() as handle:
            samples = [line.strip() for line in handle if line.strip()]
    else:
        samples = args.samples

    if not samples:
        raise ValueError("No samples were supplied")
    if len(samples) != len(set(samples)):
        raise ValueError("A sample was supplied more than once")
    return samples


def read_rsem(path: Path) -> tuple[list[tuple[str, str]], dict[str, list[str]]]:
    if not path.is_file() or path.stat().st_size == 0:
        raise FileNotFoundError(f"RSEM isoform result is missing or empty: {path}")

    metric_values = {metric: [] for metric in METRICS}
    identifiers: list[tuple[str, str]] = []
    seen_transcripts: set[str] = set()

    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {"transcript_id", "gene_id", *METRICS.values()}
        if not reader.fieldnames or not required.issubset(reader.fieldnames):
            missing = sorted(required - set(reader.fieldnames or []))
            raise ValueError(f"{path} is missing columns: {', '.join(missing)}")

        for row in reader:
            transcript = row["transcript_id"]
            if transcript in seen_transcripts:
                raise ValueError(f"Duplicate transcript_id in {path}: {transcript}")
            seen_transcripts.add(transcript)
            identifiers.append((transcript, row["gene_id"]))
            for metric, column in METRICS.items():
                metric_values[metric].append(row[column])

    if not identifiers:
        raise ValueError(f"RSEM isoform result contains no transcripts: {path}")
    return identifiers, metric_values


def write_matrix(
    path: Path,
    samples: list[str],
    identifiers: list[tuple[str, str]],
    values_by_sample: list[list[str]],
) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["transcript_id", "gene_id", *samples])
        for index, (transcript, gene) in enumerate(identifiers):
            writer.writerow(
                [
                    transcript,
                    gene,
                    *[values[index] for values in values_by_sample],
                ]
            )


def main() -> None:
    args = parse_arguments()
    samples = load_samples(args)
    reference_identifiers: list[tuple[str, str]] | None = None
    matrices: dict[str, list[list[str]]] = {metric: [] for metric in METRICS}

    for sample in samples:
        path = args.results_dir / sample / "rsem" / f"{sample}.isoforms.results"
        identifiers, sample_metrics = read_rsem(path)
        if reference_identifiers is None:
            reference_identifiers = identifiers
        elif identifiers != reference_identifiers:
            raise ValueError(
                f"Transcript identifiers/order in {path} do not match the first sample"
            )
        for metric in METRICS:
            matrices[metric].append(sample_metrics[metric])

    if reference_identifiers is None:
        raise ValueError("No RSEM isoform data were loaded")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for metric, values_by_sample in matrices.items():
        write_matrix(
            args.output_dir / f"transcript_{metric}.tsv",
            samples,
            reference_identifiers,
            values_by_sample,
        )


if __name__ == "__main__":
    main()
