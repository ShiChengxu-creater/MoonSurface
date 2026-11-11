# SPDX-License-Identifier: GPL-3.0-only
# Standalone, optional verification driver; not used by the MoonBit library.
import importlib.metadata
import json
from pathlib import Path
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
if (ROOT/'artifacts/reference-env').is_dir():
    sys.path.insert(0,str(ROOT/'artifacts/reference-env'))
import numpy as np
import pymeshlab

assert importlib.metadata.version('pymeshlab')=='2025.7.post1'
job=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
target=job['operations'][0]['target_edge_length']
diagonal=float(np.linalg.norm(np.ptp(np.asarray(job['positions']),axis=0)))
mesh=pymeshlab.Mesh(vertex_matrix=np.asarray(job['positions'],dtype=float),
                    face_matrix=np.asarray(job['triangles'],dtype=np.int32))
meshes=pymeshlab.MeshSet();meshes.add_mesh(mesh)
parameters=dict(iterations=3,adaptive=False,selectedonly=False,targetlen=pymeshlab.PureValue(target),
                featuredeg=45,checksurfdist=True,maxsurfdist=pymeshlab.PureValue(diagonal*.01),
                splitflag=True,collapseflag=True,swapflag=True,smoothflag=True,reprojectflag=True)
start=time.perf_counter()
meshes.meshing_isotropic_explicit_remeshing(**parameters)
seconds=time.perf_counter()-start
mesh=meshes.current_mesh()
output=dict(positions=mesh.vertex_matrix().tolist(),triangles=mesh.face_matrix().tolist(),
            reference=dict(version='2025.7.post1',seconds_filter_only=seconds,
                           parameters=dict(iterations=3,target_edge_length=target,
                                           featuredeg=45,max_surface_distance=diagonal*.01)))
with Path(sys.argv[2]).open('x',encoding='utf-8') as file:
    json.dump(output,file,separators=(',',':'))
