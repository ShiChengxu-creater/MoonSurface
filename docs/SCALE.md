# Bounded scale measurements — 0.2.0 candidate

Measured 2026-11-16 on Windows 11, Intel Core i9-14900HX (24 cores / 32 logical
processors), 16,890,322,944 bytes physical RAM, Node 24.22.1, Python 3.13.9 and the
pinned MoonBit compiler. Results are in [final-review.json](evidence/final-review.json),
including every repeated run, source commit, input/output hashes, parameters and
independent topology/attribute measurements. These are fresh JS file-host processes.

## Controlled inputs and budgets

The generated model is a deterministic, uneven planar grid, with original corner
UVs and an analytic position channel. Grid side n has 2*n*n source triangles.
Target length is 1.12/n; requested iterations = 2, minimum angle = 10° and default
projection sample limit = target/4. Each setting runs three times. Repeated output
bytes must match exactly; wall time and memory need not match.

```sh
python tools/benchmark.py --sizes 32 64 128 --repeats 3
python tools/benchmark.py --sizes 128 --repeats 3 --max-operations 200000
```

The 10,000-attempt runs used clean source `cb348da`; the optional larger-budget
run used `7537cfa`, which only extends benchmark parameter handling. Product sources
and manifests are identical between these commits. One CI smoke case uses n=16;
the local larger measurements are separate evidence, not a CI speed threshold.

## Actual results

Time is the median of three complete host-process measurements. Memory is the
largest OS peak-counter value observed across the three runs (MiB = 2^20 bytes).

| Input faces | Attempt cap | Output faces | Attempts used | Completed rounds | Median seconds | Observed process peak MiB | Stop |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 2048 | 10000 | 2318 | 3659 | 2 | 0.476 | 157.4 | iteration limit |
| 8192 | 10000 | 9342 | 10000 | 2 started | 1.107 | 290.0 | operation budget |
| 32768 | 10000 | 37264 | 10000 | 1 started | 2.011 | 641.3 | operation budget |
| 32768 | 200000 | 37224 | 61961 | 2 | 5.177 | 763.8 | iteration limit |

The 32,768-face bounded run performed 2248 splits and exhausted its budget before
flip/relaxation. It is not a full remeshing-cycle result. With the larger cap, the
same input completed two requested rounds: 2404 splits, 176 collapses, 4625 flips,
36,728 accepted relaxations and 18,028 rejected candidates. The cap includes rejected
attempts, not just successful edits. Iteration-limit termination still does not
promise all edges in the target band or full convergence.

Every result passed independent topology reconstruction, Euler/component/boundary
loop preservation, original protected-chain coverage, analytic field consistency,
sampled chart UV interpolation, normal checks and reported-quality agreement.
This is a synthetic planar scale experiment; real assets and the external MeshLab
comparison have separate measurements in [REAL_MODELS.md](REAL_MODELS.md).

## Quality limits visible in these measurements

Mean Q improves, but edge-length CV worsens on these already fairly regular grids.
For the larger-budget 32,768-face case, mean Q goes 0.86249 → 0.88035, CV goes
0.18095 → 0.20784, and global minimum angle goes 39.810° → 15.274°. The latter
remains above the requested 10° floor. The original high minimum angle is not
preserved when the requested floor is lower. Pinning features and a finite budget
can prevent a uniform edge distribution. None of these results supports a claim
that every model's minimum angle or CV improves; the fixed real-asset quality gates
also cannot be generalized to arbitrary inputs.

## Measurement boundary

Times include Node startup, file reads, JSON parsing, MoonBit work and JSON output
to a file. No compilation is inside the timed section. Memory includes the host
and output serialization. The monitor observes Windows PeakWorkingSetSize (or Linux
VmHWM) every 20 ms; it may miss the final peak and is a lower bound of the OS
counter. It is not isolated algorithm allocation, private committed memory or an
RSS ceiling. OS allocation and collection choices explain run-to-run variation.
Raw per-run numbers are retained rather than replacing them with a claimed bound.

The maximum tested input here is 32,768 triangles, not the library's count ceiling.
Count limits and runtime budgets do not prove memory fit or speed for arbitrary
models at those limits. No native-vs-JS speed comparison or MeshLab speed claim is
made. Full raw input/output files are retained in the participant's local archive;
any clean clone can regenerate them with the commands above.
