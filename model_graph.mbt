///|
/// Sparse local face graph for deletion-capable model edits.
priv struct ModelFace {
  a : Int
  b : Int
  c : Int
  uv : CornerUV?
  material : Int
  chart : Int
  alive : Bool
  witnesses : Array[Vec3]
}

///|
priv struct ModelState {
  points : Array[Vec3]
  alive : Array[Bool]
  faces : Array[ModelFace]
  incident : Array[Array[Int]]
  edges : Map[(Int, Int), Array[Int]]
  lookup : Map[(Int, Int, Int), Int]
  constraints : Map[(Int, Int), Bool]
  attributes : Array[VertexAttribute]
  scale : Double
  origin : Vec3
  limits : Limits
  mut nv : Int
  mut nf : Int
  mut angle_floor : Double
  mut projection_guard : ReferenceSurface?
  mut deviation_limit : Double
}

///|
fn ModelFace::vertices(self : ModelFace) -> Array[Int] {
  [self.a, self.b, self.c]
}

///|
fn ModelFace::corner(self : ModelFace, vertex : Int) -> Vec2 {
  match self.uv {
    Some(uv) =>
      if vertex == self.a {
        uv.a
      } else if vertex == self.b {
        uv.b
      } else {
        uv.c
      }
    None => { x: 0.0, y: 0.0, }
  }
}

///|
fn graph_new(
  points : Array[Vec3],
  attributes : Array[VertexAttribute],
  scale : Double,
  limits : Limits,
  origin? : Vec3 = { x: 0.0, y: 0.0, z: 0.0, },
) -> ModelState {
  let incident : Array[Array[Int]] = []
  for _ in points {
    incident.push([])
  }
  {
    points,
    attributes,
    scale,
    origin,
    limits,
    faces: [],
    alive: Array::make(points.length(), true),
    incident,
    edges: Map([]),
    lookup: Map([]),
    constraints: Map([]),
    nv: points.length(),
    nf: 0,
    angle_floor: 0.0,
    projection_guard: None,
    deviation_limit: 0.0,
  }
}

///|
fn ModelState::attach(self : ModelState, id : Int) -> Unit {
  let f = self.faces[id]
  for v in f.vertices() {
    self.incident[v].push(id)
  }
  for (a, b) in [(f.a, f.b), (f.b, f.c), (f.c, f.a)] {
    let key = edge_key(a, b)
    match self.edges.get(key) {
      Some(ids) => ids.push(id)
      None => self.edges[key] = [id]
    }
  }
  self.lookup[face_key(f.a, f.b, f.c)] = id
  self.nf += 1
}

///|
fn erase_id(ids : Array[Int], value : Int) -> Unit {
  for i in 0..<ids.length() {
    if ids[i] == value {
      ids.remove(i) |> ignore
      return
    }
  }
}

///|
fn ModelState::detach(self : ModelState, id : Int) -> Unit {
  let f = self.faces[id]
  for v in f.vertices() {
    erase_id(self.incident[v], id)
  }
  for (a, b) in [(f.a, f.b), (f.b, f.c), (f.c, f.a)] {
    let key = edge_key(a, b)
    let ids = self.edges[key]
    erase_id(ids, id)
    if ids.is_empty() {
      self.edges.remove(key)
    }
  }
  self.lookup.remove(face_key(f.a, f.b, f.c))
  self.faces[id] = { ..f, alive: false, witnesses: [], }
  self.nf -= 1
}

///|
fn ModelState::append_face(self : ModelState, f : ModelFace) -> Unit {
  let id = self.faces.length()
  self.faces.push({ ..f, alive: true, })
  self.attach(id)
}

///|
fn ModelState::check_vertex(
  self : ModelState,
  v : Int,
) -> Unit raise SurfaceError {
  if v < 0 || v >= self.points.length() || !self.alive[v] {
    raise InvalidElement(v)
  }
}

///|
fn ModelState::edge_faces(
  self : ModelState,
  a : Int,
  b : Int,
) -> Array[Int] raise SurfaceError {
  self.check_vertex(a)
  self.check_vertex(b)
  match self.edges.get(edge_key(a, b)) {
    Some(ids) => ids.copy()
    None => raise InvalidArgument("model edge does not exist")
  }
}

///|
fn ModelState::neighbors(self : ModelState, v : Int) -> Array[Int] {
  let seen : Map[Int, Bool] = Map([])
  let out : Array[Int] = []
  for id in self.incident[v] {
    for other in self.faces[id].vertices() {
      if other != v && !seen.contains(other) {
        seen[other] = true
        out.push(other)
      }
    }
  }
  out
}

///|
fn ModelState::protected_vertex(self : ModelState, v : Int) -> Bool {
  for other in self.neighbors(v) {
    if self.constraints.contains(edge_key(v, other)) {
      return true
    }
  }
  false
}

///|
fn ModelState::edge_list(self : ModelState) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  for edge in self.edges.keys() {
    out.push(edge)
  }
  out.sort_by(fn(a, b) {
    if a.0 == b.0 {
      a.1.compare(b.1)
    } else {
      a.0.compare(b.0)
    }
  })
  out
}

///|
fn ModelState::copy(self : ModelState) -> ModelState {
  let out = graph_new(
    self.points.copy(),
    self.attributes.map(attribute_copy),
    self.scale,
    self.limits,
    origin=self.origin,
  )
  for i, flag in self.alive {
    out.alive[i] = flag
  }
  out.nv = self.nv
  out.angle_floor = self.angle_floor
  for face in self.faces {
    let id = out.faces.length()
    out.faces.push(face)
    if face.alive {
      out.attach(id)
    }
  }
  for key in self.constraints.keys() {
    out.constraints[key] = true
  }
  out
}

///|
fn v_add(a : Vec3, b : Vec3) -> Vec3 {
  { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z, }
}

///|
fn v_sub(a : Vec3, b : Vec3) -> Vec3 {
  { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z, }
}

///|
fn v_scale(a : Vec3, s : Double) -> Vec3 {
  { x: a.x * s, y: a.y * s, z: a.z * s, }
}

///|
fn v_div(a : Vec3, s : Double) -> Vec3 {
  { x: a.x / s, y: a.y / s, z: a.z / s, }
}

///|
fn v_dot(a : Vec3, b : Vec3) -> Double {
  a.x * b.x + a.y * b.y + a.z * b.z
}

///|
fn v_cross(a : Vec3, b : Vec3) -> Vec3 {
  {
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x,
  }
}

///|
fn v_length(a : Vec3) -> Double {
  v_dot(a, a).sqrt()
}

///|
fn v_lerp(a : Vec3, b : Vec3, t : Double) -> Vec3 {
  {
    x: lerp_scalar(a.x, b.x, t),
    y: lerp_scalar(a.y, b.y, t),
    z: lerp_scalar(a.z, b.z, t),
  }
}
