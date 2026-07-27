#!/usr/bin/env python3

"""Aggregate per-sample STAR-Fusion and Arriba calls into cohort matrices."""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path
from typing import Callable


STAR_METRICS = {
    "junction_reads": lambda row: float(row["JunctionReadCount"]),
    "spanning_fragments": lambda row: float(row["SpanningFragCount"]),
    "total_support": lambda row: float(row["JunctionReadCount"])
    + float(row["SpanningFragCount"]),
    "FFPM": lambda row: float(row["FFPM"]),
    "presence": lambda row: 1.0,
}

ARRIBA_METRICS = {
    "split_reads": lambda row: float(row["split_reads1"])
    + float(row["split_reads2"]),
    "discordant_mates": lambda row: float(row["discordant_mates"]),
    "total_support": lambda row: float(row["split_reads1"])
    + float(row["split_reads2"])
    + float(row["discordant_mates"]),
    "presence": lambda row: 1.0,
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Aggregate STAR-Fusion and Arriba results into experiment-level "
            "fusion matrices."
        )
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


def clean_header(fieldnames: list[str] | None) -> list[str]:
    if not fieldnames:
        raise ValueError("Fusion table has no header")
    return [name.lstrip("#") for name in fieldnames]


def read_table(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(f"Required fusion result is missing: {path}")
    if path.stat().st_size == 0:
        raise ValueError(f"Fusion result is empty: {path}")

    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        original_names = reader.fieldnames
        normalized_names = clean_header(original_names)
        if original_names != normalized_names:
            reader.fieldnames = normalized_names
        return list(reader)


def star_event_id(row: dict[str, str]) -> str:
    return "|".join(
        (row["FusionName"], row["LeftBreakpoint"], row["RightBreakpoint"])
    )


def arriba_event_id(row: dict[str, str]) -> str:
    pair = f"{row['gene1']}--{row['gene2']}"
    return "|".join((pair, row["breakpoint1"], row["breakpoint2"]))


def gene_pair(event_id: str) -> str:
    return event_id.split("|", 1)[0]


def collect_metrics(
    rows_by_sample: dict[str, list[dict[str, str]]],
    metric_functions: dict[str, Callable[[dict[str, str]], float]],
    identifier: Callable[[dict[str, str]], str],
) -> dict[str, dict[str, dict[str, float]]]:
    matrices: dict[str, dict[str, dict[str, float]]] = {
        metric: defaultdict(dict) for metric in metric_functions
    }
    for sample, rows in rows_by_sample.items():
        for row in rows:
            event = identifier(row)
            for metric, calculation in metric_functions.items():
                value = calculation(row)
                previous = matrices[metric][event].get(sample)
                matrices[metric][event][sample] = (
                    value if previous is None else max(previous, value)
                )
    return matrices


def format_value(value: float) -> str:
    return str(int(value)) if value.is_integer() else f"{value:.6g}"


def write_matrix(
    path: Path,
    samples: list[str],
    events: dict[str, dict[str, float]],
    identifier_label: str = "fusion_event",
) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow([identifier_label, *samples])
        for event in sorted(events):
            writer.writerow(
                [
                    event,
                    *[
                        format_value(events[event].get(sample, 0.0))
                        for sample in samples
                    ],
                ]
            )


def write_catalog(
    path: Path,
    star_rows: dict[str, list[dict[str, str]]],
    arriba_rows: dict[str, list[dict[str, str]]],
) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(
            [
                "caller",
                "fusion_event",
                "gene_pair",
                "sample",
                "confidence",
                "reading_frame",
                "annotations",
            ]
        )
        for sample, rows in star_rows.items():
            for row in rows:
                event = star_event_id(row)
                writer.writerow(
                    [
                        "STAR-Fusion",
                        event,
                        gene_pair(event),
                        sample,
                        "",
                        "",
                        row.get("annots", ""),
                    ]
                )
        for sample, rows in arriba_rows.items():
            for row in rows:
                event = arriba_event_id(row)
                writer.writerow(
                    [
                        "Arriba",
                        event,
                        gene_pair(event),
                        sample,
                        row.get("confidence", ""),
                        row.get("reading_frame", ""),
                        row.get("tags", ""),
                    ]
                )


def main() -> None:
    args = parse_arguments()
    if args.samples_file:
        with args.samples_file.open() as handle:
            samples = [line.strip() for line in handle if line.strip()]
    else:
        samples = args.samples

    if not samples:
        raise ValueError("No samples were supplied")
    if len(samples) != len(set(samples)):
        raise ValueError("A sample was supplied more than once")

    star_rows: dict[str, list[dict[str, str]]] = {}
    arriba_rows: dict[str, list[dict[str, str]]] = {}
    for sample in samples:
        sample_root = args.results_dir / sample / "modules" / "fusion"
        star_rows[sample] = read_table(
            sample_root / "star-fusion" / "star-fusion.fusion_predictions.tsv"
        )
        arriba_rows[sample] = read_table(sample_root / "arriba" / "fusions.tsv")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    star_matrices = collect_metrics(star_rows, STAR_METRICS, star_event_id)
    arriba_matrices = collect_metrics(arriba_rows, ARRIBA_METRICS, arriba_event_id)

    for metric, events in star_matrices.items():
        write_matrix(
            args.output_dir / f"star_fusion.{metric}.tsv",
            samples,
            events,
        )
    for metric, events in arriba_matrices.items():
        write_matrix(
            args.output_dir / f"arriba.{metric}.tsv",
            samples,
            events,
        )

    caller_support: dict[str, dict[str, float]] = defaultdict(dict)
    for sample in samples:
        star_pairs = {gene_pair(star_event_id(row)) for row in star_rows[sample]}
        arriba_pairs = {gene_pair(arriba_event_id(row)) for row in arriba_rows[sample]}
        for pair in star_pairs | arriba_pairs:
            caller_support[pair][sample] = float(
                int(pair in star_pairs) + int(pair in arriba_pairs)
            )

    write_matrix(
        args.output_dir / "fusion_gene_pair.caller_support.tsv",
        samples,
        caller_support,
        identifier_label="fusion_gene_pair",
    )
    write_catalog(
        args.output_dir / "fusion_event_catalog.tsv",
        star_rows,
        arriba_rows,
    )


if __name__ == "__main__":
    main()
