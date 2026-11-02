///|
/// Output plus count snapshots (including level zero) taken before return.
pub(all) struct LoopResult {
  mesh : Mesh
  stages : Array[TopologyStats]
}

///|
/// Preflight every level before allocating new geometry, including open surfaces.
pub fn Mesh::plan_loop(
  self : Mesh,
  levels : Int,
) -> Array[TopologyStats] raise SurfaceError {
  if levels < 0 {
    raise InvalidArgument("Loop levels must be nonnegative")
  }
  if levels > self.limits.max_levels {
    raise LimitExceeded("Loop levels")
  }
  if self.face_count() > self.limits.max_output_faces {
    raise LimitExceeded("Loop faces")
  }
  let stages = [self.stats()]
  for _ in 0..<levels {
    let previous = stages[stages.length() - 1]
    let vertices = previous.vertices + previous.edges
    let faces = previous.faces * 4
    // Hard construction ceilings imply these additions cannot overflow Int.
    if vertices > self.limits.max_vertices {
      raise LimitExceeded("Loop vertices")
    }
    if faces > self.limits.max_output_faces {
      raise LimitExceeded("Loop faces")
    }
    stages.push({
      ..previous,
      vertices,
      faces,
      edges: previous.edges * 2 + previous.faces * 3,
      boundary_edges: previous.boundary_edges * 2,
    })
  }
  stages
}

///|
/// A detached copy, including geometry, connectivity and unchanged resource policy.
pub fn Mesh::copy(self : Mesh) -> Mesh raise SurfaceError {
  let indexed = self.to_indexed()
  let limits = {
    ..self.limits,
    max_input_faces: Int::max(self.face_count(), self.limits.max_input_faces),
  }
  let mesh = Mesh::from_indexed(indexed.vertices, indexed.triangles, limits~)
  { ..mesh, limits: self.limits, }
}

///| Uniform original Loop subdivision. The input is unchanged even on failure.

///|
/// Level zero also returns a detached mesh, rather than an alias of the input.
pub fn subdivide_loop(
  mesh : Mesh,
  levels : Int,
) -> LoopResult raise SurfaceError {
  let stages = mesh.plan_loop(levels)
  let mut result = mesh
  if levels == 0 {
    result = mesh.copy()
  }
  for _ in 0..<levels {
    result = result.loop_step()
  }
  { mesh: result, stages, }
}
