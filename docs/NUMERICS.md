# Numeric and resource policy — initial milestone

The original Mesh/Loop policy below remains. The 0.2 Model layer additionally uses
bounds recentering, an effective angle floor and bidirectional finite sample guards;
see [MODEL_CONTRACT.md](MODEL_CONTRACT.md). These are not continuous Hausdorff bounds.

Coordinates are finite IEEE-754 `Double`. No exact-predicate or global intersection
guarantee is claimed. The unit tests include coordinates near 1e−300 and 1e300;
this is a tested example range, not a guarantee that every mesh at those scales works.

## Degeneracy and edits

For a face, coordinates are scaled by their largest absolute component before
edge differences; both edges are scaled again before the cross product. Let N be
their cross product and L² the maximum squared length of the three scaled edges.
Reject when |N|² ≤ 1e−28·L⁴ (relative area threshold 1e−14). Repeated corners,
zero scale and coincident edges are also rejected. A large common translation can
erase small differences in floating point; normalization cannot recover lost bits.

Face normals use scaled edge cross products. Flip requires both old/new unit-normal
dot products > 1e−12, in addition to topological and area checks. This is a local
guard, not a global no-self-intersection test. Split accepts finite 0<t<1 only;
if the new point is numerically indistinguishable or creates a degenerate triangle,
the operation fails before editing. Interpolation avoids subtracting opposite-sign
large coordinates directly.

Vertex normals use one common coordinate/edge scale for each incident star and
sum unnormalized face cross products, preserving relative face-area weights.
Zero or non-finite sums raise an error instead of returning NaN. Nearly cancelling
fans can be ill conditioned; the library does not certify their stability.

## Loop stencils

Interior vertex valence n:

```text
beta = (5/8 − (3/8 + cos(2π/n)/4)²) / n
p'   = (1 − n·beta)·p + beta·sum(neighbors)
```

Boundary old vertex: 3/4 of itself plus 1/8 of each of its two boundary neighbors.
Interior edge: 3/8 of each endpoint plus 1/8 of each opposite vertex.
Boundary edge: endpoint midpoint. Every stencil reads the old mesh; updates are
synchronous. Positive weighted sums normalize coordinates first and clamp only
roundoff beyond the convex-combination coordinate bound before restoring scale.

The independent Python reference uses `math.fsum` on triangle-list stencils and
checks coordinates with normalized maximum error <5e−13. Topology, oriented faces,
integer counts and input preservation have separate checks. The reference tolerance
is a verification tolerance, not a bound on arbitrary accumulated geometric error.

## Budgets

| Budget | Default | Supported range |
| --- | ---: | ---: |
| Vertices | 1,000,000 | 0–1,000,000 |
| Input triangles | 250,000 | 0–1,000,000 |
| Output triangles | 1,000,000 | 0–1,000,000 |
| Loop levels per call | 6 | 0–6 |
| JSON input | 16 MiB UTF-8 | Fixed |
| JSON nesting | 16 | Fixed |
| JSON operations | 64 | Fixed |
| Node serialized output | 128 MiB | Fixed, checked after serialization |

Input counts are checked before owned topology allocation; split checks projected
counts before mutation; multi-level Loop prechecks the full sequence before new
geometry. Per level: V'=V+E, E'=2E+3F, F'=4F, B'=2B. The hard input/output ceilings
keep all intermediate count/index arithmetic within signed `Int`; the next count
is checked before using it for allocation.

Limits count vertices/faces rather than RSS. Parsing, copies, JSON text, maps,
halfedges and the old/new meshes consume additional memory. The Node output limit
does not prevent allocation of a larger string by MoonBit. No benchmark, peak-RSS
bound, 80k-face performance result or QEM numeric policy has been established yet.
