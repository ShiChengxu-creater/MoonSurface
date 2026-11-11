# Public API contract — 0.1.0-alpha.1

The geometry contract below is retained by the 0.2 candidate. New deletion/attribute
Model APIs have a separate contract in [MODEL_CONTRACT.md](MODEL_CONTRACT.md).

The generated root `pkg.generated.mbti` is the complete signature reference.
The `exchange` package has one public function: `execute_json(String) -> String`.

## Ownership and topology

`Mesh::from_indexed(positions, triangles, limits?=...)` validates geometry, manifold
incidence, orientation and vertex fans, then owns copies of its input arrays.
`IndexedMesh::new` checks geometry only; it is not a manifold certificate.
Neither type exposes mutable internal arrays. `to_indexed`, `positions` and
`faces` return detached storage. `Vec3` fields are immutable values.

Vertex/face indexes and `EdgeId` are zero based. An edge id belongs to one mesh;
there is no runtime provenance tag, so passing an id from another mesh is a caller
error even when its integer happens to be in range. Negative/out-of-range ids
raise `InvalidElement`. `find_edge(a,b)` returns `None` for invalid or absent pairs.

`neighbors(v)` returns one ordered, complete one-ring. `boundary_loops` returns
exterior-oriented vertex cycles with no repeated closing vertex. Disconnected
components are allowed. No API promises geometric outward orientation.
`stats()` reports V/E/F, boundary edges/loops, connected components and V−E+F.
`validate()` audits connectivity and geometry in O(V+E+F) expected time.

## Local edits

`split_edge(edge, fraction?=0.5)` measures fraction from `edge_vertices(edge).0`
to `.1`, regardless of the order used in `find_edge`. The new vertex is appended;
old vertex/face ids remain valid; new faces append. The old edge id becomes the
first-endpoint–new-vertex segment. An interior split adds (V,E,F)=(1,3,2), a boundary
split adds (1,2,1). The report lists created ids. No interpolation of other attributes.

`flip_edge(edge)` requires two incident faces, no existing opposite diagonal,
nondegenerate new faces and positive local normal agreement. The same edge id now
denotes the new diagonal; both face ids remain. Neighboring edge ids remain valid.
Changing a diagonal twice need not restore the exact triangle tuple rotations.

Checks that can raise a recoverable `SurfaceError` precede mutation. On these
errors, coordinates, triangles, connectivity and counts are unchanged. This does
not provide rollback after process termination or memory exhaustion.
Split examines the local one-ring, flip has expected O(1) local work with map lookup;
neither operation rebuilds the complete mesh to perform an edit.

`copy`, `to_indexed`/rebuild and subdivision produce independent meshes. Edge ids
may be renumbered there; re-find edges on each result. This milestone has no deletion,
collapse, live/dead element handling, or compact mapping API.

## Loop and normals

`plan_loop(k)` returns count snapshots including level zero and prechecks all
requested levels against the count policy. `subdivide_loop(mesh,k)` returns a new
mesh and those snapshots. Level zero also returns a detached copy. Input is
unchanged on success and on recoverable failure. Limits remain attached to results.
`loop_step()` executes one step and respects a zero `max_levels` policy.

The implementation uses the original cosine-based Loop beta, not the simplified
Warren beta. See `NUMERICS.md`. Each step costs O(V+E+F) expected time and storage;
the original input and current result can coexist. Face count grows by 4 per level.
Old vertices keep their indexes within a Loop result; edge points follow in the
source edge-id order. Each face produces three corner triangles then one center
triangle. `LoopResult.stages` contains snapshots, not live statistics after edits.

`face_normals()` returns unit normals in exported face order. `vertex_normals()`
returns area-weighted unit normals; a cancelling or numerically undefined star
raises `NumericalFailure`. Both return new arrays. No shading attributes are imported.

## Error categories

`SurfaceError` distinguishes invalid arguments/ids, budgets, invalid indexes,
non-finite coordinates, degenerate/duplicate faces, isolated vertices, orientation,
non-manifold edge/vertex, boundary flips, existing diagonals, numerical failures
and topology invariants. Match error constructors, not formatted error strings.
When multiple faults exist, which is detected first is not an API guarantee.
