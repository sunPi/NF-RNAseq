"""Early CLI checks for explicit project selection."""

from pathlib import Path
import subprocess
import unittest


MAIN = Path(__file__).resolve().parents[1] / "main.sh"
BASE = ["bash", str(MAIN), "--assembly", "GRCh38", "--layout", "paired"]


class ProjectCliTests(unittest.TestCase):
    def run_main(self, *arguments):
        return subprocess.run(
            [*BASE, *arguments], capture_output=True, text=True, check=False
        )

    def test_project_switch_is_documented(self):
        result = subprocess.run(
            ["bash", str(MAIN), "--help"], capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("--project NAME", result.stdout)

    def test_project_and_experiment_cannot_be_combined(self):
        result = self.run_main("--project", "UVM_KOKI", "--experiment", "other")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("either --project or --experiment", result.stderr)

    def test_project_cannot_be_a_path(self):
        result = self.run_main("--project", "../UVM_TGFB")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid project name", result.stderr)

    def test_project_is_required(self):
        result = self.run_main()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Use --project NAME", result.stderr)


if __name__ == "__main__":
    unittest.main()
