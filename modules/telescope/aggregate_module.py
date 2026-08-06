#!/usr/bin/env python3
"""Aggregate per-sample Telescope locus counts into a cohort matrix."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--sample", action="append", dest="samples", required=True)
    return parser.parse_args()


def read_counts(path: Path) -> dict[str, str]:
    if not path.is_file() or path.stat().st_size == 0:
        raise FileNotFoundError(f"Telescope count table is missing or empty: {path}")
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames or not {"transcript", "count"}.issubset(reader.fieldnames):
            raise ValueError(f"Telescope table lacks transcript/count columns: {path}")
        values: dict[str, str] = {}
        for row in reader:
            locus = row["transcript"]
            if locus in values:
                raise ValueError(f"Duplicate Telescope locus in {path}: {locus}")
            values[locus] = row["count"]
    return values


def main() -> None:
    args = arguments()
    if len(args.samples) != len(set(args.samples)):
        raise ValueError("A sample was supplied more than once")
    by_sample = {
        sample: read_counts(
            args.results_dir / sample / "modules" / "Telescope" /
            f"{sample}-TE_counts.tsv"
        )
        for sample in args.samples
    }
    loci = sorted(set().union(*(values.keys() for values in by_sample.values())))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with (args.output_dir / "telescope_locus_counts.tsv").open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["te_locus", *args.samples])
        for locus in loci:
            writer.writerow([locus, *(by_sample[sample].get(locus, "0") for sample in args.samples)])


if __name__ == "__main__":
    main()
