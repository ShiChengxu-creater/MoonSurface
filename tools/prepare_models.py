"""Prepare mesh-local CC0 geometry from a fixed Khronos revision; no textures fetched.

Exact position welding makes indexed manifold geometry; original UVs stay per corner.
Authored normal discontinuities become protected edges. No silent topology repair.
"""
import base64
from collections import defaultdict
from hashlib import sha256
import json
from pathlib import Path
import struct
import urllib.request

from common import ROOT
from reference import audit

REVISION = '8f492390ddc7a2ae221a1369ef560589cf8c70fb'
BASE = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'+REVISION+'/'


def fetch(path):
    with urllib.request.urlopen(BASE+path, timeout=90) as response:
        return response.read()


def convert(name):
    directory = ROOT/'fixtures'/'real'/name.lower()
    directory.mkdir(parents=True, exist_ok=True)
    prefix = f'Models/{name}/glTF/'
    raw = fetch(prefix+name+'.gltf')
    gltf = json.loads(raw)
    assert len(gltf['meshes']) == 1, 'Select mesh explicitly for a multi-mesh scene'
    buffers = []
    provenance = {name+'.gltf': sha256(raw).hexdigest()}
    for buffer in gltf['buffers']:
        uri = buffer['uri']
        if uri.startswith('data:'):
            binary = base64.b64decode(uri.split(',', 1)[1], validate=True)
        else:
            assert Path(uri).name == uri and '%' not in uri
            binary = fetch(prefix+uri)
        assert len(binary) == buffer['byteLength']
        provenance[uri[:80]] = sha256(binary).hexdigest()
        buffers.append(binary)

    def accessor(index):
        a = gltf['accessors'][index]
        assert 'sparse' not in a and not a.get('normalized', False)
        v = gltf['bufferViews'][a['bufferView']]
        component, size = {5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}[a['componentType']]
        count = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        stride = v.get('byteStride', count*size)
        offset = v.get('byteOffset',0)+a.get('byteOffset',0)
        return [list(struct.unpack_from('<'+component*count, buffers[v['buffer']], offset+i*stride))
                for i in range(a['count'])]

    points, faces, uvs, materials, normal_faces = [], [], [], [], []
    lookup = {}
    for primitive in gltf['meshes'][0]['primitives']:
        assert primitive.get('mode',4) == 4
        attrs = primitive['attributes']
        positions = accessor(attrs['POSITION'])
        texcoords = accessor(attrs['TEXCOORD_0'])
        normals = accessor(attrs['NORMAL'])
        indices = [row[0] for row in accessor(primitive['indices'])]
        assert len(indices)%3 == 0
        welded = []
        for p in positions:
            key = tuple(p)
            if key not in lookup:
                lookup[key] = len(points)
                points.append(p)
            welded.append(lookup[key])
        for start in range(0,len(indices),3):
            ids = indices[start:start+3]
            faces.append([welded[i] for i in ids])
            uvs.append([texcoords[i] for i in ids])
            normal_faces.append([normals[i] for i in ids])
            materials.append(primitive.get('material',0))
    stats, *_ = audit(points,faces)
    features = []
    corner_normals = defaultdict(list)
    for face, normals in zip(faces,normal_faces):
        for i in range(3):
            a,b = face[i],face[(i+1)%3]
            corner_normals[tuple(sorted((a,b)))].append({a:normals[i],b:normals[(i+1)%3]})
    for edge, uses in corner_normals.items():
        if len(uses) == 2 and any(sum((x-y)**2 for x,y in zip(uses[0][v],uses[1][v])) > 1e-10 for v in edge):
            features.append(list(edge))
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    diagonal = sum((a-b)**2 for a,b in zip(lo,hi))**.5
    job = dict(format='moonsurface-model/1', positions=points, triangles=faces,
        corner_uvs=uvs, materials=materials, feature_edges=features, sharp_angle=45,
        attributes=[dict(name='position_probe',width=3,interpolation='linear',values=points)],
        operations=[dict(kind='remesh',target_edge_length=diagonal/22,iterations=3,max_operations=20000)])
    payload = json.dumps(job,separators=(',',':'),allow_nan=False).encode()
    (directory/'input.json').write_bytes(payload+b'\n')
    notice = fetch(f'Models/{name}/README.md')
    assert b'Creative Commons Zero' in notice
    (directory/'SOURCE.md').write_bytes(notice)
    source = dict(name=name,revision=REVISION,license='CC0-1.0',
        upstream=BASE+f'Models/{name}/README.md',source_sha256=provenance,
        input_sha256=sha256(payload+b'\n').hexdigest(),stats=stats,
        extraction='first/only mesh in mesh-local coordinates; no textures or scene transforms; exact position weld; original corner UV/material; authored normal seams protected',
        normal_seam_edges=len(features), target_edge_length=diagonal/22,
        added_attribute='analytic position_probe only; not claimed to be an original authored attribute')
    (directory/'source.json').write_text(json.dumps(source,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(name=name,stats=stats,protected_normal_seams=len(features),bytes=len(payload))))


if __name__ == '__main__':
    for name in ['Avocado','Suzanne']:
        convert(name)
    license_data = fetch('LICENSES/CC0-1.0.txt')
    (ROOT/'fixtures'/'real'/'CC0-1.0.txt').write_bytes(license_data)
