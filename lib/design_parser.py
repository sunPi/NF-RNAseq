#!/usr/bin/env python3

"""Validate and normalize experiment design metadata and contrasts."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import Counter
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--design", required=True, type=Path)
    parser.add_argument("--samples-file", required=True, type=Path)
    parser.add_argument("--output-design", required=True, type=Path)
    parser.add_argument("--output-contrasts", required=True, type=Path)
    parser.add_argument("--contrast", action="append", default=[])
    return parser.parse_args()


def delimiter(path: Path) -> str:
    with path.open(newline="") as handle:
        header = handle.readline()
    return "\t" if "\t" in header else ","


def safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("_")


def main() -> None:
    args = parse_args()
    with args.samples_file.open() as handle:
        samples = [line.strip() for line in handle if line.strip()]
    if not samples or len(samples) != len(set(samples)):
        raise ValueError("QC sample list is empty or contains duplicates")

    with args.design.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter(args.design))
        if not reader.fieldnames or "sample" not in reader.fieldnames:
            raise ValueError("Design must contain a 'sample' column")
        if len(reader.fieldnames) != len(set(reader.fieldnames)):
            raise ValueError("Design contains duplicate column names")
        rows = list(reader)

    design_samples = [row["sample"].strip() for row in rows]
    duplicates = sorted(name for name, count in Counter(design_samples).items() if count > 1)
    if duplicates:
        raise ValueError(f"Design contains duplicate samples: {', '.join(duplicates)}")
    missing = [sample for sample in samples if sample not in set(design_samples)]
    if missing:
        raise ValueError(f"QC-included samples missing from design: {', '.join(missing)}")

    rows_by_sample = {row["sample"].strip(): row for row in rows}
    normalized = [rows_by_sample[sample] for sample in samples]
    for row in normalized:
        for field in reader.fieldnames:
            row[field] = row[field].strip()
            if not row[field]:
                raise ValueError(
                    f"Design contains an empty '{field}' value for sample {row['sample']}"
                )

    parsed_contrasts: list[tuple[str, str, str, str]] = []
    seen: set[str] = set()
    for value in args.contrast:
        parts = value.split(":")
        if len(parts) != 3 or not all(parts):
            raise ValueError(
                f"Invalid contrast '{value}'; expected FACTOR:NUMERATOR:DENOMINATOR"
            )
        factor, numerator, denominator = parts
        if factor not in reader.fieldnames:
            raise ValueError(f"Contrast factor is not a design column: {factor}")
        if numerator == denominator:
            raise ValueError(f"Contrast levels must differ: {value}")
        counts = Counter(row[factor] for row in normalized)
        for level in (numerator, denominator):
            if counts[level] < 2:
                raise ValueError(
                    f"Contrast '{value}' needs at least two QC-included samples "
                    f"at level '{level}' (found {counts[level]})"
                )
        contrast_id = safe_name(f"{factor}_{numerator}_vs_{denominator}")
        if not contrast_id:
            raise ValueError(f"Contrast cannot be converted to a safe identifier: {value}")
        if contrast_id in seen:
            raise ValueError(f"Contrast was supplied more than once: {value}")
        seen.add(contrast_id)
        parsed_contrasts.append((contrast_id, factor, numerator, denominator))

    args.output_design.parent.mkdir(parents=True, exist_ok=True)
    with args.output_design.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=reader.fieldnames, delimiter="\t", lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(normalized)
    with args.output_contrasts.open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["contrast_id", "factor", "numerator", "denominator"])
        writer.writerows(parsed_contrasts)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, csv.Error) as error:
        print(f"[design] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error
