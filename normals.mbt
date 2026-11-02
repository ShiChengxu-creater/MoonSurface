///|
/// Unit face normals in exported face order. No source attributes are retained.
pub fn Mesh::face_normals(self : Mesh) -> Array[Vec3] {
  self.faces.map(fn(h) {
    unit_face(
      self.vertices[self.halfedges[h].origin],
      self.vertices[self.halfedges[self.halfedges[h].next].origin],
      self.vertices[self.halfedges[self.halfedges[self.halfedges[h].next].next].origin],
    )
  })
}

///| Area-weighted unit vertex normals. An exactly cancelling fan raises, never NaN.

///|
/// Scaling is per vertex star, so disconnected components may use different units.
pub fn Mesh::vertex_normals(self : Mesh) -> Array[Vec3] raise SurfaceError {
  let result : Array[Vec3] = []
  for v, p in self.vertices {
    let neighbors = self.neighbors(v)
    let mut scale = Double::max(abs(p.x), Double::max(abs(p.y), abs(p.z)))
    for n in neighbors {
      let q = self.vertices[n]
      scale = Double::max(
        scale,
        Double::max(abs(q.x), Double::max(abs(q.y), abs(q.z))),
      )
    }
    let mut edge_scale = 0.0
    for n in neighbors {
      let q = self.vertices[n]
      edge_scale = Double::max(
        edge_scale,
        Double::max(
          abs(q.x / scale - p.x / scale),
          Double::max(
            abs(q.y / scale - p.y / scale),
            abs(q.z / scale - p.z / scale),
          ),
        ),
      )
    }
    let mut nx = 0.0
    let mut ny = 0.0
    let mut nz = 0.0
    let mut h = self.outgoing[v]
    for _ in 0..<self.degrees[v] {
      if self.halfedges[h].face >= 0 {
        let q = self.vertices[self.halfedges[opposite(h)].origin]
        let r = self.vertices[self.halfedges[self.halfedges[self.halfedges[h].next].next].origin]
        let (ux, uy, uz) = (
          (q.x / scale - p.x / scale) / edge_scale,
          (q.y / scale - p.y / scale) / edge_scale,
          (q.z / scale - p.z / scale) / edge_scale,
        )
        let (vx, vy, vz) = (
          (r.x / scale - p.x / scale) / edge_scale,
          (r.y / scale - p.y / scale) / edge_scale,
          (r.z / scale - p.z / scale) / edge_scale,
        )
        nx += uy * vz - uz * vy
        ny += uz * vx - ux * vz
        nz += ux * vy - uy * vx
      }
      h = self.halfedges[opposite(h)].next
    }
    let normal_scale = Double::max(abs(nx), Double::max(abs(ny), abs(nz)))
    if normal_scale == 0.0 || !finite(normal_scale) {
      raise NumericalFailure("undefined area-weighted normal at vertex \{v}")
    }
    let (x, y, z) = (nx / normal_scale, ny / normal_scale, nz / normal_scale)
    let length = (x * x + y * y + z * z).sqrt()
    result.push({ x: x / length, y: y / length, z: z / length, })
  }
  result
}
