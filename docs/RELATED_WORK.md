# Scope and adjacent MoonBit projects

Initial research was recorded on 2026-11-01–02; the following source revisions
were rechecked before implementation. Claims are limited to inspected files at
these revisions, not every branch or subsequent update.

| Project / revision | Existing capability and independent scope |
| --- | --- |
| [walkzzz/moon-geo](https://github.com/walkzzz/moon-geo/tree/d772d7ec43a9c8f569f0276c6e057ba057ac25dd) | Inspected halfedge construction/traversal. MoonSurface adds checked local topology editing, failure preservation and synchronous weighted Loop workflows. |
| [walkzzz/moon-geometry](https://github.com/walkzzz/moon-geometry/tree/10756656c02e787766a1a74f890d9513db12a042) | Inspected subdivision leaves old vertices fixed and uses edge midpoints; inspected simplification merges nearby vertices. MoonSurface's implemented Loop changes old vertices and uses neighbor/opposite stencils; QEM is still planned. |
| [mizchi/three-mbt](https://github.com/mizchi/three-mbt/tree/bcb6352abf2cc620184f1c1d75a857e523a60cdc) | Offers Three.js bindings and editing/modifier operations. MoonSurface provides a renderer-independent MoonBit calculation core across three targets; it does not replace its UI/binding scope. |
| [Milky2018/meshopt_mbt](https://mooncakes.io/docs/Milky2018/meshopt_mbt@0.1.2) | Existing native meshoptimizer binding. MoonSurface does not claim to replace its optimization/attribute coverage. |
| [mik1e80/stlkit](https://github.com/mik1e80/stlkit) | Existing model formats, checks and repair; MoonSurface uses ordinary arrays instead of duplicating those formats. This link is an unpinned background reference. |

Novelty is partial overlap with no identified full match for the proposed combined
scope, with medium search confidence. This is not proof that nobody has built it.
If the only goal were fixing Loop weights in an existing package, contributing
there would be reasonable. This project's larger planned scope also includes a
mutable topology/editing contract, collapse/compaction and constrained QEM; the
last two are explicitly unfinished at this initial milestone.

No source code from these projects is incorporated. Algorithm references and
development-tool provenance are in `THIRD_PARTY.md`. The research did not establish
user interviews, adoption commitments, performance superiority or contest acceptance.
