# Geometry job protocol

The original `moonsurface/1` format below is unchanged. The candidate also accepts
`moonsurface-model/1`: positions/triangles with optional attributes, corner_uvs
(F×3×2), materials, feature_edges and sharp_angle. Attributes declare name, width,
interpolation (`linear`, `unit`, `discrete`) and V rows of values.

Model operations: split/flip/collapse (edge pair, optional fraction for split and
collapse); remesh (target_edge_length, optional iterations, max_operations,
relaxation, minimum_angle, max_deviation). Complete real jobs are in `fixtures/real/`.
Results include channels, corner UVs/normals, materials, features, patch labels,
compact maps and categorized reports. Maps refer to the current operation's Model
id domain; reimport/compact starts another domain. Errors contain no partial mesh.

The file CLI accepts one UTF-8 JSON request; it does not import common model formats.
An example with directed quarter-edge splitting:

```json
{
  "format": "moonsurface/1",
  "positions": [[0, 0, 0], [4, 0, 0], [0, 4, 0]],
  "triangles": [[0, 1, 2]],
  "operations": [{"kind": "split", "edge": [1, 0], "fraction": 0.25}],
  "limits": {"max_output_faces": 1000, "max_levels": 2}
}
```

The new vertex is `(3,0,0)`: file-protocol fractions run from the requested first
endpoint toward the second. The adapter translates this to the library edge's
stored orientation. Edges are always located by current vertex pairs, not by
guessing internal edge ids. An earlier operation may remove the requested pair.

`positions` contains length-three finite numeric arrays, `triangles` length-three
integer arrays. `operations` and `limits` may be omitted. Unknown fields are errors.
Integer fields must be integral numbers within [-1,000,000,1,000,000], then satisfy
their own bounds. The bundled JSON parser uses the last value of a duplicate key;
this version does not promise duplicate-key rejection.

Operations, in order:

```json
{"kind": "split", "edge": [0, 1], "fraction": 0.5}
{"kind": "flip", "edge": [0, 2]}
{"kind": "loop", "levels": 2}
```

`fraction` is optional (default .5); `levels` is required. Limits accept only
`max_vertices`, `max_input_faces`, `max_output_faces`, `max_levels`; defaults and
ceilings are in `NUMERICS.md`. There is no collapse or QEM job operation yet.

Success includes `ok:true`, `format:"moonsurface-result/1"`, complete `positions`,
`triangles`, `stats`, and one small report per operation. Loop reports include
level-zero through final count snapshots. Split reports the appended vertex;
flip reports the new diagonal endpoints. Returned stats count boundary loops and
components in addition to V/E/F and Euler characteristic. Normals are available
through the library but are not serialized by this protocol.

Any parsing/validation/operation error returns `ok:false` and an error description,
with no partial geometry arrays. Earlier successful operations in that request
are discarded. Error prose is diagnostic, not a stable machine-readable enum.

## Host behavior

```sh
moon build --target js --deny-warn
node tools/moonsurface.mjs INPUT.json [--out NEW_OUTPUT.json]
```

Relative input/output paths are relative to the caller's working directory;
compiled code is located relative to the script. Space/Unicode paths work.
Without `--out`, success writes one JSON response to stdout. With `--out`, it
creates a new file exclusively (`wx`) and writes the successful response.
It refuses to overwrite any existing file, including the input.

Exit code 0 means a successful job/help; 2 means usage, file, decoding or job error.
Job errors emit their JSON envelope to stdout; host errors emit a message to stderr.
A failed job never creates the requested output. A disk/write failure can leave
a new partial file; it returns failure and does not claim a valid result. File
creation is not a crash-safe transaction and there is no automatic overwrite retry.

The Node adapter caps regular-file input during reading, rejects invalid UTF-8,
and delegates JSON/schema/geometry work to MoonBit. The raw MoonBit executable
instead accepts a small JSON string as its last argument on all three targets:

```sh
moon run cmd/moonsurface --target wasm-gc -- '{"format":"moonsurface/1","positions":[],"triangles":[]}'
```

Shell quoting differs across shells. Use the file CLI for large inputs: argument
length is subject to operating-system limits. Raw executable job errors use the
JSON `ok:false` envelope with process status 0; the Node adapter sets status 2.
