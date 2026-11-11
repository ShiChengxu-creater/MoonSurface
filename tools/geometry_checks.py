"""Independent NumPy face-list metrics and constrained surface/attribute checks.

Projection uses plane Gram systems plus segment candidates, not production's
closest-region implementation or its BVH. Distances below are sampled, not bounds.
"""
from collections import defaultdict
import math
import numpy as np
from reference import audit, key


def metrics(points, faces):
    p = np.asarray(points, dtype=float)
    f = np.asarray(faces, dtype=int)
    stats, edges, *_ = audit(points, faces)
    if not len(f):
        return {**stats, 'min_angle_degrees':0.,'mean_min_angle_degrees':0.,
                'mean_triangle_quality':0.,'edge_min':0.,'edge_max':0.,'edge_mean':0.,'edge_cv':0.}
    tri = p[f]
    angles = []
    for i in range(3):
        a = tri[:,(i+1)%3]-tri[:,i]
        b = tri[:,(i+2)%3]-tri[:,i]
        cosine = np.einsum('ij,ij->i',a,b)/(np.linalg.norm(a,axis=1)*np.linalg.norm(b,axis=1))
        angles.append(np.degrees(np.arccos(np.clip(cosine,-1,1))))
    minima = np.min(angles,axis=0)
    ab, ac, bc = tri[:,1]-tri[:,0], tri[:,2]-tri[:,0], tri[:,2]-tri[:,1]
    doubled_area = np.linalg.norm(np.cross(ab,ac),axis=1)
    q = 2*np.sqrt(3)*doubled_area/(np.einsum('ij,ij->i',ab,ab)+np.einsum('ij,ij->i',ac,ac)+np.einsum('ij,ij->i',bc,bc))
    ep = np.asarray(list(edges), dtype=int)
    lengths = np.linalg.norm(p[ep[:,0]]-p[ep[:,1]],axis=1)
    return {**stats,'min_angle_degrees':float(minima.min()),
            'mean_min_angle_degrees':float(minima.mean()),'mean_triangle_quality':float(q.mean()),
            'edge_min':float(lengths.min()),'edge_max':float(lengths.max()),
            'edge_mean':float(lengths.mean()),'edge_cv':float(lengths.std()/lengths.mean())}


def constraints(job):
    p = np.asarray(job['positions'],dtype=float)
    faces = job['triangles']
    _, edges, *_ = audit(job['positions'], faces)
    incidence = defaultdict(list)
    for index, face in enumerate(faces):
        for a,b in zip(face,face[1:]+face[:1]):
            incidence[key(a,b)].append(index)
    normals = np.cross(p[np.asarray(faces)[:,1]]-p[np.asarray(faces)[:,0]],p[np.asarray(faces)[:,2]]-p[np.asarray(faces)[:,0]])
    normals /= np.linalg.norm(normals,axis=1)[:,None]
    protected = set(map(tuple, map(sorted,job.get('feature_edges',[]))))
    materials = job.get('materials') or [0]*len(faces)
    uvs = job.get('corner_uvs')
    cosine = math.cos(math.radians(job.get('sharp_angle',45)))
    discrete = [c['values'] for c in job.get('attributes',[]) if c['interpolation']=='discrete']
    for edge, uses in incidence.items():
        if len(uses) == 1:
            protected.add(edge)
            continue
        a,b = uses
        seam = False
        if uvs:
            seam = any(max(abs(x-y) for x,y in zip(uvs[a][faces[a].index(v)],uvs[b][faces[b].index(v)])) > 1e-10 for v in edge)
        if seam or materials[a] != materials[b] or np.dot(normals[a],normals[b]) < cosine-1e-12 or any(c[edge[0]]!=c[edge[1]] for c in discrete):
            protected.add(edge)
    graph = {i:set() for i in range(len(faces))}
    for edge, uses in incidence.items():
        if edge not in protected and len(uses)==2:
            a,b=uses; graph[a].add(b);graph[b].add(a)
    charts = [-1]*len(faces)
    for start in range(len(faces)):
        if charts[start]>=0: continue
        stack=[start];charts[start]=start
        while stack:
            for other in graph[stack.pop()]:
                if charts[other]<0: charts[other]=start;stack.append(other)
    return protected, charts


def closest(points, vertices, faces):
    """All-triangle plane projection and three segment minima, in bounded chunks."""
    vertices = np.asarray(vertices,dtype=float)
    faces = np.asarray(faces,dtype=int)
    triangles = vertices[faces]
    a,b,c = triangles[:,0],triangles[:,1],triangles[:,2]
    u,v = b-a,c-a
    uu = np.einsum('ij,ij->i',u,u)
    uv = np.einsum('ij,ij->i',u,v)
    vv = np.einsum('ij,ij->i',v,v)
    determinant = uu*vv-uv*uv
    assert np.all(determinant>0)
    distances, ids, weights = [], [], []
    for first in range(0,len(points),32):
        batch = np.asarray(points[first:first+32],dtype=float)
        w = batch[:,None,:]-a[None,:,:]
        wu = np.einsum('nmi,mi->nm',w,u)
        wv = np.einsum('nmi,mi->nm',w,v)
        beta = (wu*vv-wv*uv)/determinant
        gamma = (wv*uu-wu*uv)/determinant
        bary = np.stack([1-beta-gamma,beta,gamma],axis=2)
        projected = np.einsum('nmk,mkj->nmj',bary,triangles)
        d2 = np.sum((projected-batch[:,None,:])**2,axis=2)
        d2[np.min(bary,axis=2)<-1e-12] = np.inf
        best_bary = bary
        for i,j in [(0,1),(1,2),(2,0)]:
            start,end = triangles[:,i],triangles[:,j]
            direction = end-start
            t = np.clip(np.einsum('nmi,mi->nm',batch[:,None,:]-start,direction)/np.sum(direction**2,axis=1),0,1)
            q = start[None,:,:]+t[:,:,None]*direction[None,:,:]
            candidate = np.sum((q-batch[:,None,:])**2,axis=2)
            use = candidate<d2
            eb = np.zeros_like(bary)
            eb[:,:,i]=1-t;eb[:,:,j]=t
            best_bary = np.where(use[:,:,None],eb,best_bary)
            d2 = np.minimum(d2,candidate)
        which = np.argmin(d2,axis=1)
        rows = np.arange(len(batch))
        distances.extend(np.sqrt(d2[rows,which]).tolist())
        ids.extend(which.tolist())
        weights.extend(best_bary[rows,which].tolist())
    return np.asarray(distances), np.asarray(ids,dtype=int), np.asarray(weights)


def samples(points,faces,limit=512):
    p=np.asarray(points,dtype=float); f=np.asarray(faces,dtype=int)
    rng=np.random.default_rng(20261111)
    vertex_ids=np.linspace(0,len(p)-1,min(len(p),limit),dtype=int)
    face_ids=np.linspace(0,len(f)-1,min(len(f),limit),dtype=int)
    centers=p[f[face_ids]].mean(axis=1)
    return np.concatenate([p[vertex_ids],centers])


def surface_distance(source, output):
    a,_,_=closest(samples(source['positions'],source['triangles']),output['positions'],output['triangles'])
    b,_,_=closest(samples(output['positions'],output['triangles']),source['positions'],source['triangles'])
    values=np.concatenate([a,b]); p=np.asarray(source['positions'])
    diagonal=np.linalg.norm(p.max(axis=0)-p.min(axis=0))
    return dict(samples_each_direction=[len(a),len(b)],max=float(values.max()),
                rms=float(np.sqrt(np.mean(values**2))),max_over_diagonal=float(values.max()/diagonal),
                method='deterministic vertices and face centroids, two directions; not a Hausdorff bound')


def check_model(job, output):
    assert output['ok'] is True
    before=metrics(job['positions'],job['triangles']); after=metrics(output['positions'],output['triangles'])
    for name in ['euler','components','boundary_loops']:
        assert before[name]==after[name], (name,before[name],after[name])
    report=output['operations'][-1]
    for side, values in [('before',before),('after',after)]:
        for name, actual in report[side].items():
            assert np.isclose(actual,values[name],rtol=1e-8,atol=1e-7), (name,actual,values[name])
    threshold=min(before['min_angle_degrees'],report['minimum_angle'])
    assert after['min_angle_degrees']>=threshold-1e-6
    assert report['attempts']==sum(report[k] for k in ['splits','collapses','flips','relaxed','rejected'])
    assert report['rejected']==sum(report[k] for k in ['rejected_topology','rejected_geometry','rejected_attributes','rejected_budget'])
    p=np.asarray(job['positions']); q=np.asarray(output['positions'])
    diagonal=np.linalg.norm(p.max(axis=0)-p.min(axis=0)); epsilon=diagonal*1e-9
    protected,charts=constraints(job)
    anchors=sorted(set(v for edge in protected for v in edge))
    mapping=output['vertex_map']; drift=0.
    for vertex in anchors:
        assert mapping[vertex]>=0, 'protected vertex was deleted'
        drift=max(drift,float(np.linalg.norm(q[mapping[vertex]]-p[vertex])))
    assert drift<epsilon
    features=output['feature_edges']
    for edge in protected:
        start,end=p[list(edge)]; direction=end-start; squared=np.dot(direction,direction)
        intervals=[]
        for a,b in features:
            points=q[[a,b]]
            t=(points-start)@direction/squared
            if min(t)>=-1e-8 and max(t)<=1+1e-8 and np.max(np.linalg.norm(points-start-t[:,None]*direction,axis=1))<epsilon:
                intervals.append(sorted(t))
        frontier=0.
        for lo,hi in sorted(intervals):
            assert lo<=frontier+1e-8, 'constraint chain gap'
            frontier=max(frontier,hi)
        assert frontier>=1-1e-8, 'constraint chain lost'
    errors={}
    if 'corner_normals' in output:
        normals=np.asarray(output['corner_normals'])
        assert normals.shape==(len(output['triangles']),3,3) and np.all(np.isfinite(normals))
        np.testing.assert_allclose(np.linalg.norm(normals,axis=2),1,atol=1e-10)
    for attr in output.get('attributes',[]):
        data=np.asarray(attr['values'])
        assert len(data)==len(q) and np.all(np.isfinite(data))
        if attr['interpolation']=='unit': np.testing.assert_allclose(np.linalg.norm(data,axis=1),1,atol=1e-10)
        if attr['name']=='position_probe':
            error=float(np.abs(data-q).max());assert error<epsilon;errors['position_probe_max']=error
    uv_error=0.
    if job.get('corner_uvs'):
        assert len(output['corner_uvs'])==len(output['triangles'])
        source_faces=np.asarray(job['triangles']); target_faces=np.asarray(output['triangles'])
        original_uv=np.asarray(job['corner_uvs']); final_uv=np.asarray(output['corner_uvs'])
        output_charts=np.asarray(output['face_charts']); source_charts=np.asarray(charts)
        for chart in set(output_charts.tolist()):
            source_ids=np.flatnonzero(source_charts==chart)
            assert len(source_ids)
            target_ids=np.flatnonzero(output_charts==chart)
            # A fixed subset of corners per patch, with endpoints included.
            target_ids=target_ids[np.linspace(0,len(target_ids)-1,min(80,len(target_ids)),dtype=int)]
            query=q[target_faces[target_ids]].reshape(-1,3)
            _, closest_faces, bary=closest(query,p,source_faces[source_ids])
            expected=np.einsum('ni,nij->nj',bary,original_uv[source_ids[closest_faces]])
            actual=final_uv[target_ids].reshape(-1,2)
            uv_error=max(uv_error,float(np.abs(expected-actual).max()))
            mat=(job.get('materials') or [0]*len(source_faces))[int(source_ids[0])]
            assert all(output['materials'][int(i)]==mat for i in np.flatnonzero(output_charts==chart))
        assert uv_error<2e-6, ('corner UV error',uv_error)
    return dict(before=before,after=after,operations={k:v for k,v in report.items() if k not in ('vertex_map','face_map','before','after')},
                protected_edges=len(protected),protected_vertices=len(anchors),max_protected_vertex_drift=drift,
                sampled_corner_uv_max_error=uv_error,attribute_errors=errors,
                input_charts=len(set(charts)), topology_preserved=True)
