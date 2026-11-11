# Sources, data and verification tools

The MoonBit production implementation is independently written and Apache-2.0.
No adjacent MoonBit geometry, CGAL, OpenMesh or MeshLab implementation is copied.
Existing algorithm ideas are not claimed as new theory. AI assistance is disclosed
in `AI_USAGE.md`.

| Material | Use and license |
| --- | --- |
| Bundled MoonBit core `0.10.14+7d59c7ec9` | Runtime standard library, Apache-2.0 |
| [Loop 1987](https://www.microsoft.com/en-us/research/publication/smooth-subdivision-surfaces-based-on-triangles/) | Algorithm reference; no paper text/code redistributed |
| [Geometry Central](https://geometry-central.net/surface/surface_mesh/basics/) | Topology design background; no code copied |
| [Illinois geometry course](https://cs418.cs.illinois.edu/website/text/make-geom.html) | Weight/normal cross-check; no code copied |
| [CGAL mesh processing](https://doc.cgal.org/latest/Polygon_mesh_processing/index.html) | Remeshing design reference; independent implementation |
| [PyMeshLab filter documentation](https://pymeshlab.readthedocs.io/en/latest/filter_list.html#meshing-isotropic-explicit-remeshing) | External comparison configuration, not a production algorithm |

Small fixtures and fixed-seed grids are original. The real Avocado (Microsoft, 2017)
and Suzanne (Norbert Nopper/UX3D, 2017) fixtures are CC0-1.0 data from Khronos glTF
Sample Assets revision `8f492390ddc7a2ae221a1369ef560589cf8c70fb`. Legal notices,
exact URLs/hashes, extraction scope and the full CC0 license are in `fixtures/real/`.
No texture images are bundled. Source/ZIP consumer techniques follow the participant's
October development lessons; new geometry and fixtures are not October code reuse.

NumPy 2.2.6 is a BSD-3-Clause development measurement dependency. PyMeshLab
2025.7.post1 is an optional GPLv3 reference process. Its independently written driver
`reference_tools/meshlab_reference.py` is marked GPL-3.0-only, with its own LICENSE.
It runs separately from the Apache-2.0 checker and is not imported/linked by the
MoonBit library. No Python dependencies or MeshLab binaries are redistributed here.
Full process and filter-only timings are retained but are not a fair speed comparison.

Python references/checkers are newly authored and also AI-assisted; independent
structure does not imply a human-certified oracle. MeshLab provides the external
comparison; OpenMesh validation and a QEM implementation remain future work.

CI invokes MIT-licensed GitHub actions checkout v4, setup-node v4, setup-python v5
and upload-artifact v4. The official installer obtains the fixed MoonBit toolchain.
These are development services, not vendored library code.
