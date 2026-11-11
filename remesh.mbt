///|
pub(all) enum RemeshStop {
  IterationLimit
  OperationBudget
  StableUnderConstraints
  StorageLimit
} derive(Eq, Debug)

///|
pub extend RemeshStop with Eq::{equal, not_equal}

///|
pub extend RemeshStop with @debug.Debug::{to_repr}

///|
pub(all) struct RemeshReport {
  iterations : Int
  attempts : Int
  splits : Int
  collapses : Int
  flips : Int
  relaxed : Int
  rejected : Int
  rejected_topology : Int
  rejected_geometry : Int
  rejected_attributes : Int
  rejected_budget : Int
  minimum_angle : Double
  max_deviation : Double
  stop : RemeshStop
}

///|
pub(all) struct RemeshResult {
  output : ModelSnapshot
  report : RemeshReport
  before : GeometryQuality
  after : GeometryQuality
}

///|
priv struct RemeshCounts {
  mut attempts : Int
  mut splits : Int
  mut collapses : Int
  mut flips : Int
  mut relaxed : Int
  mut rejected : Int
  mut topology_rejections : Int
  mut geometry_rejections : Int
  mut attribute_rejections : Int
  mut budget_rejections : Int
}

///|
fn RemeshCounts::reject(self : RemeshCounts, error : SurfaceError) -> Unit {
  self.rejected += 1
  match error {
    LimitExceeded(_) => self.budget_rejections += 1
    AttributeConflict(_) => self.attribute_rejections += 1
    NumericalFailure(_) => self.geometry_rejections += 1
    _ => self.topology_rejections += 1
  }
}

///|
fn ModelState::ideal_valence(self : ModelState, vertex : Int) -> Int {
  for other in self.neighbors(vertex) {
    if self.edges[edge_key(vertex, other)].length() == 1 {
      return 4
    }
  }
  6
}

///|
fn squared(n : Int) -> Int {
  n * n
}

///|
fn ModelState::improves_valence(self : ModelState, a : Int, b : Int) -> Bool {
  let ids = self.edges[edge_key(a, b)]
  if ids.length() != 2 {
    return false
  }
  let opposite_vertices : Array[Int] = []
  for id in ids {
    for v in self.faces[id].vertices() {
      if v != a && v != b {
        opposite_vertices.push(v)
      }
    }
  }
  let c = opposite_vertices[0]
  let d = opposite_vertices[1]
  let da = self.neighbors(a).length() - self.ideal_valence(a)
  let db = self.neighbors(b).length() - self.ideal_valence(b)
  let dc = self.neighbors(c).length() - self.ideal_valence(c)
  let dd = self.neighbors(d).length() - self.ideal_valence(d)
  squared(da - 1) + squared(db - 1) + squared(dc + 1) + squared(dd + 1) <
  squared(da) + squared(db) + squared(dc) + squared(dd)
}

///|
/// Uniform edge-length remeshing with conservative feature locks and reference projection.
/// The caller's Model is unchanged. Attempts, including rejected candidates, consume budget.
pub fn remesh_isotropic(
  model : Model,
  target_edge_length : Double,
  iterations? : Int = 3,
  max_operations? : Int = 20_000,
  relaxation? : Double = 0.5,
  minimum_angle? : Double = 10.0,
  max_deviation? : Double = 0.0,
) -> RemeshResult raise SurfaceError {
  if !finite(target_edge_length) ||
    target_edge_length <= 0.0 ||
    iterations < 0 ||
    iterations > 10 ||
    max_operations < 0 ||
    max_operations > 200_000 ||
    !finite(relaxation) ||
    relaxation < 0.0 ||
    relaxation > 1.0 ||
    !finite(minimum_angle) ||
    minimum_angle < 0.0 ||
    minimum_angle > 60.0 ||
    !finite(max_deviation) ||
    max_deviation < 0.0 {
    raise InvalidArgument("invalid remeshing options")
  }
  let working = model.copy()
  let s = working.state
  let target = target_edge_length / s.scale
  if !finite(target) || target < 1.0e-12 {
    raise InvalidArgument("target too small relative to model coordinate scale")
  }
  for (a, b) in s.edge_list() {
    if v_length(v_sub(s.points[a], s.points[b])) < 1.0e-12 {
      raise NumericalFailure(
        "input edge below supported normalized remeshing scale",
      )
    }
  }
  let before = working.quality()
  s.angle_floor = Double::min(minimum_angle, before.min_angle_degrees)
  let deviation = if max_deviation == 0.0 {
    target_edge_length * 0.25
  } else {
    max_deviation
  }
  s.deviation_limit = deviation / s.scale
  if !finite(s.deviation_limit) || s.deviation_limit < 1.0e-14 {
    raise InvalidArgument("projection deviation scale")
  }
  for id, f in s.faces {
    if !f.alive {
      continue
    }
    let a = s.points[f.a]
    let b = s.points[f.b]
    let c = s.points[f.c]
    s.faces[id] = {
      ..f,
      witnesses: [
        a,
        b,
        c,
        v_lerp(a, b, 0.5),
        v_lerp(b, c, 0.5),
        v_lerp(c, a, 0.5),
        v_div(v_add(a, v_add(b, c)), 3.0),
      ],
    }
  }
  let reference = ReferenceSurface::new(s)
  s.projection_guard = Some(reference)
  let counts = RemeshCounts::{
    attempts: 0,
    splits: 0,
    collapses: 0,
    flips: 0,
    relaxed: 0,
    rejected: 0,
    topology_rejections: 0,
    geometry_rejections: 0,
    attribute_rejections: 0,
    budget_rejections: 0,
  }
  let mut performed = 0
  let mut stop = IterationLimit
  for _ in 0..<iterations {
    if counts.attempts >= max_operations || counts.budget_rejections > 0 {
      stop = if counts.budget_rejections > 0 {
        StorageLimit
      } else {
        OperationBudget
      }
      break
    }
    performed += 1
    let previous = counts.splits +
      counts.collapses +
      counts.flips +
      counts.relaxed
    // Multiple long-edge sweeps; each candidate only touches its local star.
    for _ in 0..<16 {
      let mut changed = false
      for (a, b) in s.edge_list() {
        if counts.attempts >= max_operations || counts.budget_rejections > 0 {
          break
        }
        let key = edge_key(a, b)
        if !s.edges.contains(key) ||
          v_length(v_sub(s.points[a], s.points[b])) <= 4.0 / 3.0 * target {
          continue
        }
        counts.attempts += 1
        try {
          let projected = if s.constraints.contains(key) {
            None
          } else {
            let chart = s.faces[s.edges[key][0]].chart
            let hit = reference.closest(
              v_lerp(s.points[a], s.points[b], 0.5),
              chart,
            )
            Some(reference.sample(hit))
          }
          s.split(a, b, 0.5, projected~) |> ignore
          counts.splits += 1
          changed = true
        } catch {
          e => counts.reject(e)
        }
      }
      if !changed ||
        counts.attempts >= max_operations ||
        counts.budget_rejections > 0 {
        break
      }
    }
    for (a, b) in s.edge_list() {
      if counts.attempts >= max_operations || counts.budget_rejections > 0 {
        break
      }
      let key = edge_key(a, b)
      if !s.edges.contains(key) ||
        s.protected_vertex(a) ||
        s.protected_vertex(b) ||
        v_length(v_sub(s.points[a], s.points[b])) >= 4.0 / 5.0 * target {
        continue
      }
      counts.attempts += 1
      try s.collapse(a, b, 0.0, 4.0 / 3.0 * target) catch {
        e => counts.reject(e)
      } noraise {
        _ => counts.collapses += 1
      }
    }
    for (a, b) in s.edge_list() {
      if counts.attempts >= max_operations || counts.budget_rejections > 0 {
        break
      }
      let key = edge_key(a, b)
      if !s.edges.contains(key) ||
        s.constraints.contains(key) ||
        !s.improves_valence(a, b) {
        continue
      }
      counts.attempts += 1
      try s.flip(a, b) catch {
        e => counts.reject(e)
      } noraise {
        _ => counts.flips += 1
      }
    }
    // Proposals use the same old positions; committing each rechecks local geometry/UVs.
    let proposals : Array[(Int, ModelSample)] = []
    for v in 0..<s.points.length() {
      if counts.attempts >= max_operations || counts.budget_rejections > 0 {
        break
      }
      if !s.alive[v] || s.protected_vertex(v) || relaxation == 0.0 {
        continue
      }
      let neighbors = s.neighbors(v)
      let mut sum = Vec3::{ x: 0.0, y: 0.0, z: 0.0, }
      for n in neighbors {
        sum = v_add(sum, s.points[n])
      }
      let delta = v_sub(v_div(sum, neighbors.length().to_double()), s.points[v])
      if v_dot(delta, delta) < 1.0e-28 {
        continue
      }
      counts.attempts += 1
      try {
        let mut normal = Vec3::{ x: 0.0, y: 0.0, z: 0.0, }
        for id in s.incident[v] {
          let f = s.faces[id]
          normal = v_add(
            normal,
            v_cross(
              v_sub(s.points[f.b], s.points[f.a]),
              v_sub(s.points[f.c], s.points[f.a]),
            ),
          )
        }
        let n = v_unit(normal)
        let tangent = v_sub(delta, v_scale(n, v_dot(delta, n)))
        let proposed = v_add(s.points[v], v_scale(tangent, relaxation))
        let chart = s.faces[s.incident[v][0]].chart
        let hit = reference.closest(proposed, chart)
        proposals.push((v, reference.sample(hit)))
      } catch {
        e => counts.reject(e)
      }
    }
    for (v, sample) in proposals {
      try s.move_vertex(v, sample) catch {
        e => counts.reject(e)
      } noraise {
        _ => counts.relaxed += 1
      }
    }
    if counts.attempts >= max_operations || counts.budget_rejections > 0 {
      stop = if counts.budget_rejections > 0 {
        StorageLimit
      } else {
        OperationBudget
      }
      break
    }
    if counts.splits + counts.collapses + counts.flips + counts.relaxed ==
      previous {
      stop = StableUnderConstraints
      break
    }
  }
  {
    output: working.compact(),
    before,
    after: working.quality(),
    report: {
      iterations: performed,
      attempts: counts.attempts,
      splits: counts.splits,
      collapses: counts.collapses,
      flips: counts.flips,
      relaxed: counts.relaxed,
      rejected: counts.rejected,
      rejected_topology: counts.topology_rejections,
      rejected_geometry: counts.geometry_rejections,
      rejected_attributes: counts.attribute_rejections,
      rejected_budget: counts.budget_rejections,
      minimum_angle,
      max_deviation: deviation,
      stop,
    },
  }
}
