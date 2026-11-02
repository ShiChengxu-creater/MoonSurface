///|
/// Each edge owns two consecutive halfedges, including the exterior one.
priv struct Halfedge {
  mut origin : Int
  mut next : Int
  mut face : Int
}

///|
/// An oriented triangle 2-manifold, possibly disconnected and with boundary.
pub struct Mesh {
  priv vertices : Array[Vec3]
  priv outgoing : Array[Int]
  priv degrees : Array[Int]
  priv halfedges : Array[Halfedge]
  priv faces : Array[Int]
  priv edge_lookup : Map[(Int, Int), Int]
  priv limits : Limits
}

///|
fn opposite(h : Int) -> Int {
  if h % 2 == 0 {
    h + 1
  } else {
    h - 1
  }
}

///|
fn edge_key(a : Int, b : Int) -> (Int, Int) {
  if a < b {
    (a, b)
  } else {
    (b, a)
  }
}

///|
/// Own input arrays and validate geometry, orientation, edges and vertex fans.
pub fn Mesh::from_indexed(
  vertices : Array[Vec3],
  triangles : Array[(Int, Int, Int)],
  limits? : Limits = Limits::default(),
) -> Mesh raise SurfaceError {
  let input = IndexedMesh::new(vertices, triangles, limits~)
  let outgoing = Array::make(vertices.length(), -1)
  let degrees = Array::make(vertices.length(), 0)
  let halfedges : Array[Halfedge] = []
  let faces : Array[Int] = []
  let lookup : Map[(Int, Int), Int] = Map([])
  for fi, (a, b, c) in input.triangles {
    let ring : Array[Int] = []
    for (u, v) in [(a, b), (b, c), (c, a)] {
      let key = edge_key(u, v)
      let base = match lookup.get(key) {
        Some(e) => e * 2
        None => {
          let base = halfedges.length()
          halfedges.push({ origin: u, next: -1, face: -1, })
          halfedges.push({ origin: v, next: -1, face: -1, })
          lookup[key] = base / 2
          base
        }
      }
      let h = if halfedges[base].origin == u { base } else { base + 1 }
      if halfedges[h].face >= 0 {
        if halfedges[opposite(h)].face >= 0 {
          raise NonManifoldEdge(key.0, key.1)
        }
        raise InconsistentOrientation(key.0, key.1)
      }
      halfedges[h].face = fi
      outgoing[u] = h
      degrees[u] += 1
      ring.push(h)
    }
    halfedges[ring[0]].next = ring[1]
    halfedges[ring[1]].next = ring[2]
    halfedges[ring[2]].next = ring[0]
    faces.push(ring[0])
  }
  let boundary_out = Array::make(vertices.length(), -1)
  for h, halfedge in halfedges {
    if halfedge.face < 0 {
      let u = halfedge.origin
      if boundary_out[u] >= 0 {
        raise NonManifoldVertex(u)
      }
      boundary_out[u] = h
      outgoing[u] = h
      degrees[u] += 1
    }
  }
  for h, halfedge in halfedges {
    if halfedge.face < 0 {
      let v = halfedges[opposite(h)].origin
      if boundary_out[v] < 0 {
        raise NonManifoldVertex(v)
      }
      halfedge.next = boundary_out[v]
    }
  }
  // A single closed orbit is required even at a closed bow-tie vertex.
  for v, start in outgoing {
    let mut h = start
    let mut count = 0
    while true {
      count += 1
      h = halfedges[opposite(h)].next
      if h == start {
        break
      }
      if count >= degrees[v] {
        raise NonManifoldVertex(v)
      }
    }
    if count != degrees[v] {
      raise NonManifoldVertex(v)
    }
  }
  {
    vertices: input.vertices,
    outgoing,
    degrees,
    halfedges,
    faces,
    edge_lookup: lookup,
    limits,
  }
}

///|
/// Number of vertices, including all boundary vertices.
pub fn Mesh::vertex_count(self : Mesh) -> Int {
  self.vertices.length()
}

///|
/// Number of undirected edges, including boundary edges.
pub fn Mesh::edge_count(self : Mesh) -> Int {
  self.halfedges.length() / 2
}

///|
/// Number of real triangular faces (exterior loops are not faces).
pub fn Mesh::face_count(self : Mesh) -> Int {
  self.faces.length()
}

///|
/// The mesh's count budgets.
pub fn Mesh::limits(self : Mesh) -> Limits {
  self.limits
}

///|
/// Read a vertex position. Vec3 contains no mutable storage.
pub fn Mesh::position(self : Mesh, vertex : Int) -> Vec3 raise SurfaceError {
  if vertex < 0 || vertex >= self.vertices.length() {
    raise InvalidElement(vertex)
  }
  self.vertices[vertex]
}

///|
/// Find an undirected edge. Nonexistent or invalid vertex pairs return None.
pub fn Mesh::find_edge(self : Mesh, a : Int, b : Int) -> EdgeId? {
  self.edge_lookup.get(edge_key(a, b)).map(fn(e) { EdgeId(e) })
}

///|
/// Return endpoints; the pair's order is stable until this edge is flipped.
pub fn Mesh::edge_vertices(
  self : Mesh,
  edge : EdgeId,
) -> (Int, Int) raise SurfaceError {
  let EdgeId(e) = edge
  if e < 0 || e >= self.edge_count() {
    raise InvalidElement(e)
  }
  (self.halfedges[2 * e].origin, self.halfedges[2 * e + 1].origin)
}

///|
/// Ordered one-ring neighbors; exterior halfedges close open vertex fans.
pub fn Mesh::neighbors(
  self : Mesh,
  vertex : Int,
) -> Array[Int] raise SurfaceError {
  if vertex < 0 || vertex >= self.vertices.length() {
    raise InvalidElement(vertex)
  }
  let result : Array[Int] = []
  let mut h = self.outgoing[vertex]
  for _ in 0..<self.degrees[vertex] {
    result.push(self.halfedges[opposite(h)].origin)
    h = self.halfedges[opposite(h)].next
  }
  result
}
