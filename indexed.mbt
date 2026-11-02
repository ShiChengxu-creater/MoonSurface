///|
/// Geometry-validated indexed triangles; manifold validation is done by Mesh.
pub struct IndexedMesh {
  vertices : Array[Vec3]
  triangles : Array[(Int, Int, Int)]
} derive(Eq, Debug)

///|
/// Validate before copying. Returned data never aliases the supplied arrays.
pub fn IndexedMesh::new(
  vertices : Array[Vec3],
  triangles : Array[(Int, Int, Int)],
  limits? : Limits = Limits::default(),
) -> IndexedMesh raise SurfaceError {
  if vertices.length() > limits.max_vertices {
    raise LimitExceeded("input vertices")
  }
  if triangles.length() > limits.max_input_faces {
    raise LimitExceeded("input faces")
  }
  for i, p in vertices {
    if !finite(p.x) || !finite(p.y) || !finite(p.z) {
      raise NonFiniteCoordinate(i)
    }
  }
  let referenced = Array::make(vertices.length(), false)
  let seen : Map[(Int, Int, Int), Bool] = Map([])
  for fi, (a, b, c) in triangles {
    for v in [a, b, c] {
      if v < 0 || v >= vertices.length() {
        raise InvalidIndex(fi, v)
      }
      referenced[v] = true
    }
    if a == b ||
      b == c ||
      c == a ||
      degenerate(vertices[a], vertices[b], vertices[c]) {
      raise DegenerateFace(fi)
    }
    let key = face_key(a, b, c)
    if seen.contains(key) {
      raise DuplicateFace(fi)
    }
    seen[key] = true
  }
  for v, used in referenced {
    if !used {
      raise IsolatedVertex(v)
    }
  }
  { vertices: vertices.copy(), triangles: triangles.copy(), }
}

///|
/// A copy of the owned positions.
pub fn IndexedMesh::positions(self : IndexedMesh) -> Array[Vec3] {
  self.vertices.copy()
}

///|
/// A copy of the owned triangle index triples.
pub fn IndexedMesh::faces(self : IndexedMesh) -> Array[(Int, Int, Int)] {
  self.triangles.copy()
}

///|
pub extend IndexedMesh with Eq::{equal, not_equal}

///|
pub extend IndexedMesh with @debug.Debug::{to_repr}

///|
fn finite(x : Double) -> Bool {
  !x.is_nan() && !x.is_inf()
}

///|
fn abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
fn face_key(a : Int, b : Int, c : Int) -> (Int, Int, Int) {
  let lo = Int::min(a, Int::min(b, c))
  let hi = Int::max(a, Int::max(b, c))
  (lo, a + b + c - lo - hi, hi)
}

///|
/// Scale before subtraction/cross products, including near Double's extremes.
fn degenerate(a : Vec3, b : Vec3, c : Vec3) -> Bool {
  let mut scale = 0.0
  for p in [a, b, c] {
    scale = Double::max(
      scale,
      Double::max(abs(p.x), Double::max(abs(p.y), abs(p.z))),
    )
  }
  if scale == 0.0 {
    return true
  }
  let ux = b.x / scale - a.x / scale
  let uy = b.y / scale - a.y / scale
  let uz = b.z / scale - a.z / scale
  let vx = c.x / scale - a.x / scale
  let vy = c.y / scale - a.y / scale
  let vz = c.z / scale - a.z / scale
  let edge_scale = Double::max(
    Double::max(abs(ux), Double::max(abs(uy), abs(uz))),
    Double::max(abs(vx), Double::max(abs(vy), abs(vz))),
  )
  if edge_scale == 0.0 {
    return true
  }
  let (ux, uy, uz) = (ux / edge_scale, uy / edge_scale, uz / edge_scale)
  let (vx, vy, vz) = (vx / edge_scale, vy / edge_scale, vz / edge_scale)
  let (nx, ny, nz) = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
  let longest_sq = Double::max(
    ux * ux + uy * uy + uz * uz,
    Double::max(
      vx * vx + vy * vy + vz * vz,
      (ux - vx) * (ux - vx) + (uy - vy) * (uy - vy) + (uz - vz) * (uz - vz),
    ),
  )
  nx * nx + ny * ny + nz * nz <= 1.0e-28 * longest_sq * longest_sq
}
