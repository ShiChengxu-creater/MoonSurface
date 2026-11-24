"""Same-machine paired comparison against an exact archived product revision.

No speed threshold. Every measured output must be byte-identical to the baseline
and pass the independent checker. Host/process measurements include Node overhead.
"""
import argparse
from copy import deepcopy
from hashlib import sha256
import json
from pathlib import Path
import statistics
import subprocess
import tempfile

from common import ROOT, evidence_base, run
from consumer import unpack
from benchmark import grid, measure
from geometry_checks import check_model


def atlas(size):
    job=grid(size,200000)
    tile=max(4,size//8)
    width=size//tile
    job['materials']=[(y//tile)*width+x//tile
                     for y in range(size) for x in range(size) for _ in range(2)]
    return job


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--baseline',default='47c62fcab3d7b5693d12e9d659c1b367dcb9d410')
    parser.add_argument('--repeats',type=int,default=3)
    parser.add_argument('--smoke',action='store_true')
    args=parser.parse_args()
    assert 1<=args.repeats<=5
    baseline=run(['git','rev-parse','--verify',args.baseline+'^{commit}'],capture=True).stdout.strip()
    assert not run(['git','status','--porcelain'],capture=True).stdout.strip(),'Commit before comparison'
    base=ROOT/'artifacts';base.mkdir(exist_ok=True)
    work=Path(tempfile.mkdtemp(prefix='perf-compare-',dir=base))
    snapshot=subprocess.run(['git','archive','--format=zip',baseline],cwd=ROOT,check=True,capture_output=True).stdout
    old=work/'baseline';unpack(snapshot,old)
    run(['moon','build','--target','js','--deny-warn'],cwd=old,target='js')
    run(['moon','build','--target','js','--deny-warn'],target='js')
    cases=[('avocado',json.loads((ROOT/'fixtures/real/avocado/input.json').read_bytes()))]
    if not args.smoke:
        cases.extend([('suzanne',json.loads((ROOT/'fixtures/real/suzanne/input.json').read_bytes())),
                      ('grid-32768',grid(128,200000))])
    size=16 if args.smoke else 128
    zero=grid(size,0)
    cases.extend([(f'zero-budget-{size}',zero),(f'material-atlas-{16 if args.smoke else 64}',atlas(16 if args.smoke else 64))])
    rows=[]
    for name,job in cases:
        source=work/(name+'-input.json')
        source.write_text(json.dumps(job,separators=(',',':'),allow_nan=False),encoding='utf-8')
        assert source.stat().st_size<=16*1024*1024
        timings={'baseline':[],'optimized':[]};digests={};output=None
        # One warm-up per variant, then alternate first runner to reduce ordering bias.
        for repeat in range(args.repeats+1):
            order=['baseline','optimized'] if repeat%2==0 else ['optimized','baseline']
            for label in order:
                runner=(old if label=='baseline' else ROOT)/'tools/moonsurface.mjs'
                result=work/f'{name}-{label}-{repeat}-output.json'
                measured=measure(['node',str(runner),str(source)],result,work/f'{name}-{label}-{repeat}-stderr.txt')
                content=result.read_bytes();digest=sha256(content).hexdigest()
                assert label not in digests or digests[label]==digest,'unstable repeated output'
                digests[label]=digest
                if repeat:timings[label].append(measured)
                if label=='optimized' and output is None:output=json.loads(content)
        assert digests['baseline']==digests['optimized'],f'output changed: {name}'
        checked=check_model(job,output)
        medians={k:statistics.median(v['seconds_host_included'] for v in samples) for k,samples in timings.items()}
        peaks={k:max(v['sampled_peak_process_bytes'] for v in samples) for k,samples in timings.items()}
        row=dict(name=name,input_sha256=sha256(source.read_bytes()).hexdigest(),
                 output_sha256=digests['optimized'],output_byte_identical=True,
                 measurements=timings,median_seconds=medians,sampled_peak_bytes=peaks,
                 speedup=medians['baseline']/medians['optimized'],**checked)
        rows.append(row)
        print(f'{name}: {medians["baseline"]:.3f}s -> {medians["optimized"]:.3f}s '
              f'({row["speedup"]:.2f}x); {peaks["baseline"]/1024**2:.1f} -> '
              f'{peaks["optimized"]/1024**2:.1f} MiB observed process peak; byte-identical',flush=True)
    report=dict(evidence_base('js',[['python','tools/compare_performance.py','--baseline',baseline,
                '--repeats',str(args.repeats),*(['--smoke'] if args.smoke else [])]]),
        status='passed',baseline_commit=baseline,baseline_archive_sha256=sha256(snapshot).hexdigest(),
        cases=rows,repeats=args.repeats,warmups=1,workspace=str(work),
        method='alternating fresh Node processes; one warm-up per variant; identical input and output bytes; '
               '20 ms OS peak-counter observations include host overhead and are lower bounds')
    output=base/('performance-smoke.json' if args.smoke else 'performance-comparison.json')
    output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
