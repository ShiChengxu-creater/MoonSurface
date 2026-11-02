# Sources and third-party materials

Production algorithms in this repository are independently written in MoonBit.
No source from the adjacent MoonBit geometry packages has been copied.

| Source | Use | License / scope |
| --- | --- | --- |
| MoonBit bundled core `0.10.14+7d59c7ec9` | Build/runtime standard library | Apache-2.0; supplied by the pinned toolchain |
| Charles Loop, 1987, [Smooth Subdivision Surfaces Based on Triangles](https://www.microsoft.com/en-us/research/publication/smooth-subdivision-surfaces-based-on-triangles/) | Algorithm definition | Paper reference; no paper text or code redistributed |
| [Geometry Central surface model](https://geometry-central.net/surface/surface_mesh/basics/) | Halfedge and manifold design background | Documentation reference; no code copied |
| [Illinois geometry course](https://cs418.cs.illinois.edu/website/text/make-geom.html) | Loop weights / normal computation cross-check | Documentation reference; no code copied |

Fixtures are generated from original coordinate lists and fixed-seed grid generators.
Development references, generated fixtures and runtime dependencies are separate.
Any later source copying or reference binary requires a pinned revision, exact
license and retained notices before entering a package.

The development consumer workflow (Git snapshots, explicit `moon.work` members,
and package ZIP separation) follows the participant's October MoonBit projects
and handoff notes. MoonSurface's consumer fixtures, tests and implementation are
newly authored; no October geometry implementation is reused. This tooling is
development infrastructure and is not counted as a new geometry algorithm.

`tools/reference.py` is a newly authored stdlib Python mathematical reference,
using triangle-list incidence rather than the production halfedge structure.
It is not an external OpenMesh oracle and is also AI-assisted, as disclosed in
`AI_USAGE.md`. No external model datasets or reference binaries are bundled.

CI uses GitHub's actions/checkout v4, actions/setup-node v4,
actions/setup-python v5 and actions/upload-artifact v4 (MIT licensed upstream
actions, invoked by workflow); the MoonBit official installer downloads the
specified toolchain. These are development services, not vendored product code.
