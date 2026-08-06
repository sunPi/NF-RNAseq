#!/usr/bin/env python3

import csv
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]


class ModuleAggregationTest(unittest.TestCase):
    def test_telescope_matrix(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for sample, rows in {
                "S1": [("L1", "2"), ("L2", "3")],
                "S2": [("L2", "5")],
            }.items():
                target = root / sample / "modules" / "Telescope"
                target.mkdir(parents=True)
                with (target / f"{sample}-TE_counts.tsv").open("w", newline="") as handle:
                    writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
                    writer.writerow(["transcript", "count"])
                    writer.writerows(rows)
            output = root / "matrix"
            subprocess.run(
                ["python3", str(ROOT / "modules/telescope/aggregate_module.py"),
                 "--results-dir", str(root), "--output-dir", str(output),
                 "--sample", "S1", "--sample", "S2"], check=True
            )
            self.assertIn("L1\t2\t0", (output / "telescope_locus_counts.tsv").read_text())

    def test_trust4_matrix(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "S1" / "modules" / "TRUST4"
            target.mkdir(parents=True)
            (target / "S1_report.tsv").write_text(
                "#count\tfrequency\tCDR3nt\tCDR3aa\tV\tD\tJ\tC\tcid\tcid_full_length\n"
                "4\t0.5\tACGT\tT\tTRBV1\t.\tTRBJ1\tTRBC1\tc1\t1\n",
                encoding="utf-8",
            )
            (target / "S1_airr.tsv").write_text(
                "sequence_id\tproductive\tlocus\nseq1\tT\tTRB\n",
                encoding="utf-8",
            )
            output = root / "matrix"
            subprocess.run(
                ["python3", str(ROOT / "modules/trust4/aggregate_module.py"),
                 "--results-dir", str(root), "--output-dir", str(output),
                 "--sample", "S1"], check=True
            )
            matrix = (output / "trust4_clonotype_counts.tsv").read_text()
            self.assertIn("ACGT|TRBV1|.|TRBJ1|TRBC1\t4", matrix)
            self.assertTrue((output / "trust4_airr_rearrangements.tsv").is_file())
            self.assertTrue((output / "trust4_repertoire_summary.tsv").is_file())


if __name__ == "__main__":
    unittest.main()
