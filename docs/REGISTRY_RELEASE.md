# Registry release — 0.1.0-alpha.1

`ShiChengxu/moonsurface@0.1.0-alpha.1` has been published by the participant.
The public registry reports the version as available and not deprecated.
This is the initial alpha milestone; collapse/compact/QEM remain future work.

- Published source: `4aae55eec5bb1c7fffb08ef732bc7d88dcc6383a`.
- Archive SHA-256: `30c01a7247526bdcc89cc789401d6076bf2b46dd900a0a567ffddb6204fe58d5`.
- Verification: a new standalone project, no ancestor `moon.work`, no local path override.
- Dependency tree: version `0.1.0-alpha.1`, `source.kind = registry`, not a workspace member.
- Public API consumption: 4 tests each on JS, wasm-gc and Windows native/MSVC.
- Source comparison: all 13 non-test `.mbt` files match the published source revision after LF normalization.
- README app: compiled as a standalone registry consumer on JS and returned 16 faces.

The archive checksum in live registry metadata matches the previously verified
`moon package` ZIP. The tests exercise the downloaded dependency, rather than a
workspace copy. They cover edits, normals, owned output arrays, Loop, typed failures
and the separately imported geometry job package. This does not replace further
algorithm/scale validation or the contest's final review.

Reproduce from a checkout containing the verification tool:

```sh
python tools/registry_consumer.py --version 0.1.0-alpha.1 --source-ref 4aae55e --expected-sha256 30c01a7247526bdcc89cc789401d6076bf2b46dd900a0a567ffddb6204fe58d5 --readme
```

Each execution creates a fresh consumer and saves live metadata, dependency trees
and a machine report. A compact, machine-independent result is retained in
[`evidence/registry-0.1.0-alpha.1.json`](evidence/registry-0.1.0-alpha.1.json).
Later documentation/tooling commits on `main` do not change the published archive.
The participant should use a new version for a subsequent package publication.
