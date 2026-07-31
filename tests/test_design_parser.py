#!/usr/bin/env python3

"""Regression tests for design-defined experiment subsets."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PARSER = ROOT / "lib" / "design_parser.py"


class DesignParserTests(unittest.TestCase):
    def run_parser(self, design_text: str) -> tuple[subprocess.CompletedProcess[str], Path]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        work = Path(temporary.name)
        (work / "samples.txt").write_text("S1\nS2\nS3\nS4\n")
        (work / "design.tsv").write_text(design_text)
        result = subprocess.run(
            [
                "python3",
                str(PARSER),
                "--design",
                str(work / "design.tsv"),
                "--samples-file",
                str(work / "samples.txt"),
                "--output-design",
                str(work / "normalized.tsv"),
                "--output-contrasts",
                str(work / "contrasts.tsv"),
                "--output-samples",
                str(work / "analysis_samples.txt"),
                "--contrast",
                "condition:treated:control",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        return result, work

    def test_sample_id_subset_is_normalized(self) -> None:
        result, work = self.run_parser(
            "sample_id\tcondition\n"
            "S1\tcontrol\n"
            "S2\tcontrol\n"
            "S3\ttreated\n"
            "S4\ttreated\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (work / "normalized.tsv").read_text().splitlines()[0],
            "sample\tcondition",
        )
        self.assertEqual(
            (work / "analysis_samples.txt").read_text(),
            "S1\nS2\nS3\nS4\n",
        )

    def test_omitted_experiment_samples_are_allowed(self) -> None:
        result, work = self.run_parser(
            "sample\tcondition\n"
            "S1\tcontrol\n"
            "S2\tcontrol\n"
            "S3\ttreated\n"
            "S4\ttreated\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        (work / "samples.txt").write_text("S1\nS2\nS3\nS4\nS5\n")
        result = subprocess.run(
            [
                "python3",
                str(PARSER),
                "--design",
                str(work / "design.tsv"),
                "--samples-file",
                str(work / "samples.txt"),
                "--output-design",
                str(work / "normalized-subset.tsv"),
                "--output-contrasts",
                str(work / "contrasts-subset.tsv"),
                "--contrast",
                "condition:treated:control",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unknown_design_sample_is_rejected(self) -> None:
        result, _ = self.run_parser(
            "sample\tcondition\n"
            "S1\tcontrol\n"
            "S2\tcontrol\n"
            "S3\ttreated\n"
            "UNKNOWN\ttreated\n"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("absent from QC-included", result.stderr)


if __name__ == "__main__":
    unittest.main()
