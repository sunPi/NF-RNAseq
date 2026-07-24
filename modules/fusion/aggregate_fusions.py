#!/usr/bin/env python3

"""Create experiment-level fusion transcript evidence matrices."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


METRICS = ("JunctionReadCount", "SpanningFragCount", "FFPM")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Aggregate FusionInspector abridged tables. The manifest must be "
            "tab-delimited with columns: sample and fusion_inspector."
        )
    )
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    return parser.parse_args()


def fusion_id(row: dict[str, str]) -> str:
    name = row.get("#FusionName") or row.get("FusionName")
    left = row.get("LeftBreakpoint")
    right = row.get("RightBreakpoint")
    if not name or not left or not right:
        raise ValueError(
            "FusionInspector table lacks FusionName, LeftBreakpoint, or "
            "RightBreakpoint"
        )
    return f"{name}|{left}|{right}"


def read_manifest(path: Path) -> list[tuple[str, Path]]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if not reader.fieldnames or not {"sample", "fusion_inspector"} <= set(
            reader.fieldnames
        ):
            raise ValueError(
                "Manifest must contain sample and fusion_inspector columns"
            )
        records = [(row["sample"], Path(row["fusion_inspector"])) for row in reader]

    if not records:
        raise ValueError("Manifest contains no samples")
    samples = [sample for sample, _ in records]
    if len(samples) != len(set(samples)):
        raise ValueError("Manifest contains duplicate sample names")
    return records


def main() -> None:
    args = parse_arguments()
    records = read_manifest(args.manifest)
    sample_names = [sample for sample, _ in records]
    values: dict[str, dict[str, dict[str, float]]] = {
        metric: {} for metric in (*METRICS, "TotalSupportingFragments")
    }

    for sample, table_path in records:
        if not table_path.is_file():
            raise FileNotFoundError(f"FusionInspector table not found: {table_path}")
        with table_path.open(newline="") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            for row in reader:
                event = fusion_id(row)
                junction = float(row["JunctionReadCount"])
                spanning = float(row["SpanningFragCount"])
                metric_values = {
                    "JunctionReadCount": junction,
                    "SpanningFragCount": spanning,
                    "FFPM": float(row["FFPM"]),
                    "TotalSupportingFragments": junction + spanning,
                }
                for metric, value in metric_values.items():
                    values[metric].setdefault(event, {})[sample] = value

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for metric, events in values.items():
        output_path = args.output_dir / f"fusion_transcripts.{metric}.tsv"
        with output_path.open("w", newline="") as handle:
            writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
            writer.writerow(["fusion_transcript_id", *sample_names])
            for event in sorted(events):
                writer.writerow(
                    [event, *(events[event].get(sample, 0) for sample in sample_names)]
                )


if __name__ == "__main__":
    main()
