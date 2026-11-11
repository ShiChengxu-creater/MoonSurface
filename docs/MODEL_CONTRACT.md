# Model attribute and feature contract — 0.2.0-alpha.1 candidate

`Model` is the deletion-capable, attribute-aware model layer. `Mesh` retains its
geometry-only halfedge split/flip/Loop contract. Accessing `.mesh` from a snapshot
and using geometry Loop is an explicit caller choice, not attribute-aware Loop.

## Supported data

| Payload | Contract |
| --- | --- |
| VertexAttribute Linear | 1–4 finite Double components; convex/linear interpolation |
| VertexAttribute UnitVector | Exactly three components, normalized at import and interpolation; zero/cancelling values reject |
| VertexAttribute Discrete | 1–4 finite components compared exactly; incompatible values reject interpolation/merge |
| CornerUV | UV0 stored per face corner, independently on either side of a seam |
| Materials | Nonnegative face material ids copied to descendant faces |
| Corner normals | Area-weighted smoothing fans separated by protected edges |

At most 16 vertex channels, width 1–4, unique nonempty names up to 64 code units.
Inputs and exported data are owned copies. Linear colors assume the caller's chosen
interpolation space; no automatic sRGB conversion. Skinning, morph targets, multiple
UV sets and semantic weight rules are unsupported. The glTF fixture extractor turns
authored-normal discontinuities into explicit feature edges, then recomputes corner
normals; it does not promise identical custom authored corner-normal values.

## Edits and identifiers

Model split fraction follows the requested a→b pair. Each incident face interpolates
its own UV side and inherits its material. Flip retains vertex data and transfers
the quad's corners. UV orientation reversal rejects. Collapse is restricted to
unprotected interior endpoints with link, duplicate-face and local inversion checks.
It keeps one vertex id and retires the other; default fraction zero retains the
destination data/position, optional blending interpolates compatible channels.

Vertex ids belong to one Model and persist until removal/compaction. Face rewrites
may retire old internal face ids. Compact returns detached geometry/channels, corner
UV/materials, feature edges and sparse-to-dense maps (-1 for retired slots). Face
maps are not one-to-many descendant maps. `face_charts` labels belong to the current
Model reference patches; reimport starts a new label/id domain. Recoverable checks
precede edits. OOM or process termination is not a rollback guarantee.

Operations update local face incidence/edge maps; they do not rebuild the complete
mesh per edit. Remeshing copies the input, keeps tombstones, and compacts once at
output. Audits/snapshots perform full validation. Vertex slot ceilings include
retired slots; compact/reimport reclaims them. Counters are not process RSS bounds.

## Feature policy

Boundary edges, explicit tags, dihedral features (default 45°), UV seams, material
boundaries and discrete-channel interfaces are protected. UV detection uses an
absolute 1e-10 corner tolerance; mark explicit features for finer application rules.
All incident feature vertices are pinned. Protected edges cannot flip; their
endpoints cannot collapse/relax. Splitting along the segment inherits constraints
on both children and preserves separate UV sides. This conservative policy does
not coarsen feature chains and can leave out-of-band edge lengths near features.

## Isotropic remeshing and numeric policy

Each round: split edges longer than 4/3 target, collapse unprotected edges shorter
than 4/5 target, improve valence by flipping, tangentially relax and project to the
original patch. Defaults: three rounds, relaxation .5, 20,000 attempts including
rejections. Hard limits: 0–10 rounds and 0–200,000 attempts, with at most 16 long-edge
sweeps per round. Output is independent of the input.

The requested angle floor defaults to 10°, clamped to the input's minimum angle.
Each edit checks that effective floor. `max_deviation=0` selects target/4; positive
values use object units. A static BVH projects/resamples within the original
constraint-separated patch. Original vertices, edge midpoints and centroids form
seven witnesses per source triangle, reassigned to close faces before each edit.
New face midpoints/centroids are also checked. These are finite sample protections,
not a continuous Hausdorff guarantee or a global intersection test.

Working coordinates recenter at the input bounds and scale by the largest centered
component. Input/target edges below 1e-12 of that scale or unrepresentable deviations
reject. Export may introduce floating roundoff; original feature vertex drift is
measured separately in validation. No exact predicates are claimed.

The report separates topology/constraint, geometry/numeric, attribute and storage
rejections. Stops: IterationLimit, OperationBudget, StableUnderConstraints,
StorageLimit. Zero attempt budget returns a detached unchanged result. Completion
does not imply every edge is in-band. Local witness redistribution cost depends on
samples assigned to affected faces; no constant-time or large-mesh speed claim.
