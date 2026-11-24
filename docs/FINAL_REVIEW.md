# Final-review scope and reproduction

Prepared 2026-11-16. The revised core scope is attributed model editing, conservative
feature preservation, isotropic remeshing and the original geometry Loop workflow.
QEM is not part of this release. Skinning/morphs/multiple UVs, complete glTF
round-trip and global self-intersection guarantees are unsupported. The formal
proposal and organizer correspondence are maintained by the participant outside
the public product repository.

Continued development, 2026-11-24: version 0.2.1 optimizes reference storage,
patch-local search and no-work requests without changing the public API/policy.
The 0.2.0 evidence below remains a historical release record; new comparison
measurements are appended to [SCALE.md](SCALE.md), and registry proof is tracked
separately for each version.

Publication update: 0.2.1 has now been published from `6453803`, after four CI jobs
passed. Fresh three-target registry consumers passed 5 tests per target, public
source/archive hashes matched, and the README registry app returned 16 faces.

## Deliverables and evidence

| Item | Reproduce / inspect |
| --- | --- |
| Pure MoonBit core and public errors | Root `.mbt` files, generated interfaces; no external geometry runtime |
| Attribute/UV/material editing | `model_stress_test.mbt`, `model_test.mbt`, [MODEL_CONTRACT](MODEL_CONTRACT.md) |
| Protected chains and remeshing | `remesh_test.mbt`, `examples/feature_remesh` |
| Three complete examples | `local_edit`, `loop_refine`, `feature_remesh`; exact outputs checked by `tools/verify.py` |
| Core and external consumers | 50 tests per target for 0.2.1; 5 tests each for clean source and actual packaged ZIP |
| Independent measurement | NumPy face-list topology/Gram projection; six seeded jobs, four damaged-result controls |
| Real asset/reference comparison | [REAL_MODELS](REAL_MODELS.md); original UV/materials, fixed CC0 sources and optional MeshLab |
| File job boundary coverage | `tools/release_check.py`: four valid transformations/folded jobs, 21 rejections, byte-repeatability |
| Bounded scale/resource measurements | `tools/benchmark.py`; per-run parameters, hashes, timings, process counters and stop reasons |
| CI | Linux native/JS/wasm-gc and Windows native; explicit check/build/test; reference and smoke jobs |
| Published versions | [REGISTRY_RELEASE](REGISTRY_RELEASE.md): version-specific registry download, source/hash and three-target proof |
| License and provenance | Apache-2.0 core; CC0 assets; separately licensed optional GPL reference driver; THIRD_PARTY/AI_USAGE |

Local pre-publication measurements and exact source revisions are summarized in
[final-review.json](evidence/final-review.json); the scale table and visible quality
limits are in [SCALE.md](SCALE.md). A later documentation commit does not change the
recorded measurement revisions.

## Verification commands

Use the pinned compiler from README, Python 3.12+ and Node 22+. Native Windows
requires an existing MSVC x64 toolchain. Run from a clean, complete Git checkout:

```sh
python -m pip install -r requirements-dev.txt
python tools/verify.py --target js
python tools/verify.py --target wasm-gc
python tools/verify.py --target native
python -m pip install -r requirements-reference.txt
python tools/model_verify.py --target js --real --reference
python tools/benchmark.py --sizes 32 64 128 --repeats 3
```

Every script writes actual results under ignored `artifacts/`; inspect source commit
and `source_dirty` before citing them. The seeded edit test performs 480 attempted
operations with a reconstruction audit after each attempt and exact failed-state
snapshot comparisons. It does not prove correctness for arbitrary inputs. The
file-job tests ensure later failures produce no partial mesh/file, not disk-crash
atomicity. Scale checks validate the actual output topology/attributes/constraints;
they do not assert every edge reaches the target interval.

Memory measurements are fresh Node host processes. Windows uses sampled
[PeakWorkingSetSize](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters),
Linux sampled `/proc/PID/status` VmHWM. Observing every 20 ms can miss the last peak,
so results are lower bounds of OS counters, not exact algorithm-only memory usage.
All runs include process startup, input, computation and JSON output. A 10,000
attempt cap bounds this experiment; hitting it is recorded, not hidden or called
full convergence. CPU, OS, compiler, parameters and hashes accompany the report.

## Publication and final submission status

Stable `0.2.0` is published from `b993b41`. Its four exact-head CI jobs passed before
publication; a fresh three-target registry consumer subsequently passed 5 tests per
target and the README example. Source/archive hashes and commands are in
[REGISTRY_RELEASE.md](REGISTRY_RELEASE.md). Local workspace tests are separate
from that registry evidence. Later documentation commits do not replace the
published source revision. Do not re-upload a changed archive under `0.2.0`.

The participant must check the final delivery links and submit through the official
channel. Repository/test completion, package publication and organizer acceptance
are separate facts. No contest form, message or final acceptance is implied here.
