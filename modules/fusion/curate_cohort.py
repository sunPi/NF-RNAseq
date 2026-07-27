#!/usr/bin/env python3

"""Create auditable curated fusion matrices from cohort aggregation outputs."""

from __future__ import annotations

import argparse
import csv
import shutil
from pathlib import Path


MATRIX_FILES = (
    "star_fusion.junction_reads.tsv",
    "star_fusion.spanning_fragments.tsv",
    "star_fusion.total_support.tsv",
    "star_fusion.FFPM.tsv",
    "star_fusion.presence.tsv",
    "arriba.split_reads.tsv",
    "arriba.discordant_mates.tsv",
    "arriba.total_support.tsv",
    "arriba.presence.tsv",
    "fusion_gene_pair.caller_support.tsv",
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Filter cohort fusion outputs using a reviewed decisions table."
    )
    parser.add_argument("--input-dir", required=True, type=Path)
    parser.add_argument("--decisions", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    return parser.parse_args()


def retained_pairs(path: Path) -> set[str]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {"fusion_gene_pair", "decision"}
        if not reader.fieldnames or not required.issubset(reader.fieldnames):
            raise ValueError(
                "Decisions table must contain fusion_gene_pair and decision columns"
            )
        retained = {
            row["fusion_gene_pair"]
            for row in reader
            if row["decision"].strip().lower() == "retain"
        }
    if not retained:
        raise ValueError("Decisions table does not contain any retained fusions")
    return retained


def filter_matrix(source: Path, destination: Path, retained: set[str]) -> int:
    with source.open(newline="") as input_handle, destination.open(
        "w", newline=""
    ) as output_handle:
        reader = csv.reader(input_handle, delimiter="\t")
        writer = csv.writer(output_handle, delimiter="\t", lineterminator="\n")
        header = next(reader, None)
        if not header:
            raise ValueError(f"Matrix has no header: {source}")
        writer.writerow(header)
        count = 0
        for row in reader:
            pair = row[0].split("|", 1)[0]
            if pair in retained:
                writer.writerow(row)
                count += 1
    return count


def filter_catalog(source: Path, destination: Path, retained: set[str]) -> int:
    with source.open(newline="") as input_handle, destination.open(
        "w", newline=""
    ) as output_handle:
        reader = csv.DictReader(input_handle, delimiter="\t")
        if not reader.fieldnames or "gene_pair" not in reader.fieldnames:
            raise ValueError(f"Catalog does not contain a gene_pair column: {source}")
        writer = csv.DictWriter(
            output_handle,
            fieldnames=reader.fieldnames,
            delimiter="\t",
            lineterminator="\n",
        )
        writer.writeheader()
        count = 0
        for row in reader:
            if row["gene_pair"] in retained:
                writer.writerow(row)
                count += 1
    return count


def main() -> None:
    args = parse_arguments()
    retained = retained_pairs(args.decisions)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    for name in MATRIX_FILES:
        source = args.input_dir / name
        if not source.is_file():
            raise FileNotFoundError(f"Required aggregate matrix is missing: {source}")
        filter_matrix(source, args.output_dir / name, retained)

    catalog = args.input_dir / "fusion_event_catalog.tsv"
    if not catalog.is_file():
        raise FileNotFoundError(f"Required fusion catalog is missing: {catalog}")
    filter_catalog(
        catalog,
        args.output_dir / "fusion_event_catalog.tsv",
        retained,
    )
    shutil.copyfile(args.decisions, args.output_dir / "curation_decisions.tsv")


if __name__ == "__main__":
    main()
