# Changes

## 0.2.1 — performance update

- Keep the public API and remeshing policy compatible with 0.2.0.
- Store only owned projection geometry/channels and live triangles, rather than cloning the editable topology graph and witnesses.
- Build a deterministic BVH per constraint-separated reference patch.
- Skip graph/reference setup for validated zero-budget, zero-iteration or empty requests while preserving report/validation behavior.
- Add patch isolation, reference ownership, retired-face and no-work regression checks (50 core tests per target).
- Compare five real/synthetic tasks against an exact 0.2.0 archive: byte-identical outputs, paired host timing and observed process-memory measurements.
- Add Linux/Windows CI smoke checks for output-preserving optimization; publication proof remains version-specific in REGISTRY_RELEASE.

## 0.2.0 — published 2026-11-16

- Preserve the 0.2 alpha product API; freeze the attributed/feature remeshing scope.
- Add 480 seeded edit attempts with topology, UV, analytic field and failure rollback checks.
- Cover repeated compact/reimport, explicit coplanar tags, empty/zero work and invalid budgets.
- Exercise similarity transforms, deterministic file output and 21 invalid model jobs.
- Add reproducible bounded scale/host-memory measurements and CI smoke coverage.
- Correct 0.2 alpha registry publication records and document final-review reproduction.
- QEM, skinning/morphs/multiple UV sets and global intersection guarantees remain outside scope.

## 0.2.0-alpha.1 — published 2026-11-11

- Owned numeric vertex channels, corner UV/material transfer and feature-aware normals.
- Model local split/flip/collapse, removed-id guards and compact maps.
- Sharp/boundary/seam/material/discrete constraints inherited by split.
- Isotropic remeshing, BVH projection, patch-aware attribute sampling, angle floor,
  surface witnesses and explicit budget/refusal reports.
- Real CC0 Avocado/Suzanne data, independent NumPy measurement and optional pinned
  MeshLab geometry comparison. Original Mesh/Loop interfaces remain; QEM is pending.

## 0.1.0-alpha.1 — published 2026-11-04

Checked Mesh, split/flip, geometry Loop, normals, CLI, two examples,
three-backend tests and source/ZIP/registry consumer evidence.
