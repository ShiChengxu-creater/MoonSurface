"""Verify an exact published module in a fresh project without workspace overrides.

This is an opt-in network check, separate from offline source/ZIP verification.
It never publishes, reads credentials, or replaces a dependency with local source.
"""
import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
import platform
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.request

from common import ROOT, build_environment
from consumer import TESTS


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--source-ref', help='Optional Git revision to compare published production .mbt files')
    parser.add_argument('--expected-sha256', help='Optional checksum of the previously verified published ZIP')
    parser.add_argument('--readme', action='store_true', help='Also execute the exact README app files from the registry')
    parser.add_argument('--target', choices=['native', 'js', 'wasm-gc'], action='append')
    parser.add_argument('--output', type=Path, help='Parent for fresh consumer and evidence (defaults to artifacts)')
    args = parser.parse_args()
    assert re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', args.version), 'Unexpected version'
    base = (args.output or ROOT/'artifacts').resolve()
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='registry-consumer-', dir=base)).resolve()
    for directory in [work, *work.parents]:
        assert not (directory/'moon.work').exists(), f'Workspace override found: {directory}'
    assert not (work/'.mooncakes').exists()
    (work/'moon.mod').write_text('name = "local/moonsurface_registry_consumer"\n'
        'version = "0.0.0"\npreferred_target = "wasm-gc"\n', encoding='utf-8')
    (work/'moon.pkg').write_text('import {\n "ShiChengxu/moonsurface" @surface,\n'
        ' "ShiChengxu/moonsurface/exchange" @job,\n "moonbitlang/core/json",\n} for "test"\n', encoding='utf-8')
    (work/'consumer_test.mbt').write_text(TESTS, encoding='utf-8')
    commands = []
    proxies = urllib.request.getproxies()

    def run(command, target='wasm-gc', directory=work):
        env = build_environment(target)
        # Match the existing system proxy without printing or persisting its URL.
        for scheme in ('http', 'https'):
            if scheme in proxies and not env.get(scheme+'_proxy') and not env.get(scheme.upper()+'_PROXY'):
                env[scheme.upper()+'_PROXY'] = proxies[scheme]
        if proxies.get('https') and 'GIT_CONFIG_COUNT' not in env:
            env.update(GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='http.proxy',
                       GIT_CONFIG_VALUE_0=proxies['https'])
        result = subprocess.run(command, cwd=directory, env=env, capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=240)
        commands.append(dict(command=command, directory=str(directory.relative_to(work)),
                             exit_code=result.returncode))
        if result.returncode:
            raise RuntimeError(f'Command failed: {command!r}\n{result.stdout}\n{result.stderr}')
        return result.stdout

    module = 'ShiChengxu/moonsurface'
    metadata = json.loads(run(['moon', 'view', module+'@'+args.version, '--json']))
    assert metadata['status'] == 'success'
    release = metadata['result']
    assert release['module'] == module and release['version'] == args.version
    assert not release['yanked'], 'Requested release was deprecated'
    archive_checksum = release['metadata']['checksum']
    if args.expected_sha256:
        assert archive_checksum == args.expected_sha256, 'Registry archive checksum differs'
    (work/'registry-metadata.json').write_text(json.dumps(metadata, indent=2)+'\n', encoding='utf-8')
    run(['moon', 'add', module+'@'+args.version])
    tree_text = run(['moon', 'tree', '--json'])
    (work/'dependency-tree.json').write_text(tree_text, encoding='utf-8')

    def verify_tree(tree):
        assert tree['status'] == 'success', tree
        candidates = [item for item in tree['modules'] if item['name'] == module]
        assert len(candidates) == 1
        item = candidates[0]
        assert item['version'] == args.version and item['source']['kind'] == 'registry', item
        assert not item['workspace_member'], item

    verify_tree(json.loads(tree_text))
    manifests = list((work/'.mooncakes').rglob('moon.mod'))
    resolved = []
    for manifest in manifests:
        text = manifest.read_text(encoding='utf-8')
        if re.search(r'^name\s*=\s*"'+re.escape(module)+'"', text, re.M):
            assert re.search(r'^version\s*=\s*"'+re.escape(args.version)+'"', text, re.M), text
            assert not manifest.parent.is_symlink()
            resolved.append(manifest.parent.resolve())
    assert len(resolved) == 1, f'Expected exact registry dependency, found {resolved}'
    dependency = resolved[0]
    assert dependency.is_relative_to(work/'.mooncakes')
    assert 'path:' not in (work/'moon.mod').read_text(encoding='utf-8')
    expected_ref = None
    production_hashes = []
    if args.source_ref:
        expected_ref = subprocess.run(['git', 'rev-parse', '--verify', args.source_ref+'^{commit}'],
            cwd=ROOT, check=True, capture_output=True, text=True, encoding='utf-8').stdout.strip()
        files = subprocess.run(['git', 'ls-tree', '-r', '--name-only', expected_ref],
            cwd=ROOT, check=True, capture_output=True, text=True, encoding='utf-8').stdout.splitlines()
        for name in files:
            if name.endswith('.mbt') and not name.endswith(('_test.mbt', '_wbtest.mbt')):
                original = subprocess.run(['git', 'show', expected_ref+':'+name], cwd=ROOT,
                    check=True, capture_output=True).stdout.replace(b'\r\n', b'\n')
                published = (dependency/name).read_bytes().replace(b'\r\n', b'\n')
                assert original == published, f'Published source differs: {name}'
                production_hashes.append(dict(file=name, sha256_lf=sha256(published).hexdigest()))
    results = []
    for target in args.target or ['js', 'wasm-gc', 'native']:
        for verb in ['check', 'build']:
            run(['moon', verb, '--target', target, '--deny-warn'], target)
        output = run(['moon', 'test', '--target', target, '--deny-warn'], target)
        assert 'Total tests: 4, passed: 4, failed: 0' in output, output
        results.append(dict(target=target, tests=4, passed=4))
        print(f'Registry consumer {target}: 4/4 passed ({module}@{args.version})', flush=True)
    readme_result = None
    if args.readme:
        blocks = re.findall(r'```(?:toml|moonbit)\n(.*?)\n```',
                            (ROOT/'README.md').read_text(encoding='utf-8'), re.S)
        assert len(blocks) == 4 and module+'@'+args.version in blocks[1]
        app = work/'readme-consumer'
        app.mkdir()
        for name, text in zip(['moon.mod', 'moon.pkg', 'main.mbt'], blocks[1:]):
            (app/name).write_text(text+'\n', encoding='utf-8')
        output = run(['moon', 'run', '.', '--target', 'js', '--deny-warn'], 'js', app)
        assert output.strip() == '16', output
        tree = run(['moon', 'tree', '--json'], 'js', app)
        verify_tree(json.loads(tree))
        (app/'dependency-tree.json').write_text(tree, encoding='utf-8')
        readme_result = dict(target='js', output=output.strip(), dependency_source='registry')
        print('Registry README example: 16 faces, no workspace override', flush=True)
    report = dict(status='passed', executed_at=datetime.now(timezone.utc).isoformat(),
                  module=module, version=args.version, workspace=str(work),
                  dependency=str(dependency), resolution='Mooncakes registry; no moon.work or local path replacement',
                  compared_source_commit=expected_ref, production_files=production_hashes,
                  registry_archive_sha256=archive_checksum, readme=readme_result,
                  targets=results, commands=commands, platform=platform.platform(),
                  toolchain=run(['moon', 'version', '--all']).strip())
    output = work/'registry-verification.json'
    output.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('Evidence: '+str(output), flush=True)


if __name__ == '__main__':
    main()
