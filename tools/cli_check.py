"""Exercise the real Node file adapter, including Unicode paths and failed writes."""
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import tempfile

from common import ROOT, run


def main():
    run(['moon', 'build', '--target', 'js', '--deny-warn'], target='js')
    base = ROOT/'artifacts'
    base.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='CLI 中文 paths ', dir=base)).resolve()
    input_path = work/'输入 网格.json'
    input_path.write_bytes((ROOT/'examples/data/triangle.json').read_bytes())
    output_path = work/'细分 结果.json'
    checks = []

    def cli(arguments, success, label):
        result = subprocess.run(['node', str(ROOT/'tools/moonsurface.mjs'), *map(str, arguments)],
            cwd=work, capture_output=True, text=True, encoding='utf-8', errors='strict', timeout=30)
        assert result.returncode == (0 if success else 2), (label, result.stdout, result.stderr)
        checks.append(label)
        return result

    result = cli([input_path], True, 'unicode-and-space-input-from-other-working-directory')
    response = json.loads(result.stdout)
    assert response['ok'] and response['stats']['faces'] == 4
    cli([input_path, '--out', output_path], True, 'create-output')
    before = output_path.read_bytes()
    assert json.loads(before)['stats']['vertices'] == 6
    cli([input_path, '--out', output_path], False, 'preserve-existing-output')
    assert output_path.read_bytes() == before
    original_input = input_path.read_bytes()
    cli([input_path, '--out', input_path], False, 'preserve-input-if-output-is-input')
    assert input_path.read_bytes() == original_input
    missing_output = work/'should-not-exist.json'
    bad = work/'bad.json'
    bad.write_text('{', encoding='utf-8')
    result = cli([bad, '--out', missing_output], False, 'malformed-json-no-output')
    assert json.loads(result.stdout)['ok'] is False and not missing_output.exists()
    bad.write_bytes(b'\xff\xfe')
    cli([bad, '--out', missing_output], False, 'strict-utf8-no-output')
    assert not missing_output.exists()
    with bad.open('wb') as file:
        file.truncate(16*1024*1024+1)
    cli([bad], False, 'input-byte-budget')
    bad.write_text('['*17+'0'+']'*17, encoding='utf-8')
    result = cli([bad], False, 'json-nesting-budget')
    assert json.loads(result.stdout)['ok'] is False
    cli([work/'missing.json'], False, 'missing-input')
    cli([work], False, 'reject-directory')
    cli([], False, 'missing-arguments')
    cli([input_path, '--unknown', output_path], False, 'unknown-arguments')
    assert 'Usage:' in cli(['--help'], True, 'help').stdout
    report = dict(status='passed', timestamp_utc=datetime.now(timezone.utc).isoformat(),
                  source_commit=run(['git', 'rev-parse', 'HEAD'], capture=True).stdout.strip(),
                  checks=checks, count=len(checks))
    (base/'cli.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(f'Node CLI: {len(checks)} file/process checks passed')


if __name__ == '__main__':
    main()
