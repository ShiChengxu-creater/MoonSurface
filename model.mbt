///|
/// Attribute-aware editing. Vertex ids survive until explicitly compacted.
pub struct Model {
  priv state : ModelState
}

///|
/// Detached output and sparse-to-dense maps; deleted elements map to -1.
pub(all) struct ModelSnapshot {
  mesh : Mesh
  attributes : Array[VertexAttribute]
  corner_uvs : Array[CornerUV]
  materials : Array[Int]
  feature_edges : Array[(Int, Int)]
  vertex_map : Array[Int]
  face_map : Array[Int]
}

///|
pub fn Model::new(
  mesh : Mesh,
  attributes? : Array[VertexAttribute] = [],
  corner_uvs? : Array[CornerUV] = [],
  materials? : Array[Int] = [],
  feature_edges? : Array[(Int, Int)] = [],
  sharp_angle_degrees? : Double = 45.0,
) -> Model raise SurfaceError {
  mesh.validate()
  if !finite(sharp_angle_degrees) ||
    sharp_angle_degrees <= 0.0 ||
    sharp_angle_degrees > 180.0 {
    raise InvalidArgument("sharp angle must be in (0,180]")
  }
  if attributes.length() > 16 {
    raise LimitExceeded("vertex attribute channels")
  }
  let names : Map[String, Bool] = Map([])
  for attr in attributes {
    if attr.data.length() != mesh.vertex_count() || names.contains(attr.name) {
      raise InvalidArgument("attribute length or duplicate name")
    }
    names[attr.name] = true
  }
  let nfaces = mesh.face_count()
  if (!corner_uvs.is_empty() && corner_uvs.length() != nfaces) ||
    (!materials.is_empty() && materials.length() != nfaces) {
    raise InvalidArgument("corner UV/material count")
  }
  for uv in corner_uvs {
    for p in [uv.a, uv.b, uv.c] {
      if !finite(p.x) || !finite(p.y) {
        raise InvalidArgument("non-finite UV")
      }
    }
  }
  for mat in materials {
    if mat < 0 {
      raise InvalidArgument("negative material id")
    }
  }
  let input = mesh.to_indexed()
  let mut scale = 0.0
  for p in input.vertices {
    scale = Double::max(
      scale,
      Double::max(abs(p.x), Double::max(abs(p.y), abs(p.z))),
    )
  }
  if scale == 0.0 {
    scale = 1.0
  }
  let points = input.vertices.map(fn(p) { v_div(p, scale) })
  let state = graph_new(
    points,
    attributes.map(attribute_copy),
    scale,
    mesh.limits(),
  )
  for i, (a, b, c) in input.triangles {
    if degenerate(points[a], points[b], points[c]) {
      raise NumericalFailure("model normalization lost geometry")
    }
    state.append_face({
      a,
      b,
      c,
      uv: if corner_uvs.is_empty() {
        None
      } else {
        Some(corner_uvs[i])
      },
      material: if materials.is_empty() {
        0
      } else {
        materials[i]
      },
      chart: -1,
      alive: true,
    })
  }
  let cosine = @math.cos(sharp_angle_degrees * 3.141592653589793 / 180.0)
  for key in state.edges.keys() {
    let ids = state.edges[key]
    let mut constrained = ids.length() == 1
    if ids.length() == 2 {
      let left = state.faces[ids[0]]
      let right = state.faces[ids[1]]
      constrained = left.material != right.material ||
        !uv_equal(left.corner(key.0), right.corner(key.0)) ||
        !uv_equal(left.corner(key.1), right.corner(key.1)) ||
        normal_dot(state.face_normal(left), state.face_normal(right)) <
        cosine - 1.0e-12
    }
    if constrained {
      state.constraints[key] = true
    }
  }
  for (a, b) in feature_edges {
    ignore(state.edge_faces(a, b))
    state.constraints[edge_key(a, b)] = true
  }
  // Reference patches cannot cross a protected seam or material boundary.
  for start in 0..<state.faces.length() {
    if state.faces[start].chart >= 0 {
      continue
    }
    let queue = [start]
    let mut cursor = 0
    state.faces[start] = { ..state.faces[start], chart: start, }
    while cursor < queue.length() {
      let face = state.faces[queue[cursor]]
      cursor += 1
      for (a, b) in [(face.a, face.b), (face.b, face.c), (face.c, face.a)] {
        let key = edge_key(a, b)
        if state.constraints.contains(key) {
          continue
        }
        for next in state.edges[key] {
          if state.faces[next].chart < 0 {
            state.faces[next] = { ..state.faces[next], chart: start, }
            queue.push(next)
          }
        }
      }
    }
  }
  { state, }
}

///|
fn ModelState::face_normal(self : ModelState, f : ModelFace) -> Vec3 {
  unit_face(self.points[f.a], self.points[f.b], self.points[f.c])
}

///|
pub fn Model::vertex_count(self : Model) -> Int {
  self.state.nv
}

///|
pub fn Model::face_count(self : Model) -> Int {
  self.state.nf
}

///|
pub fn Model::position(self : Model, vertex : Int) -> Vec3 raise SurfaceError {
  self.state.check_vertex(vertex)
  v_scale(self.state.points[vertex], self.state.scale)
}

///|
pub fn Model::is_protected(
  self : Model,
  a : Int,
  b : Int,
) -> Bool raise SurfaceError {
  ignore(self.state.edge_faces(a, b))
  self.state.constraints.contains(edge_key(a, b))
}

///|
pub fn Model::copy(self : Model) -> Model {
  { state: self.state.copy(), }
}

///|
pub fn Model::compact(self : Model) -> ModelSnapshot raise SurfaceError {
  let s = self.state
  let vm = Array::make(s.points.length(), -1)
  let fm = Array::make(s.faces.length(), -1)
  let points : Array[Vec3] = []
  for i, p in s.points {
    if s.alive[i] {
      vm[i] = points.length()
      points.push(v_scale(p, s.scale))
    }
  }
  let triangles : Array[(Int, Int, Int)] = []
  let uv : Array[CornerUV] = []
  let materials : Array[Int] = []
  for i, f in s.faces {
    if !f.alive {
      continue
    }
    fm[i] = triangles.length()
    triangles.push((vm[f.a], vm[f.b], vm[f.c]))
    if f.uv is Some(value) {
      uv.push(value)
    }
    materials.push(f.material)
  }
  let limits = {
    ..s.limits,
    max_input_faces: Int::max(
      s.limits.max_input_faces,
      s.limits.max_output_faces,
    ),
  }
  let mesh = Mesh::from_indexed(points, triangles, limits~)
  let final_mesh = { ..mesh, limits: s.limits, }
  let attrs = s.attributes.map(fn(attr) {
    let rows : Array[Array[Double]] = []
    for i, row in attr.data {
      if s.alive[i] {
        rows.push(row.copy())
      }
    }
    { ..attr, data: rows, }
  })
  let features : Array[(Int, Int)] = []
  for key in s.edge_list() {
    if s.constraints.contains(key) {
      features.push((vm[key.0], vm[key.1]))
    }
  }
  {
    mesh: final_mesh,
    attributes: attrs,
    corner_uvs: uv,
    materials,
    feature_edges: features,
    vertex_map: vm,
    face_map: fm,
  }
}
