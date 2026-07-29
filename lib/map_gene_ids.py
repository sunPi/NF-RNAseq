#!/usr/bin/env python3

"""Build reproducible GTF annotations and annotate expression matrices."""

from __future__ import annotations

import argparse
import csv
import gzip
import re
import sys
from pathlib import Path
from typing import TextIO


ATTRIBUTE_PATTERN = re.compile(r'([A-Za-z0-9_]+) "([^"]*)"')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create a gene annotation cache from the installed GTF or add "
            "gene_id, gene_name, and gene_type to an expression matrix."
        )
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--build-mapping", action="store_true")
    mode.add_argument("--input", type=Path)
    parser.add_argument("--gtf", type=Path)
    parser.add_argument("--mapping", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def open_text(path: Path) -> TextIO:
    if path.suffix == ".gz":
        return gzip.open(path, "rt")
    return path.open()


def clean_ensembl_id(identifier: str) -> str:
    return identifier.split(".", 1)[0]


def build_mapping(gtf: Path, output: Path) -> tuple[int, int]:
    if not gtf.is_file() or gtf.stat().st_size == 0:
        raise FileNotFoundError(f"GTF is missing or empty: {gtf}")

    annotations: dict[str, tuple[str, str]] = {}
    conflicts = 0
    with open_text(gtf) as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t", 8)
            if len(fields) != 9 or fields[2] != "gene":
                continue
            attributes = dict(ATTRIBUTE_PATTERN.findall(fields[8]))
            identifier = clean_ensembl_id(attributes.get("gene_id", ""))
            if not identifier:
                continue
            name = attributes.get("gene_name") or identifier
            gene_type = (
                attributes.get("gene_biotype")
                or attributes.get("gene_type")
                or "unannotated"
            )
            annotation = (name, gene_type)
            if identifier in annotations and annotations[identifier] != annotation:
                conflicts += 1
                continue
            annotations.setdefault(identifier, annotation)

    if not annotations:
        raise ValueError(f"No gene annotations were found in {gtf}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["gene_id", "gene_name", "gene_type"])
        for identifier, (name, gene_type) in annotations.items():
            writer.writerow([identifier, name, gene_type])
    return len(annotations), conflicts


def load_mapping(path: Path) -> dict[str, tuple[str, str]]:
    if not path.is_file() or path.stat().st_size == 0:
        raise FileNotFoundError(f"Gene mapping is missing or empty: {path}")
    mapping: dict[str, tuple[str, str]] = {}
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {"gene_id", "gene_name", "gene_type"}
        if not reader.fieldnames or not required.issubset(reader.fieldnames):
            raise ValueError(f"Gene mapping must contain: {', '.join(sorted(required))}")
        for row in reader:
            identifier = clean_ensembl_id(row["gene_id"])
            if identifier in mapping:
                raise ValueError(f"Duplicate gene_id in mapping: {identifier}")
            mapping[identifier] = (row["gene_name"], row["gene_type"])
    return mapping


def annotate_matrix(input_path: Path, mapping_path: Path, output: Path) -> tuple[int, int]:
    mapping = load_mapping(mapping_path)
    if not input_path.is_file() or input_path.stat().st_size == 0:
        raise FileNotFoundError(f"Expression matrix is missing or empty: {input_path}")

    output.parent.mkdir(parents=True, exist_ok=True)
    rows = 0
    unmapped = 0
    seen: set[str] = set()
    with input_path.open(newline="") as source, output.open(
        "w", newline=""
    ) as destination:
        reader = csv.DictReader(source, delimiter="\t")
        if not reader.fieldnames or "gene_id" not in reader.fieldnames:
            raise ValueError("Expression matrix must contain a gene_id column")
        value_columns = [name for name in reader.fieldnames if name != "gene_id"]
        writer = csv.writer(destination, delimiter="\t", lineterminator="\n")
        writer.writerow(["gene_id", "gene_name", "gene_type", *value_columns])
        for row in reader:
            identifier = clean_ensembl_id(row["gene_id"])
            if identifier in seen:
                raise ValueError(f"Duplicate gene_id in expression matrix: {identifier}")
            seen.add(identifier)
            annotation = mapping.get(identifier)
            if annotation is None:
                annotation = (identifier, "unannotated")
                unmapped += 1
            writer.writerow(
                [identifier, annotation[0], annotation[1]]
                + [row[column] for column in value_columns]
            )
            rows += 1
    if rows == 0:
        raise ValueError("Expression matrix contains no data rows")
    return rows, unmapped


def main() -> None:
    args = parse_args()
    if args.build_mapping:
        if args.gtf is None:
            raise ValueError("--build-mapping requires --gtf")
        genes, conflicts = build_mapping(args.gtf, args.output)
        print(
            f"[mapGeneID] Wrote {genes} genes to {args.output}; "
            f"ignored {conflicts} conflicting duplicate annotation(s)"
        )
        return

    if args.mapping is None:
        raise ValueError("Matrix annotation requires --mapping")
    rows, unmapped = annotate_matrix(args.input, args.mapping, args.output)
    print(
        f"[mapGeneID] Annotated {rows} rows in {args.output}; "
        f"{unmapped} gene ID(s) were not present in the mapping"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, csv.Error) as error:
        print(f"[mapGeneID] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error
