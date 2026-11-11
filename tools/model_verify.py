"""Reproduce feedback validation on public API jobs and real CC0 mesh assets."""
import argparse
from copy import deepcopy
from hashlib import sha256
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from common import ROOT, evidence_base, run

# Optional local reference wheels are deliberately outside the product package.
local_reference = ROOT/'artifacts/reference-env'
if local_reference.is_dir():
    sys.path.insert(0,str(local_reference))
import numpy as np
from geometry_checks import check_model, metrics, surface_distance


def grid(seed):
    rng=np.random.default_rng(seed)
    xs=np.linspace(0,1,5);ys=np.linspace(0,1,5)
    xs[1:-1]+=rng.uniform(-.06,.06,3);ys[1:-1]+=rng.uniform(-.06,.06,3)
    p=[[float(x),float(y),0.] for y in ys for x in xs]
    f=[face for y in range(4) for x in range(4) for face in
       ([y*5+x,y*5+x+1,(y+1)*5+x+1],[y*5+x,(y+1)*5+x+1,(y+1)*5+x])]
    return dict(format='moonsurface-model/1',positions=p,triangles=f,
                corner_uvs=[[[p[v][0],p[v][1]] for v in face] for face in f],
                attributes=[dict(name='position_probe',width=3,interpolation='linear',values=p),
                            dict(name='normal',width=3,interpolation='unit',values=[[0,0,1]]*len(p)),
                            dict(name='label',width=1,interpolation='discrete',values=[[7]]*len(p))],
                operations=[dict(kind='remesh',target_edge_length=.18+.035*(seed%6),iterations=2,max_operations=2000)])


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--target',choices=['js','wasm-gc','native'],required=True)
    parser.add_argument('--real',action='store_true',help='real assets through the JS file host')
    parser.add_argument('--reference',action='store_true',help='also run pinned MeshLab geometry-only comparison')
    args=parser.parse_args()
    assert not args.real or args.target=='js'
    assert not args.reference or args.real
    assert np.__version__=='2.2.6', f'Install numpy==2.2.6; found {np.__version__}'
    run(['moon','build','--target',args.target,'--deny-warn'],target=args.target)
    base=ROOT/'artifacts';base.mkdir(exist_ok=True)
    work=Path(tempfile.mkdtemp(prefix='models-'+args.target+'-',dir=base))
    cases=[]

    def execute(job,label,file_host=False):
        data=json.dumps(job,separators=(',',':'),allow_nan=False)
        path=work/(label+'-input.json');path.write_text(data,encoding='utf-8')
        command=['node',str(ROOT/'tools/moonsurface.mjs'),str(path)] if file_host else [
            'moon','run','cmd/moonsurface','--target',args.target,'--',data]
        start=time.perf_counter()
        result=run(command,target=args.target,capture=True)
        elapsed=time.perf_counter()-start
        out=json.loads(result.stdout)
        output=work/(label+'-output.json');output.write_text(result.stdout,encoding='utf-8')
        return out,dict(input_sha256=sha256(path.read_bytes()).hexdigest(),
                        output_sha256=sha256(output.read_bytes()).hexdigest(),seconds_host_included=elapsed)

    for seed in range(20261111,20261117):
        job=grid(seed)
        out,hashes=execute(job,str(seed))
        case=check_model(job,out)
        for attr in out['attributes']:
            if attr['name']=='label': assert all(row==[7] for row in attr['values'])
        cases.append(dict(name='grid-'+str(seed),**case,**hashes))
    # The independent checks must reject corrupted geometry/statistics/attributes.
    for kind in ['position','uv','statistics','feature']:
        mutant=deepcopy(out)
        if kind=='position': mutant['attributes'][0]['values'][0][0]+=.1
        if kind=='uv': mutant['corner_uvs'][0][0][0]+=.1
        if kind=='statistics': mutant['operations'][0]['after']['edge_cv']+=.1
        if kind=='feature': mutant['feature_edges']=[]
        try: check_model(job,mutant)
        except AssertionError: pass
        else: raise AssertionError('undetected mutation: '+kind)
    real=[]
    for name in ['avocado','suzanne'] if args.real else []:
        source=ROOT/'fixtures/real'/name
        original_bytes=(source/'input.json').read_bytes()
        provenance=json.loads((source/'source.json').read_text(encoding='utf-8'))
        assert sha256(original_bytes).hexdigest()==provenance['input_sha256']
        job=json.loads(original_bytes)
        out,hashes=execute(job,name,True)
        case=check_model(job,out)
        distances=surface_distance(job,out)
        assert distances['max_over_diagonal'] < .02, distances
        assert case['after']['edge_cv'] < case['before']['edge_cv']
        assert case['after']['mean_triangle_quality'] >= case['before']['mean_triangle_quality']
        row=dict(name=name,provenance=provenance,attributed=dict(**case,distance=distances,**hashes))
        geometry=deepcopy(job)
        for key in ['corner_uvs','attributes','materials','feature_edges']:
            geometry.pop(key,None)
        geom_out,geom_hashes=execute(geometry,name+'-geometry',True)
        row['geometry_only']=dict(**check_model(geometry,geom_out),
                                  distance=surface_distance(job,geom_out),**geom_hashes)
        if args.reference:
            reference_path=work/(name+'-meshlab.json')
            run([sys.executable,str(ROOT/'reference_tools/meshlab_reference.py'),
                 str(work/(name+'-geometry-input.json')),str(reference_path)],target='js')
            data=reference_path.read_bytes()
            reference=json.loads(data)
            row['meshlab_geometry_only']=dict(metrics=metrics(**dict(points=reference['positions'],faces=reference['triangles'])),
                distance=surface_distance(job,reference),**reference['reference'],
                output_sha256=sha256(data).hexdigest(),
                caveat='geometry-only; feature-chain/boundary policy and angle floor differ; not a bitwise equivalence claim')
        real.append(row)
        print(f"Real {name}: CV {case['before']['edge_cv']:.4f} -> {case['after']['edge_cv']:.4f}; UV error {case['sampled_corner_uv_max_error']:.3g}",flush=True)
    report=dict(evidence_base(args.target,[['python','tools/model_verify.py','--target',args.target,
                *(['--real'] if args.real else []),*(['--reference'] if args.reference else [])]]),
                status='passed',numpy=np.__version__,grids=cases,negative_controls=4,real_models=real,workspace=str(work),
                measurements='independent face-list topology/Gram projection; sampled distances are not Hausdorff bounds')
    output=base/('model-'+args.target+('-reference' if args.reference else '')+'.json')
    output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('Model verification passed; report: '+str(output),flush=True)


if __name__=='__main__': main()
