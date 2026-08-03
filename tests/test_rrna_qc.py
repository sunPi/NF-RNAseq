#!/usr/bin/env python3

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "modules" / "qc" / "qc_validator.py"
SPEC = importlib.util.spec_from_file_location("qc_validator", MODULE_PATH)
QC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(QC)


class RrnaMetricsTest(unittest.TestCase):
    def test_reads_single_metrics_row(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.tsv"
            path.write_text(
                "sample\tinput_fragments\tretained_fragments\trrna_fragments\trrna_percent\n"
                "S1\t100\t88\t12\t12.000000\n",
                encoding="utf-8",
            )
            self.assertEqual(QC.read_rrna(path), {"rrna_rate": 12.0})

    def test_rejects_multiple_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.tsv"
            path.write_text("rrna_percent\n1\n2\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                QC.read_rrna(path)


if __name__ == "__main__":
    unittest.main()
