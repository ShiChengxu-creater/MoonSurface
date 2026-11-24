# Registry releases

## 0.2.1 — performance update, published 2026-11-24

The approved 0.2.1 archive was published after four exact-head jobs of
[CI 45347672321](https://github.com/ShiChengxu-creater/MoonSurface/actions/runs/45347672321)
passed, including output-preserving comparison smoke on Linux and Windows.
The server returned `200 OK`; subsequent metadata/download verification matched
the same frozen archive. [SCALE.md](SCALE.md) retains all paired measurements.

- Published source: `645380322d01d77c19c10a7590479567b9aa330b`.
- Archive SHA-256: `d7f507943b221ca9afeed796e3af88d50fed642f24e2bfcd7f1888dd54cc9640`.
- Registry created at: `2026-11-24T07:27:17.962461+00:00`.
- Fresh JS/wasm-gc/Windows native consumers: 5/5 per target, with no local path or workspace override.
- All 23 non-test MoonBit files matched the approved source after LF normalization.
- README registry app compiled and returned 16 faces.
- Portable report: [registry-0.2.1.json](evidence/registry-0.2.1.json).

```sh
python tools/registry_consumer.py --version 0.2.1 --source-ref 6453803 --expected-sha256 d7f507943b221ca9afeed796e3af88d50fed642f24e2bfcd7f1888dd54cc9640 --readme
```

The previous 0.2.0 release below remains unchanged. Post-publication documentation
does not replace the approved immutable archive or its source revision.

## 0.2.0 — stable, published 2026-11-16

The explicitly approved archive was published after all four jobs of
[CI 43848088670](https://github.com/ShiChengxu-creater/MoonSurface/actions/runs/43848088670)
passed on the exact release commit. The server returned `200 OK`. Registry metadata
and a fresh independent download matched the same archive checksum.

- Published source: `b993b4129f5967440864b656ac7fb8b79dae880a`.
- Archive SHA-256: `677954d198a6c2556843e2395fbda9c5286fb81629b2ed70d7ced3d264c96cf2`.
- Registry created at: `2026-11-16T10:25:08.196233+00:00`.
- Fresh JS, wasm-gc and Windows native/MSVC consumers: 5/5 tests per target.
- All 23 non-test MoonBit source files matched the release revision after LF normalization.
- Dependency source was registry, not a workspace member; no local path override.
- README registry example compiled and returned 16 faces.
- Portable report: [registry-0.2.0.json](evidence/registry-0.2.0.json).

```sh
python tools/registry_consumer.py --version 0.2.0 --source-ref b993b41 --expected-sha256 677954d198a6c2556843e2395fbda9c5286fb81629b2ed70d7ced3d264c96cf2 --readme
```

Documentation and evidence updates after publication do not change the immutable
release archive. `moon package` on a later documentation checkout may contain
different documentation bytes; that is not a replacement registry release.

## 0.2.0-alpha.1 — published 2026-11-11

The participant published `ShiChengxu/moonsurface@0.2.0-alpha.1`. Its archive includes
the Model attributes/features/remeshing API. A fresh standalone registry consumer
passed 5 public-API tests on each of JS, wasm-gc and Windows native/MSVC, including
the new model remesher. The README app also compiled from the registry and returned
16 faces. No workspace or local path override was present.

- Published source: `2cfbeb6964eb941df105dd95dda3d4376c2d53b7`.
- Archive SHA-256: `9de021c074a3bf8ac4dcb0fd6e9b5cc3163b9406c6a40fe2a7dffde5c322c855`.
- Registry created at: `2026-11-11T14:07:20.986924+00:00`.
- All 23 non-test MoonBit source files matched that revision after LF normalization.
- Portable report: [registry-0.2.0-alpha.1.json](evidence/registry-0.2.0-alpha.1.json).

```sh
python tools/registry_consumer.py --version 0.2.0-alpha.1 --source-ref 2cfbeb6 --expected-sha256 9de021c074a3bf8ac4dcb0fd6e9b5cc3163b9406c6a40fe2a7dffde5c322c855 --readme
```

This alpha is distinct from stable `0.2.0` above. Later docs/tests commits cannot change an immutable
published archive; a new publication must use its own version and be verified again.

## 0.1.0-alpha.1 — historical initial release

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
