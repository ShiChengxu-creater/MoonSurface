///|
/// A flip keeps edge and face ids, replacing the diagonal's endpoints.
pub(all) struct FlipReport {
  edge : EdgeId
  endpoints : (Int, Int)
  faces : (Int, Int)
} derive(Debug)

///|
pub extend FlipReport with @debug.Debug::{to_repr}

///|
/// Flip a non-boundary diagonal only if topology and both local face orientations survive.
pub fn Mesh::flip_edge(
  self : Mesh,
  edge : EdgeId,
) -> FlipReport raise SurfaceError {
  let (u, v) = self.edge_vertices(edge)
  let EdgeId(e) = edge
  let h = 2 * e
  let t = h + 1
  let lf = self.halfedges[h].face
  let rf = self.halfedges[t].face
  if lf < 0 || rf < 0 {
    raise BoundaryEdge(e)
  }
  let ln = self.halfedges[h].next
  let lp = self.halfedges[ln].next
  let rn = self.halfedges[t].next
  let rp = self.halfedges[rn].next
  let w = self.halfedges[lp].origin
  let x = self.halfedges[rp].origin
  if self.edge_lookup.contains(edge_key(w, x)) {
    raise DuplicateDiagonal(w, x)
  }
  let pu = self.vertices[u]
  let pv = self.vertices[v]
  let pw = self.vertices[w]
  let px = self.vertices[x]
  if degenerate(pw, px, pv) ||
    degenerate(px, pw, pu) ||
    normal_dot(unit_face(pu, pv, pw), unit_face(pw, px, pv)) <= 1.0e-12 ||
    normal_dot(unit_face(pv, pu, px), unit_face(px, pw, pu)) <= 1.0e-12 {
    raise NumericalFailure("flip would degenerate or invert a local face")
  }
  self.halfedges[h].origin = w
  self.halfedges[t].origin = x
  self.set_triangle(lf, h, rp, ln)
  self.set_triangle(rf, t, lp, rn)
  self.outgoing[u] = rn
  self.outgoing[v] = ln
  self.degrees[u] -= 1
  self.degrees[v] -= 1
  self.degrees[w] += 1
  self.degrees[x] += 1
  self.edge_lookup.remove(edge_key(u, v))
  self.edge_lookup[edge_key(w, x)] = e
  { edge, endpoints: (w, x), faces: (lf, rf), }
}

///|
/// Unit normal computed after coordinate and edge scaling to avoid over/underflow.
fn unit_face(a : Vec3, b : Vec3, c : Vec3) -> Vec3 {
  let mut scale = 0.0
  for p in [a, b, c] {
    scale = Double::max(
      scale,
      Double::max(abs(p.x), Double::max(abs(p.y), abs(p.z))),
    )
  }
  if scale == 0.0 {
    return { x: 0.0, y: 0.0, z: 0.0, }
  }
  let u = Vec3::{
    x: b.x / scale - a.x / scale,
    y: b.y / scale - a.y / scale,
    z: b.z / scale - a.z / scale,
  }
  let v = Vec3::{
    x: c.x / scale - a.x / scale,
    y: c.y / scale - a.y / scale,
    z: c.z / scale - a.z / scale,
  }
  let edge_scale = Double::max(
    Double::max(abs(u.x), Double::max(abs(u.y), abs(u.z))),
    Double::max(abs(v.x), Double::max(abs(v.y), abs(v.z))),
  )
  if edge_scale == 0.0 {
    return { x: 0.0, y: 0.0, z: 0.0, }
  }
  let (ux, uy, uz) = (u.x / edge_scale, u.y / edge_scale, u.z / edge_scale)
  let (vx, vy, vz) = (v.x / edge_scale, v.y / edge_scale, v.z / edge_scale)
  let n = Vec3::{
    x: uy * vz - uz * vy,
    y: uz * vx - ux * vz,
    z: ux * vy - uy * vx,
  }
  let length = (n.x * n.x + n.y * n.y + n.z * n.z).sqrt()
  if length == 0.0 {
    return { x: 0.0, y: 0.0, z: 0.0, }
  }
  { x: n.x / length, y: n.y / length, z: n.z / length, }
}

///|
fn normal_dot(a : Vec3, b : Vec3) -> Double {
  a.x * b.x + a.y * b.y + a.z * b.z
}
