///|
fn ModelState::face_ok(
  self : ModelState,
  old : ModelFace,
  proposed : ModelFace,
  moved : Int,
  point : Vec3,
) -> Bool {
  let a = if proposed.a == moved { point } else { self.points[proposed.a] }
  let b = if proposed.b == moved { point } else { self.points[proposed.b] }
  let c = if proposed.c == moved { point } else { self.points[proposed.c] }
  !degenerate(a, b, c) &&
  normal_dot(self.face_normal(old), unit_face(a, b, c)) > 1.0e-8 &&
  uv_survives(old.uv, proposed.uv)
}

///|
fn triangle_like(
  old : ModelFace,
  a : Int,
  b : Int,
  c : Int,
  ua : Vec2,
  ub : Vec2,
  uc : Vec2,
) -> ModelFace {
  {
    ..old,
    a,
    b,
    c,
    uv: if old.uv is Some(_) {
      Some({ a: ua, b: ub, c: uc, })
    } else {
      None
    },
  }
}

///|
pub fn Model::split_edge(
  self : Model,
  a : Int,
  b : Int,
  fraction? : Double = 0.5,
) -> Int raise SurfaceError {
  self.state.split(a, b, fraction)
}

///|
fn ModelState::split(
  self : ModelState,
  a : Int,
  b : Int,
  t : Double,
) -> Int raise SurfaceError {
  let ids = self.edge_faces(a, b)
  if !finite(t) || t <= 0.0 || t >= 1.0 {
    raise InvalidArgument("split fraction")
  }
  if self.points.length() >= self.limits.max_vertices ||
    self.nf + ids.length() > self.limits.max_output_faces ||
    self.faces.length() + 2 * ids.length() >
    4 * Int::max(self.limits.max_input_faces, self.limits.max_output_faces) {
    raise LimitExceeded("model split slots/faces")
  }
  let point = v_lerp(self.points[a], self.points[b], t)
  let rows : Array[Array[Double]] = []
  for attr in self.attributes {
    rows.push(attribute_blend(attr, a, b, t))
  }
  let m = self.points.length()
  let planned : Array[ModelFace] = []
  for id in ids {
    let f = self.faces[id]
    let vertices = f.vertices()
    for i in 0..<3 {
      let u = vertices[i]
      let v = vertices[(i + 1) % 3]
      let w = vertices[(i + 2) % 3]
      if edge_key(u, v) != edge_key(a, b) {
        continue
      }
      let um = uv_lerp(f.corner(a), f.corner(b), t)
      let left = triangle_like(f, u, m, w, f.corner(u), um, f.corner(w))
      let right = triangle_like(f, m, v, w, um, f.corner(v), f.corner(w))
      if !self.face_ok(f, left, m, point) || !self.face_ok(f, right, m, point) {
        raise NumericalFailure("model split geometry/UV inversion")
      }
      planned.push(left)
      planned.push(right)
    }
  }
  self.points.push(point)
  self.alive.push(true)
  self.incident.push([])
  self.nv += 1
  for i, attr in self.attributes {
    attr.data.push(rows[i])
  }
  for id in ids {
    self.detach(id)
  }
  for face in planned {
    self.append_face(face)
  }
  let key = edge_key(a, b)
  if self.constraints.contains(key) {
    self.constraints.remove(key)
    self.constraints[edge_key(a, m)] = true
    self.constraints[edge_key(m, b)] = true
  }
  m
}

///|
pub fn Model::flip_edge(
  self : Model,
  a : Int,
  b : Int,
) -> Unit raise SurfaceError {
  self.state.flip(a, b)
}

///|
fn ModelState::flip(
  self : ModelState,
  a : Int,
  b : Int,
) -> Unit raise SurfaceError {
  let ids = self.edge_faces(a, b)
  if self.constraints.contains(edge_key(a, b)) {
    raise ProtectedFeature(a, b)
  }
  if ids.length() != 2 {
    raise ProtectedFeature(a, b)
  }
  let left = self.faces[ids[0]]
  let right = self.faces[ids[1]]
  let verts = left.vertices()
  let mut u = a
  let mut v = b
  let mut w = -1
  for i in 0..<3 {
    if edge_key(verts[i], verts[(i + 1) % 3]) == edge_key(a, b) {
      u = verts[i]
      v = verts[(i + 1) % 3]
      w = verts[(i + 2) % 3]
    }
  }
  let mut x = -1
  for other in right.vertices() {
    if other != u && other != v {
      x = other
    }
  }
  if self.edges.contains(edge_key(w, x)) {
    raise DuplicateDiagonal(w, x)
  }
  let fl = triangle_like(
    left,
    w,
    x,
    v,
    left.corner(w),
    right.corner(x),
    left.corner(v),
  )
  let fr = triangle_like(
    right,
    x,
    w,
    u,
    right.corner(x),
    left.corner(w),
    right.corner(u),
  )
  if !self.face_ok(left, fl, -1, self.points[u]) ||
    !self.face_ok(right, fr, -1, self.points[u]) {
    raise NumericalFailure("model flip geometry/UV inversion")
  }
  self.detach(ids[0])
  self.detach(ids[1])
  self.faces[ids[0]] = fl
  self.attach(ids[0])
  self.faces[ids[1]] = fr
  self.attach(ids[1])
}

///|
/// Keep `keep`'s id, delete `remove`, with optional attribute/position blending.
pub fn Model::collapse_edge(
  self : Model,
  keep : Int,
  remove : Int,
  fraction? : Double = 0.0,
) -> Unit raise SurfaceError {
  self.state.collapse(keep, remove, fraction, 1.7976931348623157e308)
}

///|
fn ModelState::collapse(
  self : ModelState,
  keep : Int,
  remove : Int,
  t : Double,
  max_edge_length : Double,
) -> Unit raise SurfaceError {
  let ids = self.edge_faces(keep, remove)
  if !finite(t) || t < 0.0 || t > 1.0 {
    raise InvalidArgument("collapse fraction")
  }
  if ids.length() != 2 ||
    self.protected_vertex(keep) ||
    self.protected_vertex(remove) {
    raise ProtectedFeature(keep, remove)
  }
  let neighbors_keep = self.neighbors(keep)
  let neighbors_remove = self.neighbors(remove)
  let mut common = 0
  for n in neighbors_keep {
    if neighbors_remove.contains(n) {
      common += 1
    }
  }
  if common != 2 {
    raise CollapseTopology(keep, remove)
  }
  let point = v_lerp(self.points[keep], self.points[remove], t)
  let rows : Array[Array[Double]] = []
  for attr in self.attributes {
    rows.push(attribute_blend(attr, keep, remove, t))
  }
  let edge_face = self.faces[ids[0]]
  let uv = uv_lerp(edge_face.corner(keep), edge_face.corner(remove), t)
  let affected = self.incident[keep].copy()
  for id in self.incident[remove] {
    if !affected.contains(id) {
      affected.push(id)
    }
  }
  let planned : Array[(Int, ModelFace)] = []
  let seen : Map[(Int, Int, Int), Bool] = Map([])
  for id in affected {
    if ids.contains(id) {
      continue
    }
    let f = self.faces[id]
    let verts = f.vertices().map(fn(v) { if v == remove { keep } else { v } })
    let corners = f
      .vertices()
      .map(fn(v) { if v == keep || v == remove { uv } else { f.corner(v) } })
    let proposed = triangle_like(
      f,
      verts[0],
      verts[1],
      verts[2],
      corners[0],
      corners[1],
      corners[2],
    )
    let key = face_key(proposed.a, proposed.b, proposed.c)
    if seen.contains(key) {
      raise CollapseTopology(keep, remove)
    }
    match self.lookup.get(key) {
      Some(other) if !affected.contains(other) =>
        raise CollapseTopology(keep, remove)
      _ => ()
    }
    seen[key] = true
    if !self.face_ok(f, proposed, keep, point) {
      raise NumericalFailure("collapse geometry/UV inversion")
    }
    for v in verts {
      if v != keep && v_length(v_sub(self.points[v], point)) > max_edge_length {
        raise InvalidArgument("collapse would create a long edge")
      }
    }
    planned.push((id, proposed))
  }
  for id in affected {
    self.detach(id)
  }
  self.points[keep] = point
  for i, attr in self.attributes {
    attr.data[keep] = rows[i]
  }
  self.alive[remove] = false
  self.nv -= 1
  for (id, face) in planned {
    self.faces[id] = face
    self.attach(id)
  }
}
