"""Tests for the pure helper functions in windows/start-ollama.ps1."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "windows" / "start-ollama.ps1"
PWSH = shutil.which("pwsh")

pytestmark = pytest.mark.skipif(PWSH is None, reason="pwsh is not on PATH")

# Dot-sources only the function definitions, so the script body (ollama.exe lookup, server start) never runs.
LOAD_FUNCTIONS = f"""
$ErrorActionPreference = 'Stop'
$ast = [System.Management.Automation.Language.Parser]::ParseFile('{SCRIPT}', [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({{ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }}, $false)) {{
    . ([scriptblock]::Create($f.Extent.Text))
}}
"""


def run_pwsh(command: str) -> str:
    """Run a pwsh command after loading the script's functions and return its stdout.

    Args:
        command: PowerShell code to run once the functions are defined.

    Returns:
        The command's standard output.
    """
    assert PWSH is not None
    result = subprocess.run(
        [PWSH, "-NoProfile", "-NonInteractive", "-Command", LOAD_FUNCTIONS + command],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def modelfile_lines(num_gpu: int) -> list[str]:
    """Return the non-empty lines Get-ModelfileText emits for a 128k context."""
    out = run_pwsh(f"Get-ModelfileText -BaseModel 'qwen3.8:27b' -ContextTokens 131072 -NumGpu {num_gpu}")
    return [line for line in out.splitlines() if line.strip()]


def placement_report(size: int, size_vram: int) -> list[str]:
    """Return the lines Get-PlacementReport emits for the given sizes in bytes."""
    out = run_pwsh(f"Get-PlacementReport -Size {size} -SizeVram {size_vram} | ConvertTo-Json -AsArray")
    lines = json.loads(out)
    assert isinstance(lines, list)
    return [str(line) for line in lines]


@pytest.mark.parametrize("num_gpu", [99, 0])
def test_modelfile_includes_num_gpu(num_gpu: int) -> None:
    """Any NumGpu other than -1 adds a num_gpu parameter after FROM and num_ctx."""
    assert modelfile_lines(num_gpu) == [
        "FROM qwen3.8:27b",
        "PARAMETER num_ctx 131072",
        f"PARAMETER num_gpu {num_gpu}",
    ]


def test_modelfile_omits_num_gpu_for_minus_one() -> None:
    """NumGpu -1 leaves placement to Ollama and writes no num_gpu line."""
    lines = modelfile_lines(-1)
    assert lines == ["FROM qwen3.8:27b", "PARAMETER num_ctx 131072"]
    assert not any("num_gpu" in line for line in lines)


def test_placement_report_full_gpu_has_no_warning() -> None:
    """A model fully in VRAM reports 100% and adds no warning line."""
    size = 18 * 1024**3
    lines = placement_report(size, size)
    assert lines == ["GPU placement: 100% of the model in VRAM (18.0 GiB of 18.0 GiB)."]


def test_placement_report_partial_gpu_warns() -> None:
    """A model 78% in VRAM reports 78% and warns with the -NumGpu and -ContextK knobs."""
    size = 25 * 1024**3  # divisible by 100, so 78% is exact
    lines = placement_report(size, size * 78 // 100)
    assert len(lines) == 2
    assert lines[0] == "GPU placement: 78% of the model in VRAM (19.5 GiB of 25.0 GiB)."
    assert "78%" in lines[1]
    assert "-NumGpu" in lines[1]
    assert "-ContextK" in lines[1]
