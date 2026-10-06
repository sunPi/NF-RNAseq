"""Validation and command construction for the NF-RNAseq desktop launcher."""

from dataclasses import dataclass
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parent.parent
PROJECT_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


@dataclass(frozen=True)
class Module:
    name: str
    requires_design: bool
    requires_contrast: bool


def available_modules(root: Path = ROOT) -> list[Module]:
    modules = []
    for config in sorted((root / "modules").glob("*/module.config")):
        content = config.read_text()
        def flag(key: str) -> bool:
            match = re.search(rf"^{key}=(true|false)$", content, re.MULTILINE)
            return bool(match and match.group(1) == "true")
        modules.append(Module(config.parent.name, flag("MODULE_REQUIRES_DESIGN"),
                              flag("MODULE_REQUIRES_CONTRASTS")))
    return modules


def build_command(*, root: Path = ROOT, project: str, assembly: str,
                  layout: str, mode: str, input_dir: str = "",
                  modules: tuple[str, ...] = (), design: str = "",
                  contrasts: tuple[str, ...] = ()) -> list[str]:
    if not PROJECT_PATTERN.fullmatch(project) or project in {".", ".."}:
        raise ValueError("Enter one project folder name using letters, numbers, dots, underscores, or hyphens.")
    if assembly not in {"GRCh38", "GRCh37", "hg38", "hg19"}:
        raise ValueError("Choose a supported reference assembly.")
    if layout not in {"single", "paired"}:
        raise ValueError("Choose single or paired read layout.")
    if mode not in {"core", "optional", "modules"}:
        raise ValueError("Choose a pipeline mode.")
    if mode == "modules" and not (root / "results" / project).is_dir():
        raise ValueError(f"Core results do not exist for project {project}.")
    if mode != "modules" and not Path(input_dir).is_dir():
        raise ValueError("Select an existing FASTQ input folder.")
    if mode == "core" and modules:
        raise ValueError("Choose a module run mode to select modules.")
    known = {module.name: module for module in available_modules(root)}
    if mode != "core" and not modules:
        raise ValueError("Select at least one optional module.")
    if len(set(modules)) != len(modules) or any(name not in known for name in modules):
        raise ValueError("Module selection contains an unknown or repeated module.")
    if design and not Path(design).is_file():
        raise ValueError("Select an existing design TSV or CSV file.")
    if contrasts and not design:
        raise ValueError("Contrasts require a design file.")
    for contrast in contrasts:
        if len(contrast.split(":")) != 3 or not all(contrast.split(":")):
            raise ValueError("Each contrast must be FACTOR:NUMERATOR:DENOMINATOR.")
    for name in modules:
        module = known[name]
        if module.requires_design and not design:
            raise ValueError(f"Module {name} requires a design file.")
        if module.requires_contrast and not contrasts:
            raise ValueError(f"Module {name} requires at least one contrast.")

    command = [str(root / "main.sh"), "--assembly", assembly, "--layout", layout,
               "--project", project, "--pipeline", mode]
    if mode != "modules":
        command += ["--input", str(Path(input_dir).resolve())]
    if mode != "core":
        command += ["--modules", ",".join(modules)]
    if design:
        command += ["--design", str(Path(design).resolve())]
    for contrast in contrasts:
        command += ["--contrast", contrast]
    return command
