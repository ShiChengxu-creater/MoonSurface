"""Compile the exact README workspace example from a clean Git snapshot."""
import json
from pathlib import Path
import re
import subprocess
import tempfile

from common import ROOT, evidence_base, run
from consumer import unpack


def main():
    assert not run(['git', 'status', '--porcelain'], capture=True).stdout.strip()
    blocks = re.findall(r'```(?:toml|moonbit)\n(.*?)\n```',
                        (ROOT/'README.md').read_text(encoding='utf-8'), re.S)
    assert len(blocks) == 4, 'Review README smoke extraction after changing its code blocks'
    base = ROOT/'artifacts'
    base.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='readme-', dir=base)).resolve()
    source = subprocess.run(['git', 'archive', '--format=zip', 'HEAD'], cwd=ROOT,
                            check=True, capture_output=True).stdout
    unpack(source, work/'MoonSurface')
    app = work/'app'
    app.mkdir()
    for name, text in zip(['moon.work', 'app/moon.mod', 'app/moon.pkg', 'app/main.mbt'], blocks):
        (work/name).write_text(text+'\n', encoding='utf-8')
    command = ['moon', 'run', 'app', '--target', 'js', '--deny-warn']
    result = run(command, cwd=work, target='js', capture=True)
    assert result.stdout.strip() == '16', result.stdout+result.stderr
    report = dict(evidence_base('js', [command]), status='passed', output=result.stdout.strip(),
                  scope='exact README fenced workspace files; clean Git archive')
    (base/'readme.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('README workspace example: compiled and returned 16 faces')


if __name__ == '__main__':
    main()
