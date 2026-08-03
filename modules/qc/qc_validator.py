#!/usr/bin/env python3

import argparse
import csv
import json
import os
import sys


def parse_args():
    parser = argparse.ArgumentParser(
        description="Classify bulk RNA-seq samples using fastp, STAR, and RSEM metrics."
    )
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--output-dir", required=True)
    return parser.parse_args()


def read_config(path):
    config = {}
    with open(path, encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                raise ValueError("Invalid QC configuration line: {}".format(raw_line.rstrip()))
            key, value = line.split("=", 1)
            config[key.strip()] = value.strip().strip("\"'")
    return config


def number(config, key):
    try:
        return float(config[key])
    except KeyError:
        raise ValueError("Missing QC threshold: {}".format(key))
    except ValueError:
        raise ValueError("QC threshold is not numeric: {}={}".format(key, config[key]))


def classify_min(value, pass_threshold, warning_threshold):
    if value >= pass_threshold:
        return "PASS"
    if value >= warning_threshold:
        return "WARNING"
    return "FAIL"


def classify_max(value, pass_threshold, warning_threshold):
    if value <= pass_threshold:
        return "PASS"
    if value <= warning_threshold:
        return "WARNING"
    return "FAIL"


def read_fastp(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)

    before = data["summary"]["before_filtering"]
    after = data["summary"]["after_filtering"]
    total_reads = float(before["total_reads"])
    retained_reads = float(after["total_reads"])
    retention = retained_reads / total_reads * 100 if total_reads else 0.0
    q30 = float(after["q30_rate"]) * 100

    adapter_reads = float(data.get("adapter_cutting", {}).get("adapter_trimmed_reads", 0))
    adapter_rate = adapter_reads / total_reads * 100 if total_reads else 0.0

    n_curves = []
    for read_key in ("read1_before_filtering", "read2_before_filtering"):
        read_data = data.get(read_key)
        if read_data:
            n_curves.extend(read_data.get("content_curves", {}).get("N", []))
    n_rate = sum(n_curves) / len(n_curves) * 100 if n_curves else 0.0

    return {
        "total_reads": total_reads,
        "q30_after_trimming": q30,
        "trim_retention": retention,
        "adapter_contamination": adapter_rate,
        "n_bases": n_rate,
    }


def read_star(path):
    values = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if "|" not in line:
                continue
            key, value = (part.strip() for part in line.split("|", 1))
            values[key] = value

    def percentage(key):
        return float(values.get(key, "0").rstrip("%"))

    unmapped = (
        percentage("% of reads unmapped: too many mismatches")
        + percentage("% of reads unmapped: too short")
        + percentage("% of reads unmapped: other")
    )

    return {
        "unique_mapping": percentage("Uniquely mapped reads %"),
        "multi_mapping": percentage("% of reads mapped to multiple loci"),
        "unmapped": unmapped,
        "mismatch_rate": percentage("Mismatch rate per base, %"),
        "chimeric_rate": percentage("% of chimeric reads"),
    }


def read_rsem(path):
    genes_tpm = 0
    genes_count = 0
    total_expected_counts = 0.0

    with open(path, encoding="utf-8") as handle:
        header = next(handle).rstrip("\n").split("\t")
        count_index = header.index("expected_count")
        tpm_index = header.index("TPM")

        for line in handle:
            fields = line.rstrip("\n").split("\t")
            expected_count = float(fields[count_index])
            tpm = float(fields[tpm_index])
            total_expected_counts += expected_count
            if tpm > 1:
                genes_tpm += 1
            if expected_count > 10:
                genes_count += 1

    return {
        "genes_tpm_gt_1": float(genes_tpm),
        "genes_count_gt_10": float(genes_count),
        "total_expected_counts": total_expected_counts,
    }


def read_rrna(path):
    with open(path, encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    if len(rows) != 1:
        raise ValueError("Expected one rRNA metrics row in: {}".format(path))
    return {"rrna_rate": float(rows[0]["rrna_percent"])}


def metric_definitions(config):
    return {
        "total_reads": ("Sequencing", "min", number(config, "MIN_TOTAL_READS_PASS"), number(config, "MIN_TOTAL_READS_WARNING"), "reads"),
        "q30_after_trimming": ("Sequencing", "min", number(config, "MIN_Q30_PASS"), number(config, "MIN_Q30_WARNING"), "%"),
        "trim_retention": ("Sequencing", "min", number(config, "MIN_TRIM_RETENTION_PASS"), number(config, "MIN_TRIM_RETENTION_WARNING"), "%"),
        "adapter_contamination": ("Sequencing", "max", number(config, "MAX_ADAPTER_CONTAMINATION_PASS"), number(config, "MAX_ADAPTER_CONTAMINATION_WARNING"), "%"),
        "n_bases": ("Sequencing", "max", number(config, "MAX_N_BASES_PASS"), number(config, "MAX_N_BASES_WARNING"), "%"),
        "rrna_rate": ("Contamination", "max", number(config, "MAX_RRNA_RATE_PASS"), number(config, "MAX_RRNA_RATE_WARNING"), "%"),
        "unique_mapping": ("Alignment", "min", number(config, "MIN_UNIQUE_MAPPING_PASS"), number(config, "MIN_UNIQUE_MAPPING_WARNING"), "%"),
        "multi_mapping": ("Alignment", "max", number(config, "MAX_MULTI_MAPPING_PASS"), number(config, "MAX_MULTI_MAPPING_WARNING"), "%"),
        "unmapped": ("Alignment", "max", number(config, "MAX_UNMAPPED_PASS"), number(config, "MAX_UNMAPPED_WARNING"), "%"),
        "mismatch_rate": ("Alignment", "max", number(config, "MAX_MISMATCH_RATE_PASS"), number(config, "MAX_MISMATCH_RATE_WARNING"), "%"),
        "chimeric_rate": ("Alignment", "max", number(config, "MAX_CHIMERIC_RATE_PASS"), number(config, "MAX_CHIMERIC_RATE_WARNING"), "%"),
        "genes_tpm_gt_1": ("Expression", "min", number(config, "MIN_GENES_TPM_PASS"), number(config, "MIN_GENES_TPM_WARNING"), "genes"),
        "genes_count_gt_10": ("Expression", "min", number(config, "MIN_GENES_COUNT_PASS"), number(config, "MIN_GENES_COUNT_WARNING"), "genes"),
        "total_expected_counts": ("Expression", "min", number(config, "MIN_EXPECTED_COUNTS_PASS"), number(config, "MIN_EXPECTED_COUNTS_WARNING"), "counts"),
    }


def format_value(value, unit):
    if unit in ("reads", "genes", "counts"):
        return "{:,.0f}".format(value)
    return "{:.2f}{}".format(value, unit)


def main():
    args = parse_args()
    config = read_config(args.config)
    definitions = metric_definitions(config)
    immediate_fail = set(
        item.strip()
        for item in config.get("IMMEDIATE_FAIL_METRICS", "").split(",")
        if item.strip()
    )
    warning_limit = int(number(config, "MAX_WARNINGS_FOR_PASS"))
    fail_limit = int(number(config, "FAIL_METRICS_FOR_OVERALL_FAIL"))

    os.makedirs(args.output_dir, exist_ok=True)
    summary_path = os.path.join(args.output_dir, "sample_qc_status.csv")
    metrics_path = os.path.join(args.output_dir, "sample_qc_metrics.csv")
    included_path = os.path.join(args.output_dir, "qc_included_samples.txt")

    with open(args.manifest, encoding="utf-8") as manifest_handle:
        manifest = list(csv.DictReader(manifest_handle, delimiter="\t"))

    summary_rows = []
    metric_rows = []
    included_samples = []

    for row in manifest:
        sample = row["sample"]
        metrics = {}
        metrics.update(read_fastp(row["fastp_json"]))
        metrics.update(read_star(row["star_log"]))
        metrics.update(read_rsem(row["rsem_genes"]))
        if row.get("rrna_metrics"):
            metrics.update(read_rrna(row["rrna_metrics"]))

        statuses = {}
        for metric, value in metrics.items():
            category, direction, pass_threshold, warning_threshold, unit = definitions[metric]
            if direction == "min":
                status = classify_min(value, pass_threshold, warning_threshold)
            else:
                status = classify_max(value, pass_threshold, warning_threshold)
            statuses[metric] = status
            metric_rows.append({
                "sample": sample,
                "category": category,
                "metric": metric,
                "value": "{:.6f}".format(value),
                "unit": unit,
                "status": status,
                "pass_threshold": "{:.6f}".format(pass_threshold),
                "warning_threshold": "{:.6f}".format(warning_threshold),
            })

        failures = [metric for metric, status in statuses.items() if status == "FAIL"]
        warnings = [metric for metric, status in statuses.items() if status == "WARNING"]
        immediate = [metric for metric in failures if metric in immediate_fail]

        if immediate or len(failures) >= fail_limit:
            overall = "FAIL"
        elif failures or len(warnings) > warning_limit:
            overall = "WARNING"
        else:
            overall = "PASS"

        flagged = failures + warnings
        reasons = [
            "{} {} ({})".format(
                metric,
                statuses[metric],
                format_value(metrics[metric], definitions[metric][4]),
            )
            for metric in flagged
        ]
        reason = "; ".join(reasons)
        summary_rows.append({
            "sample": sample,
            "status": overall,
            "fail_metrics": len(failures),
            "warning_metrics": len(warnings),
            "reason": reason,
        })

        if overall != "FAIL":
            included_samples.append(sample)

        report_path = os.path.join(args.output_dir, "{}.qc_report.txt".format(sample))
        with open(report_path, "w", encoding="utf-8") as report:
            report.write("Sample: {}\n\n".format(sample))
            for category in ("Sequencing", "Contamination", "Alignment", "Expression"):
                report.write("{}\n{}\n".format(category, "-" * 25))
                for metric, definition in definitions.items():
                    if definition[0] != category:
                        continue
                    report.write(
                        "{:<28} {:<8} {}\n".format(
                            metric,
                            statuses[metric],
                            format_value(metrics[metric], definition[4]),
                        )
                    )
                report.write("\n")
            report.write("Overall\n{}\nSTATUS: {}\n".format("-" * 25, overall))
            if reasons:
                report.write("Reason:\n")
                for item in reasons:
                    report.write("- {}\n".format(item))

    with open(summary_path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=("sample", "status", "fail_metrics", "warning_metrics", "reason"),
        )
        writer.writeheader()
        writer.writerows(summary_rows)

    with open(metrics_path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=(
                "sample", "category", "metric", "value", "unit", "status",
                "pass_threshold", "warning_threshold",
            ),
        )
        writer.writeheader()
        writer.writerows(metric_rows)

    with open(included_path, "w", encoding="utf-8") as handle:
        for sample in included_samples:
            handle.write(sample + "\n")

    print("QC summary: {}".format(summary_path))
    print("QC metrics: {}".format(metrics_path))
    print("Samples retained: {} of {}".format(len(included_samples), len(manifest)))
    return 0 if included_samples else 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyError, ValueError, OSError, json.JSONDecodeError) as error:
        print("ERROR: {}".format(error), file=sys.stderr)
        sys.exit(1)
