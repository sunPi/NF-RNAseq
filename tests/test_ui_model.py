from pathlib import Path
import tempfile
import unittest

from ui_model import build_command


class UiModelTests(unittest.TestCase):
    def test_separate_projects_build_separate_commands(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "modules").mkdir()
            fastq = root / "fastq"
            fastq.mkdir()
            first = build_command(root=root, project="UVM_KOKI", assembly="GRCh38",
                                  layout="paired", mode="core", input_dir=str(fastq))
            second = build_command(root=root, project="UVM_TGFB", assembly="GRCh38",
                                   layout="paired", mode="core", input_dir=str(fastq))
            self.assertEqual(first[first.index("--project") + 1], "UVM_KOKI")
            self.assertEqual(second[second.index("--project") + 1], "UVM_TGFB")

    def test_module_requirements(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module_dir = root / "modules" / "dge"
            module_dir.mkdir(parents=True)
            (module_dir / "module.config").write_text(
                "MODULE_REQUIRES_DESIGN=true\nMODULE_REQUIRES_CONTRASTS=true\n")
            (root / "results" / "UVM_KOKI").mkdir(parents=True)
            kwargs = dict(root=root, project="UVM_KOKI", assembly="GRCh38",
                          layout="paired", mode="modules", modules=("dge",))
            with self.assertRaisesRegex(ValueError, "design"):
                build_command(**kwargs)
            design = root / "design.tsv"
            design.write_text("sample\tcondition\n")
            with self.assertRaisesRegex(ValueError, "contrast"):
                build_command(**kwargs, design=str(design))
            command = build_command(**kwargs, design=str(design),
                                    contrasts=("condition:treated:control",))
            self.assertIn("--contrast", command)

    def test_modules_need_existing_project(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "modules").mkdir()
            with self.assertRaisesRegex(ValueError, "Core results"):
                build_command(root=root, project="UVM_KOKI", assembly="GRCh38",
                              layout="paired", mode="modules", modules=("dge",))


if __name__ == "__main__":
    unittest.main()
