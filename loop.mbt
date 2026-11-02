///| One uniform Loop step, using the old mesh for every stencil.

///|
/// The result owns new storage and retains the original mesh's configured limits.
pub fn Mesh::loop_step(self : Mesh) -> Mesh raise SurfaceError {
  if self.limits.max_levels < 1 {
    raise LimitExceeded("Loop levels")
  }
  let count = self.vertex_count() + self.edge_count()
  if count > self.limits.max_vertices {
    raise LimitExceeded("Loop vertices")
  }
  if self.face_count() * 4 > self.limits.max_output_faces {
    raise LimitExceeded("Loop faces")
  }
  let boundary : Array[(Int, Int)?] = Array::make(self.vertex_count(), None)
  for ring in self.boundary_loops() {
    let n = ring.length()
    for i, v in ring {
      boundary[v] = Some((ring[(i + n - 1) % n], ring[(i + 1) % n]))
    }
  }
  let positions : Array[Vec3] = []
  for v in 0..<self.vertex_count() {
    let stencil = match boundary[v] {
      Some((a, b)) => [(v, 0.75), (a, 0.125), (b, 0.125)]
      None => {
        let n = self.degrees[v]
        let c = 0.375 + 0.25 * @math.cos(6.283185307179586 / n.to_double())
        let beta = (0.625 - c * c) / n.to_double()
        let entries = [(v, 1.0 - n.to_double() * beta)]
        for other in self.neighbors(v) {
          entries.push((other, beta))
        }
        entries
      }
    }
    positions.push(weighted_position(self.vertices, stencil))
  }
  for e in 0..<self.edge_count() {
    let h = 2 * e
    let t = h + 1
    let u = self.halfedges[h].origin
    let v = self.halfedges[t].origin
    let stencil = if self.halfedges[h].face < 0 || self.halfedges[t].face < 0 {
      [(u, 0.5), (v, 0.5)]
    } else {
      let a = self.halfedges[self.halfedges[self.halfedges[h].next].next].origin
      let b = self.halfedges[self.halfedges[self.halfedges[t].next].next].origin
      [(u, 0.375), (v, 0.375), (a, 0.125), (b, 0.125)]
    }
    positions.push(weighted_position(self.vertices, stencil))
  }
  let triangles : Array[(Int, Int, Int)] = []
  let offset = self.vertex_count()
  for h in self.faces {
    let a = self.halfedges[h].origin
    let b = self.halfedges[self.halfedges[h].next].origin
    let c = self.halfedges[self.halfedges[self.halfedges[h].next].next].origin
    let ab = offset + self.edge_lookup[edge_key(a, b)]
    let bc = offset + self.edge_lookup[edge_key(b, c)]
    let ca = offset + self.edge_lookup[edge_key(c, a)]
    triangles.push((a, ab, ca))
    triangles.push((b, bc, ab))
    triangles.push((c, ca, bc))
    triangles.push((ab, bc, ca))
  }
  let temporary_limits = {
    ..self.limits,
    max_input_faces: self.limits.max_output_faces,
  }
  let result = Mesh::from_indexed(positions, triangles, limits=temporary_limits)
  { ..result, limits: self.limits, }
}

///|
/// Positive Loop weights form convex combinations. Normalize before summation.
fn weighted_position(
  points : Array[Vec3],
  stencil : Array[(Int, Double)],
) -> Vec3 {
  let mut scale = 0.0
  for (v, _) in stencil {
    let p = points[v]
    scale = Double::max(
      scale,
      Double::max(abs(p.x), Double::max(abs(p.y), abs(p.z))),
    )
  }
  if scale == 0.0 {
    return { x: 0.0, y: 0.0, z: 0.0, }
  }
  let mut x = 0.0
  let mut y = 0.0
  let mut z = 0.0
  for (v, weight) in stencil {
    x += points[v].x / scale * weight
    y += points[v].y / scale * weight
    z += points[v].z / scale * weight
  }
  // Roundoff cannot move a convex combination beyond the input coordinate bound.
  {
    x: Double::max(-1.0, Double::min(1.0, x)) * scale,
    y: Double::max(-1.0, Double::min(1.0, y)) * scale,
    z: Double::max(-1.0, Double::min(1.0, z)) * scale,
  }
}
