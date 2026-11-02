///|
/// Real face/edge counts. Exterior loops are reported separately.
pub(all) struct TopologyStats {
  vertices : Int
  edges : Int
  faces : Int
  boundary_edges : Int
  boundary_loops : Int
  components : Int
  euler : Int
} derive(Eq, Debug)

///|
pub extend TopologyStats with Eq::{equal, not_equal}

///|
pub extend TopologyStats with @debug.Debug::{to_repr}

///|
/// Export independent storage. Positions and triangle indices retain their ids.
pub fn Mesh::to_indexed(self : Mesh) -> IndexedMesh {
  let triangles = self.faces.map(fn(h) {
    (
      self.halfedges[h].origin,
      self.halfedges[self.halfedges[h].next].origin,
      self.halfedges[self.halfedges[self.halfedges[h].next].next].origin,
    )
  })
  { vertices: self.vertices.copy(), triangles, }
}

///|
/// Is this undirected edge adjacent to an exterior halfedge?
pub fn Mesh::is_boundary_edge(
  self : Mesh,
  edge : EdgeId,
) -> Bool raise SurfaceError {
  let EdgeId(e) = edge
  ignore(self.edge_vertices(edge))
  self.halfedges[2 * e].face < 0 || self.halfedges[2 * e + 1].face < 0
}

///|
/// Exterior-oriented loops, without a repeated endpoint, ordered by halfedge id.
pub fn Mesh::boundary_loops(self : Mesh) -> Array[Array[Int]] {
  let visited = Array::make(self.halfedges.length(), false)
  let loops : Array[Array[Int]] = []
  for start, he in self.halfedges {
    if he.face >= 0 || visited[start] {
      continue
    }
    let ring : Array[Int] = []
    let mut h = start
    while !visited[h] {
      visited[h] = true
      ring.push(self.halfedges[h].origin)
      h = self.halfedges[h].next
    }
    loops.push(ring)
  }
  loops
}

///|
/// Count connected components and boundary loops; Euler is summed over components.
pub fn Mesh::stats(self : Mesh) -> TopologyStats {
  let visited = Array::make(self.vertices.length(), false)
  let mut components = 0
  for start in 0..<self.vertices.length() {
    if visited[start] {
      continue
    }
    components += 1
    let queue = [start]
    visited[start] = true
    let mut cursor = 0
    while cursor < queue.length() {
      let vertex = queue[cursor]
      cursor += 1
      let mut h = self.outgoing[vertex]
      for _ in 0..<self.degrees[vertex] {
        let other = self.halfedges[opposite(h)].origin
        if !visited[other] {
          visited[other] = true
          queue.push(other)
        }
        h = self.halfedges[opposite(h)].next
      }
    }
  }
  let mut boundary_edges = 0
  for he in self.halfedges {
    if he.face < 0 {
      boundary_edges += 1
    }
  }
  {
    vertices: self.vertex_count(),
    edges: self.edge_count(),
    faces: self.face_count(),
    boundary_edges,
    boundary_loops: self.boundary_loops().length(),
    components,
    euler: self.vertex_count() - self.edge_count() + self.face_count(),
  }
}

///|
/// Explicit O(V+E+F) audit. Intended for debug/validation, not every hot-path query.
pub fn Mesh::validate(self : Mesh) -> Unit raise SurfaceError {
  let n = self.vertices.length()
  let nh = self.halfedges.length()
  if nh % 2 != 0 ||
    self.outgoing.length() != n ||
    self.degrees.length() != n ||
    self.edge_lookup.length() != nh / 2 {
    raise TopologyInvariant("array counts")
  }
  let degrees = Array::make(n, 0)
  for he in self.halfedges {
    if he.origin < 0 ||
      he.origin >= n ||
      he.next < 0 ||
      he.next >= nh ||
      he.face < -1 ||
      he.face >= self.faces.length() {
      raise TopologyInvariant("halfedge range")
    }
    degrees[he.origin] += 1
  }
  let covered = Array::make(nh, false)
  for f, start in self.faces {
    if start < 0 || start >= nh {
      raise TopologyInvariant("face range")
    }
    let mut h = start
    for _ in 0..<3 {
      if covered[h] || self.halfedges[h].face != f {
        raise TopologyInvariant("face ownership")
      }
      covered[h] = true
      h = self.halfedges[h].next
    }
    if h != start {
      raise TopologyInvariant("triangle cycle")
    }
  }
  for h, he in self.halfedges {
    let other = self.halfedges[opposite(h)]
    if he.origin == other.origin ||
      self.halfedges[he.next].origin != other.origin ||
      (he.face >= 0 && !covered[h]) ||
      (he.face < 0 && self.halfedges[he.next].face >= 0) {
      raise TopologyInvariant("halfedge connectivity")
    }
    if self.edge_lookup.get(edge_key(he.origin, other.origin)) != Some(h / 2) {
      raise TopologyInvariant("edge lookup")
    }
  }
  for v, start in self.outgoing {
    if start < 0 || start >= nh || degrees[v] != self.degrees[v] {
      raise TopologyInvariant("vertex incidence")
    }
    let mut h = start
    for i in 0..<degrees[v] {
      if self.halfedges[h].origin != v || (i > 0 && h == start) {
        raise TopologyInvariant("vertex fan")
      }
      h = self.halfedges[opposite(h)].next
    }
    if h != start {
      raise TopologyInvariant("vertex closure")
    }
  }
  let indexed = self.to_indexed()
  let limits = {
    ..self.limits,
    max_input_faces: Int::max(
      self.limits.max_input_faces,
      self.limits.max_output_faces,
    ),
  }
  ignore(IndexedMesh::new(indexed.vertices, indexed.triangles, limits~))
}
