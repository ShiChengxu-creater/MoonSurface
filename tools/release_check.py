"""Exercise published job boundaries, similarity transforms and repeatability.

Uses the real file host and the independent checker, not a replacement remesher.
"""
from copy import deepcopy
from hashlib import sha256
import json
import subprocess
import tempfile

from common import ROOT, evidence_base, run
from model_verify import grid, np
from geometry_checks import check_model, surface_distance


def main():
    run(['moon','build','--target','js','--deny-warn'],target='js')
    work = ROOT/'artifacts'
    work.mkdir(exist_ok=True)
    work = type(work)(tempfile.mkdtemp(prefix='release-jobs-',dir=work))
    cases = []

    def execute(job, name, expected=True):
        source = work/(name+'-input.json')
        source.write_text(json.dumps(job,separators=(',',':'),allow_nan=False),encoding='utf-8')
        output = work/(name+'-output.json')
        before = source.read_bytes()
        result = subprocess.run(['node',str(ROOT/'tools/moonsurface.mjs'),str(source),'--out',str(output)],
            cwd=work,capture_output=True,text=True,encoding='utf-8',timeout=60)
        assert source.read_bytes()==before
        assert result.returncode==(0 if expected else 2),(name,result.stderr,result.stdout)
        if expected:
            data=output.read_bytes()
            return json.loads(data),sha256(data).hexdigest()
        error=json.loads(result.stdout)
        assert error['ok'] is False and not output.exists(),name
        assert not {'positions','triangles','attributes','operations'}.intersection(error),name

    base=grid(20261116)
    for scale in [1.,.001,1000.]:
        job=deepcopy(base)
        p=np.asarray(job['positions'])*scale+np.asarray([100.,-32.,7.])
        job['positions']=p.tolist()
        job['attributes'][0]['values']=p.tolist()
        job['operations'][0]['target_edge_length']*=scale
        label='similarity-'+str(scale)
        output,digest=execute(job,label)
        cases.append(dict(name=label,**check_model(job,output),output_sha256=digest))

    folded=deepcopy(base)
    crease=folded['positions'][2][0]
    for p in folded['positions']: p[2]=.2*abs(p[0]-crease)
    folded['attributes'][0]['values']=deepcopy(folded['positions'])
    folded['materials']=[]
    for i,face in enumerate(folded['triangles']):
        side=sum(folded['positions'][v][0] for v in face)/3>crease
        folded['materials'].append(7 if side else 3)
        folded['corner_uvs'][i]=[[folded['positions'][v][0]+(2 if side else 0),
                                  folded['positions'][v][1]] for v in face]
    output,digest=execute(folded,'folded')
    case=check_model(folded,output)
    distance=surface_distance(folded,output)
    assert distance['max_over_diagonal']<.02
    _,repeat=execute(folded,'folded-repeat')
    assert repeat==digest,'identical jobs produced different output bytes'
    cases.append(dict(name='folded-material-uv',**case,distance=distance,output_sha256=digest))

    negatives=[]
    def bad(name,change):
        job=deepcopy(base)
        change(job)
        execute(job,'reject-'+name,False)
        negatives.append(name)
    for option,value in [('target_edge_length',0),('iterations',11),('max_operations',200001),
                         ('relaxation',-1),('minimum_angle',61),('max_deviation',-1)]:
        bad(option,lambda j,k=option,v=value:j['operations'][0].update({k:v}))
    bad('unknown-operation-field',lambda j:j['operations'][0].update(unknown=1))
    bad('unknown-root-field',lambda j:j.update(unknown=1))
    bad('unsupported-qem',lambda j:j['operations'][0].update(kind='qem'))
    bad('sharp-angle',lambda j:j.update(sharp_angle=0))
    bad('negative-material',lambda j:j.update(materials=[-1]*len(j['triangles'])))
    bad('missing-corner',lambda j:j['corner_uvs'][0].pop())
    bad('missing-face-uv',lambda j:j['corner_uvs'].pop())
    bad('invalid-feature',lambda j:j.update(feature_edges=[[0,9999]]))
    bad('duplicate-channel',lambda j:j['attributes'].append(deepcopy(j['attributes'][0])))
    bad('short-channel',lambda j:j['attributes'][0]['values'].pop())
    bad('wrong-width',lambda j:j['attributes'][0].update(width=4))
    bad('empty-channel-name',lambda j:j['attributes'][0].update(name=''))
    bad('zero-normal',lambda j:j['attributes'][1]['values'].__setitem__(0,[0,0,0]))
    bad('unit-width',lambda j:j['attributes'][1].update(width=2))
    bad('late-rejection',lambda j:j.update(operations=[dict(kind='split',edge=[0,1]),
        dict(kind='flip',edge=[0,5])]))
    report=dict(evidence_base('js',[['python','tools/release_check.py']]),status='passed',
                cases=cases,rejected_jobs=negatives,repeatability='identical folded input output SHA-256 matched',
                workspace=str(work))
    (ROOT/'artifacts/release-jobs.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(f'Release jobs: {len(cases)} valid, {len(negatives)} rejected, deterministic repeat passed',flush=True)


if __name__=='__main__': main()
