#!/usr/bin/env python3
"""Aggregate TRUST4 bulk repertoire calls into cohort tables and matrices."""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--sample", action="append", dest="samples", required=True)
    return parser.parse_args()


def read_report(path: Path) -> list[dict[str, str]]:
    if not path.is_file() or path.stat().st_size == 0:
        raise FileNotFoundError(f"TRUST4 report is missing or empty: {path}")
    with path.open(newline="") as handle:
        first = handle.readline().lstrip("#")
        reader = csv.DictReader(handle, delimiter="\t", fieldnames=first.rstrip("\n").split("\t"))
        rows = list(reader)
    required = {"count", "frequency", "CDR3nt", "CDR3aa", "V", "D", "J", "C"}
    if not rows and not required.issubset(first.rstrip("\n").split("\t")):
        raise ValueError(f"Invalid TRUST4 report header: {path}")
    if rows and not required.issubset(rows[0]):
        raise ValueError(f"TRUST4 report lacks required columns: {path}")
    return rows


def main() -> None:
    args = arguments()
    if len(args.samples) != len(set(args.samples)):
        raise ValueError("A sample was supplied more than once")
    reports: dict[str, list[dict[str, str]]] = {}
    for sample in args.samples:
        reports[sample] = read_report(
            args.results_dir / sample / "modules" / "TRUST4" / f"{sample}_report.tsv"
        )

    counts: dict[str, dict[str, float]] = defaultdict(dict)
    frequencies: dict[str, dict[str, float]] = defaultdict(dict)
    catalog: list[list[str]] = []
    summaries: list[list[str]] = []
    for sample, rows in reports.items():
        for row in rows:
            clonotype = "|".join((row["CDR3nt"], row["V"], row["D"], row["J"], row["C"]))
            counts[clonotype][sample] = counts[clonotype].get(sample, 0.0) + float(row["count"])
            frequencies[clonotype][sample] = frequencies[clonotype].get(sample, 0.0) + float(row["frequency"])
            catalog.append([sample, clonotype, row["CDR3nt"], row["CDR3aa"], row["V"], row["D"], row["J"], row["C"], row["count"], row["frequency"]])
        total_reads = sum(float(row["count"]) for row in rows)
        productive = sum(
            row["CDR3aa"] not in {"", ".", "out_of_frame"}
            and "_" not in row["CDR3aa"] and "?" not in row["CDR3aa"]
            for row in rows
        )
        proportions = [float(row["count"]) / total_reads for row in rows if total_reads and float(row["count"]) > 0]
        shannon = -sum(value * math.log(value) for value in proportions)
        clonality = 1 - shannon / math.log(len(proportions)) if len(proportions) > 1 else (1.0 if proportions else 0.0)
        summaries.append([sample, str(len(rows)), f"{total_reads:.10g}", str(productive), f"{shannon:.10g}", f"{clonality:.10g}"])

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, values in (("clonotype_counts", counts), ("clonotype_frequencies", frequencies)):
        with (args.output_dir / f"trust4_{name}.tsv").open("w", newline="") as handle:
            writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
            writer.writerow(["clonotype", *args.samples])
            for clonotype in sorted(values):
                writer.writerow([clonotype, *(f"{values[clonotype].get(sample, 0):.10g}" for sample in args.samples)])
    with (args.output_dir / "trust4_clonotype_catalog.tsv").open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["sample", "clonotype", "CDR3nt", "CDR3aa", "V", "D", "J", "C", "count", "frequency"])
        writer.writerows(catalog)
    with (args.output_dir / "trust4_repertoire_summary.tsv").open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["sample", "clonotypes", "total_supporting_reads", "productive_clonotypes", "shannon_diversity", "clonality"])
        writer.writerows(summaries)

    airr_header: list[str] | None = None
    airr_rows: list[list[str]] = []
    for sample in args.samples:
        path = args.results_dir / sample / "modules" / "TRUST4" / f"{sample}_airr.tsv"
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(f"TRUST4 AIRR table is missing or empty: {path}")
        with path.open(newline="") as handle:
            reader = csv.reader(handle, delimiter="\t")
            header = next(reader)
            if airr_header is None:
                airr_header = header
            elif header != airr_header:
                raise ValueError(f"TRUST4 AIRR columns differ between samples: {path}")
            airr_rows.extend([[sample, *row] for row in reader])
    with (args.output_dir / "trust4_airr_rearrangements.tsv").open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["sample", *(airr_header or [])])
        writer.writerows(airr_rows)


if __name__ == "__main__":
    main()
