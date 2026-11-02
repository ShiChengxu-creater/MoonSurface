///|
/// New ids and the retained original edge after a local edge split.
pub(all) struct SplitReport {
  vertex : Int
  retained_edge : EdgeId
  created_edges : Array[EdgeId]
  created_faces : Array[Int]
} derive(Debug)

///|
pub extend SplitReport with @debug.Debug::{to_repr}

///| Split an edge; fraction is measured from edge_vertices().0 towards .1.

///|
/// All recoverable errors occur before mutation. Other element ids are retained.
pub fn Mesh::split_edge(
  self : Mesh,
  edge : EdgeId,
  fraction? : Double = 0.5,
) -> SplitReport raise SurfaceError {
  let (a, b) = self.edge_vertices(edge)
  if !finite(fraction) || fraction <= 0.0 || fraction >= 1.0 {
    raise InvalidArgument(
      "split fraction must be strictly between zero and one",
    )
  }
  let EdgeId(e) = edge
  let h = if self.halfedges[2 * e].face >= 0 { 2 * e } else { 2 * e + 1 }
  let t = opposite(h)
  let boundary = self.halfedges[t].face < 0
  let added_faces = if boundary { 1 } else { 2 }
  if self.vertex_count() >= self.limits.max_vertices {
    raise LimitExceeded("split vertices")
  }
  if self.face_count() + added_faces > self.limits.max_output_faces {
    raise LimitExceeded("split faces")
  }
  let p = Vec3::{
    x: lerp_scalar(self.vertices[a].x, self.vertices[b].x, fraction),
    y: lerp_scalar(self.vertices[a].y, self.vertices[b].y, fraction),
    z: lerp_scalar(self.vertices[a].z, self.vertices[b].z, fraction),
  }
  let u = self.halfedges[h].origin
  let v = self.halfedges[t].origin
  let ln = self.halfedges[h].next
  let lp = self.halfedges[ln].next
  let w = self.halfedges[lp].origin
  if !finite(p.x) ||
    !finite(p.y) ||
    !finite(p.z) ||
    degenerate(self.vertices[u], p, self.vertices[w]) ||
    degenerate(p, self.vertices[v], self.vertices[w]) {
    raise NumericalFailure("split would create degenerate geometry")
  }
  let rn = self.halfedges[t].next
  let rp = self.halfedges[rn].next
  let x = if boundary { -1 } else { self.halfedges[rp].origin }
  if !boundary &&
    (
      degenerate(p, self.vertices[u], self.vertices[x]) ||
      degenerate(self.vertices[v], p, self.vertices[x])
    ) {
    raise NumericalFailure("split would create degenerate geometry")
  }
  let mut boundary_prev = -1
  if boundary {
    let mut current = ln
    for _ in 0..<self.degrees[v] {
      let incoming = opposite(current)
      if self.halfedges[incoming].face < 0 {
        boundary_prev = incoming
        break
      }
      current = self.halfedges[incoming].next
    }
    if boundary_prev < 0 {
      raise TopologyInvariant("missing exterior predecessor")
    }
  }
  let lf = self.halfedges[h].face
  let rf = self.halfedges[t].face
  let m = self.vertices.length()
  // No fallible validation remains below this point.
  self.vertices.push(p)
  self.outgoing.push(t)
  self.degrees.push(if boundary { 3 } else { 4 })
  let mv = self.append_edge(m, v)
  let mw = self.append_edge(m, w)
  let new_left = self.faces.length()
  self.faces.push(-1)
  self.halfedges[t].origin = m
  self.set_triangle(lf, h, mw, lp)
  self.set_triangle(new_left, mv, ln, opposite(mw))
  self.degrees[w] += 1
  let created_edges = [EdgeId(mv / 2), EdgeId(mw / 2)]
  let created_faces = [new_left]
  if boundary {
    self.halfedges[boundary_prev].next = opposite(mv)
    self.halfedges[opposite(mv)].next = t
  } else {
    let mx = self.append_edge(m, x)
    let new_right = self.faces.length()
    self.faces.push(-1)
    self.set_triangle(rf, t, rn, opposite(mx))
    self.set_triangle(new_right, opposite(mv), mx, rp)
    self.degrees[x] += 1
    created_edges.push(EdgeId(mx / 2))
    created_faces.push(new_right)
  }
  self.outgoing[v] = opposite(mv)
  self.edge_lookup.remove(edge_key(u, v))
  self.edge_lookup[edge_key(u, m)] = e
  { vertex: m, retained_edge: edge, created_edges, created_faces, }
}

///|
fn lerp_scalar(a : Double, b : Double, t : Double) -> Double {
  if (a >= 0.0 && b >= 0.0) || (a <= 0.0 && b <= 0.0) {
    a + (b - a) * t
  } else {
    (1.0 - t) * a + t * b
  }
}

///|
fn Mesh::append_edge(self : Mesh, a : Int, b : Int) -> Int {
  let h = self.halfedges.length()
  self.halfedges.push({ origin: a, next: -1, face: -1, })
  self.halfedges.push({ origin: b, next: -1, face: -1, })
  self.edge_lookup[edge_key(a, b)] = h / 2
  h
}

///|
fn Mesh::set_triangle(
  self : Mesh,
  face : Int,
  a : Int,
  b : Int,
  c : Int,
) -> Unit {
  self.faces[face] = a
  for (h, next) in [(a, b), (b, c), (c, a)] {
    self.halfedges[h].face = face
    self.halfedges[h].next = next
  }
}
