"""Reproduce one target's complete initial-milestone checks on a clean commit."""
import argparse
from datetime import datetime, timezone
import json
import platform
import sys

from common import ROOT, evidence_base, run


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', choices=['native', 'js', 'wasm-gc'], required=True)
    args = parser.parse_args()
    assert not run(['git', 'status', '--porcelain'], capture=True).stdout.strip(), 'Commit changes first'
    history = int(run(['git', 'rev-list', '--count', 'HEAD'], capture=True).stdout)
    assert history >= 10, f'Expected at least 10 real commits, found {history}'
    # Counting commits checks only quantity; the history must still be reviewed.
    run(['moon', 'fmt', '--check'], target=args.target)
    run([sys.executable, 'tools/check.py', '--target', args.target], target=args.target)
    examples = {}
    for name in ['local_edit', 'loop_refine', 'feature_remesh']:
        result = run(['moon', 'run', f'examples/{name}', '--target', args.target, '--deny-warn'],
                     target=args.target, capture=True)
        examples[name] = result.stdout.strip().splitlines()
    assert examples['local_edit'] == ['local_edit: V=5 E=8 F=4 chi=1 boundary=4']
    assert examples['feature_remesh'] == ['feature_remesh: attributes=2 materials=2 protected_crease=true']
    assert examples['loop_refine'] == [f'loop_refine: level={i} {counts} chi=2' for i, counts in
                                     enumerate(['V=4 E=6 F=4', 'V=10 E=24 F=16', 'V=34 E=96 F=64'])]
    for script in ['reference', 'consumer']:
        run([sys.executable, f'tools/{script}.py', '--target', args.target], target=args.target)
    run([sys.executable,'tools/model_verify.py','--target',args.target,
         *(['--real'] if args.target=='js' else [])],target=args.target)
    if args.target == 'js':
        run([sys.executable, 'tools/cli_check.py'], target='js')
        run([sys.executable, 'tools/readme_check.py'], target='js')
    run(['moon', 'info'], target=args.target)
    run(['git', 'diff', '--exit-code'])
    report = dict(evidence_base(args.target, [['python', 'tools/verify.py', '--target', args.target]]),
                  status='passed', timestamp_utc=datetime.now(timezone.utc).isoformat(),
                  commit_count=history,
                  examples=examples)
    output = ROOT/'artifacts'/f'verification-{args.target}.json'
    output.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(f'Initial milestone verification passed: {args.target}, {history} commits')


if __name__ == '__main__':
    main()
