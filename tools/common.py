"""Local/CI process helpers. No network, dependencies, or credential access."""
from pathlib import Path
from datetime import datetime, timezone
import os
import platform
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build_environment(target):
    env = dict(os.environ)
    if os.name != "nt" or target != "native" or shutil.which("cl", path=env.get("PATH")):
        return env
    installer = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"))
    vswhere = installer / "Microsoft Visual Studio/Installer/vswhere.exe"
    if not vswhere.is_file():
        raise SystemExit("native target requires MSVC (Visual Studio C++ build tools)")
    found = subprocess.run([str(vswhere), "-latest", "-products", "*", "-requires",
                            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                            "-property", "installationPath"], check=True, capture_output=True,
                           text=True).stdout.strip()
    if not found:
        raise SystemExit("MSVC x64 build tools were not found")
    script = Path(found) / "VC/Auxiliary/Build/vcvars64.bat"
    if not script.is_file() or any(c in str(script) for c in '"&|<>^%!'):
        raise SystemExit("Unexpected MSVC initialization path")
    # cmd uses its own quoting rules; list2cmdline's backslash escaping is not cmd quoting.
    command = f'cmd.exe /d /s /c ""{script}" >nul && set"'
    result = subprocess.run(command, capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    if result.returncode:
        raise SystemExit("MSVC initialization failed: " + result.stderr.strip())
    for line in result.stdout.splitlines():
        if "=" in line and not line.startswith("="):
            key, value = line.split("=", 1)
            # Windows environment names are case insensitive; avoid two PATH entries.
            for old in list(env):
                if old.lower() == key.lower():
                    del env[old]
            env[key] = value
    return env


def run(args, *, target="wasm-gc", cwd=ROOT, capture=False):
    return subprocess.run([str(x) for x in args], cwd=cwd, env=build_environment(target),
                          check=True, text=True, encoding="utf-8", errors="replace",
                          capture_output=capture)


def evidence_base(target, commands):
    """Non-secret reproduction context shared by machine reports."""
    module = (ROOT / 'moon.mod').read_text(encoding='utf-8')
    return dict(executed_at=datetime.now(timezone.utc).isoformat(),
                source_commit=run(['git', 'rev-parse', 'HEAD'], capture=True).stdout.strip(),
                source_tree=run(['git', 'rev-parse', 'HEAD^{tree}'], capture=True).stdout.strip(),
                source_dirty=bool(run(['git', 'status', '--porcelain'], capture=True).stdout.strip()),
                module=re.search(r'^name\s*=\s*"([^"]+)"', module, re.M)[1],
                version=re.search(r'^version\s*=\s*"([^"]+)"', module, re.M)[1],
                target=target, platform=platform.platform(), python=platform.python_version(),
                toolchain=run(['moon', 'version', '--all'], capture=True).stdout.strip(),
                node=run(['node', '--version'], capture=True).stdout.strip(), commands=commands)
