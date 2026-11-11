///|
/// Immutable original-surface BVH; normalized coordinates keep distance arithmetic bounded.
priv struct ProjectionNode {
  lo : Vec3
  hi : Vec3
  left : Int
  right : Int
  faces : Array[Int]
}

///|
priv struct ReferenceSurface {
  state : ModelState
  nodes : Array[ProjectionNode]
  root : Int
}

///|
priv struct ProjectionHit {
  point : Vec3
  face : Int
  weights : (Double, Double, Double)
  distance_sq : Double
}

///|
priv struct ModelSample {
  point : Vec3
  rows : Array[Array[Double]]
  uv : Vec2?
}

///|
fn coordinate(p : Vec3, axis : Int) -> Double {
  if axis == 0 {
    p.x
  } else if axis == 1 {
    p.y
  } else {
    p.z
  }
}

///|
fn ReferenceSurface::new(state : ModelState) -> ReferenceSurface {
  let reference = { state: state.copy(), nodes: [], root: 0, }
  let ids : Array[Int] = []
  for id, f in state.faces {
    if f.alive {
      ids.push(id)
    }
  }
  let root = reference.build(ids)
  { ..reference, root, }
}

///|
fn ReferenceSurface::build(self : ReferenceSurface, ids : Array[Int]) -> Int {
  let mut lo = Vec3::{
    x: 1.7976931348623157e308,
    y: 1.7976931348623157e308,
    z: 1.7976931348623157e308,
  }
  let mut hi = v_scale(lo, -1.0)
  for id in ids {
    for v in self.state.faces[id].vertices() {
      let p = self.state.points[v]
      lo = {
        x: Double::min(lo.x, p.x),
        y: Double::min(lo.y, p.y),
        z: Double::min(lo.z, p.z),
      }
      hi = {
        x: Double::max(hi.x, p.x),
        y: Double::max(hi.y, p.y),
        z: Double::max(hi.z, p.z),
      }
    }
  }
  let index = self.nodes.length()
  self.nodes.push({ lo, hi, left: -1, right: -1, faces: [], })
  if ids.length() <= 8 {
    self.nodes[index] = { lo, hi, left: -1, right: -1, faces: ids, }
    return index
  }
  let extent = v_sub(hi, lo)
  let axis = if extent.x >= extent.y && extent.x >= extent.z {
    0
  } else if extent.y >= extent.z {
    1
  } else {
    2
  }
  ids.sort_by(fn(a, b) {
    let fa = self.state.faces[a]
    let fb = self.state.faces[b]
    let ca = coordinate(self.state.points[fa.a], axis) +
      coordinate(self.state.points[fa.b], axis) +
      coordinate(self.state.points[fa.c], axis)
    let cb = coordinate(self.state.points[fb.a], axis) +
      coordinate(self.state.points[fb.b], axis) +
      coordinate(self.state.points[fb.c], axis)
    if ca == cb {
      a.compare(b)
    } else {
      ca.compare(cb)
    }
  })
  let left : Array[Int] = []
  let right : Array[Int] = []
  for i, id in ids {
    if i < ids.length() / 2 {
      left.push(id)
    } else {
      right.push(id)
    }
  }
  let l = self.build(left)
  let r = self.build(right)
  self.nodes[index] = { lo, hi, left: l, right: r, faces: [], }
  index
}

///|
fn bbox_distance(node : ProjectionNode, p : Vec3) -> Double {
  let mut sum = 0.0
  for axis in 0..<3 {
    let x = coordinate(p, axis)
    let d = Double::max(
      coordinate(node.lo, axis) - x,
      Double::max(0.0, x - coordinate(node.hi, axis)),
    )
    sum += d * d
  }
  sum
}

///|
/// Closest point regions of a triangle, computed independently of topology.
fn triangle_hit(
  a : Vec3,
  b : Vec3,
  c : Vec3,
  p : Vec3,
  face : Int,
) -> ProjectionHit raise SurfaceError {
  let ab = v_sub(b, a)
  let ac = v_sub(c, a)
  let ap = v_sub(p, a)
  let d1 = v_dot(ab, ap)
  let d2 = v_dot(ac, ap)
  let weights = if d1 <= 0.0 && d2 <= 0.0 {
    (1.0, 0.0, 0.0)
  } else {
    let bp = v_sub(p, b)
    let d3 = v_dot(ab, bp)
    let d4 = v_dot(ac, bp)
    if d3 >= 0.0 && d4 <= d3 {
      (0.0, 1.0, 0.0)
    } else {
      let vc = d1 * d4 - d3 * d2
      if vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0 {
        let v = d1 / (d1 - d3)
        (1.0 - v, v, 0.0)
      } else {
        let cp = v_sub(p, c)
        let d5 = v_dot(ab, cp)
        let d6 = v_dot(ac, cp)
        if d6 >= 0.0 && d5 <= d6 {
          (0.0, 0.0, 1.0)
        } else {
          let vb = d5 * d2 - d1 * d6
          if vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0 {
            let w = d2 / (d2 - d6)
            (1.0 - w, 0.0, w)
          } else {
            let va = d3 * d6 - d5 * d4
            if va <= 0.0 && d4 - d3 >= 0.0 && d5 - d6 >= 0.0 {
              let w = (d4 - d3) / (d4 - d3 + (d5 - d6))
              (0.0, 1.0 - w, w)
            } else {
              let denominator = va + vb + vc
              if denominator <= 0.0 || !finite(denominator) {
                raise NumericalFailure("ill-conditioned projection triangle")
              }
              let v = vb / denominator
              let w = vc / denominator
              (1.0 - v - w, v, w)
            }
          }
        }
      }
    }
  }
  let q = v_add(
    v_scale(a, weights.0),
    v_add(v_scale(b, weights.1), v_scale(c, weights.2)),
  )
  let delta = v_sub(q, p)
  { point: q, face, weights, distance_sq: v_dot(delta, delta), }
}

///|
fn ReferenceSurface::closest(
  self : ReferenceSurface,
  p : Vec3,
  chart : Int,
) -> ProjectionHit raise SurfaceError {
  let stack = [self.root]
  let mut best : ProjectionHit? = None
  let mut distance = 1.7976931348623157e308
  while !stack.is_empty() {
    let index = stack.pop().unwrap()
    let node = self.nodes[index]
    if bbox_distance(node, p) > distance {
      continue
    }
    if node.left >= 0 {
      let dl = bbox_distance(self.nodes[node.left], p)
      let dr = bbox_distance(self.nodes[node.right], p)
      if dl < dr {
        stack.push(node.right)
        stack.push(node.left)
      } else {
        stack.push(node.left)
        stack.push(node.right)
      }
    } else {
      for id in node.faces {
        let f = self.state.faces[id]
        if f.chart != chart {
          continue
        }
        let hit = triangle_hit(
          self.state.points[f.a],
          self.state.points[f.b],
          self.state.points[f.c],
          p,
          id,
        )
        if hit.distance_sq < distance ||
          (
            hit.distance_sq == distance &&
            best is Some({ face, .. }) &&
            id < face
          ) {
          distance = hit.distance_sq
          best = Some(hit)
        }
      }
    }
  }
  match best {
    Some(hit) => hit
    None => raise NumericalFailure("no reference patch")
  }
}

///|
fn convex3(
  a : Double,
  b : Double,
  c : Double,
  w : (Double, Double, Double),
) -> Double {
  let scale = Double::max(abs(a), Double::max(abs(b), abs(c)))
  if scale == 0.0 {
    return 0.0
  }
  Double::max(
    -1.0,
    Double::min(1.0, a / scale * w.0 + b / scale * w.1 + c / scale * w.2),
  ) *
  scale
}

///|
fn ReferenceSurface::sample(
  self : ReferenceSurface,
  hit : ProjectionHit,
) -> ModelSample raise SurfaceError {
  let f = self.state.faces[hit.face]
  let rows : Array[Array[Double]] = []
  for attr in self.state.attributes {
    let a = attr.data[f.a]
    let b = attr.data[f.b]
    let c = attr.data[f.c]
    if attr.interpolation == Discrete && (a != b || b != c) {
      raise AttributeConflict(attr.name)
    }
    let row : Array[Double] = []
    for i in 0..<attr.width {
      row.push(convex3(a[i], b[i], c[i], hit.weights))
    }
    rows.push(attribute_normalize(row, attr.interpolation))
  }
  let uv = match f.uv {
    Some(value) =>
      Some(Vec2::{
        x: convex3(value.a.x, value.b.x, value.c.x, hit.weights),
        y: convex3(value.a.y, value.b.y, value.c.y, hit.weights),
      })
    None => None
  }
  { point: hit.point, rows, uv, }
}

///|
fn ModelState::move_vertex(
  self : ModelState,
  v : Int,
  sample : ModelSample,
) -> Unit raise SurfaceError {
  if self.protected_vertex(v) {
    raise ProtectedFeature(v, v)
  }
  for i, attr in self.attributes {
    if attr.interpolation == Discrete && attr.data[v] != sample.rows[i] {
      raise AttributeConflict(attr.name)
    }
  }
  let planned : Array[(Int, ModelFace)] = []
  for id in self.incident[v] {
    let f = self.faces[id]
    let corners = f
      .vertices()
      .map(fn(n) {
        if n == v {
          match sample.uv {
            Some(uv) => uv
            None => f.corner(n)
          }
        } else {
          f.corner(n)
        }
      })
    let proposed = triangle_like(
      f,
      f.a,
      f.b,
      f.c,
      corners[0],
      corners[1],
      corners[2],
    )
    if !self.face_ok(f, proposed, v, sample.point) {
      raise NumericalFailure("relaxation geometry/UV inversion")
    }
    planned.push((id, proposed))
  }
  self.points[v] = sample.point
  for i, attr in self.attributes {
    attr.data[v] = sample.rows[i].copy()
  }
  for (id, f) in planned {
    self.faces[id] = f
  }
}
