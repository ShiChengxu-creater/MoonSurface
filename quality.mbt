///|
fn minimum_angle(a : Vec3, b : Vec3, c : Vec3) -> Double {
  let points = [a, b, c]
  let mut smallest = 180.0
  for i in 0..<3 {
    let u = v_sub(points[(i + 1) % 3], points[i])
    let v = v_sub(points[(i + 2) % 3], points[i])
    let su = Double::max(abs(u.x), Double::max(abs(u.y), abs(u.z)))
    let sv = Double::max(abs(v.x), Double::max(abs(v.y), abs(v.z)))
    if su == 0.0 || sv == 0.0 {
      return 0.0
    }
    let un = v_div(u, su)
    let vn = v_div(v, sv)
    let cosine = v_dot(un, vn) / (v_length(un) * v_length(vn))
    smallest = Double::min(
      smallest,
      @math.acos(Double::max(-1.0, Double::min(1.0, cosine))) *
      180.0 /
      3.141592653589793,
    )
  }
  smallest
}

///|
/// Full-mesh metrics. Lengths are in input coordinate units; CV is dimensionless.
pub(all) struct GeometryQuality {
  vertices : Int
  edges : Int
  faces : Int
  min_angle_degrees : Double
  mean_min_angle_degrees : Double
  mean_triangle_quality : Double
  edge_min : Double
  edge_max : Double
  edge_mean : Double
  edge_cv : Double
}

///|
pub fn Model::quality(self : Model) -> GeometryQuality raise SurfaceError {
  let s = self.state
  let mut smallest = 180.0
  let mut angle_sum = 0.0
  let mut quality_sum = 0.0
  for face in s.faces {
    if !face.alive {
      continue
    }
    let points = face.vertices().map(fn(v) { s.points[v] })
    let mut angle = 180.0
    for i in 0..<3 {
      let u = v_unit(v_sub(points[(i + 1) % 3], points[i]))
      let v = v_unit(v_sub(points[(i + 2) % 3], points[i]))
      let value = @math.acos(Double::max(-1.0, Double::min(1.0, v_dot(u, v)))) *
        180.0 /
        3.141592653589793
      angle = Double::min(angle, value)
    }
    smallest = Double::min(smallest, angle)
    angle_sum += angle
    let ab = v_sub(points[1], points[0])
    let ac = v_sub(points[2], points[0])
    let scale = Double::max(v_length(ab), v_length(ac))
    let u = v_div(ab, scale)
    let v = v_div(ac, scale)
    let w = v_sub(u, v)
    quality_sum += 3.4641016151377544 *
      v_length(v_cross(u, v)) /
      (v_dot(u, u) + v_dot(v, v) + v_dot(w, w))
  }
  let mut emin = 1.7976931348623157e308
  let mut emax = 0.0
  let mut sum = 0.0
  let mut sum_sq = 0.0
  for (a, b) in s.edge_list() {
    let value = v_length(v_sub(s.points[a], s.points[b]))
    emin = Double::min(emin, value)
    emax = Double::max(emax, value)
    sum += value
    sum_sq += value * value
  }
  let ne = s.edges.length()
  let mean = if ne == 0 { 0.0 } else { sum / ne.to_double() }
  let cv = if mean == 0.0 {
    0.0
  } else {
    Double::max(0.0, sum_sq / ne.to_double() - mean * mean).sqrt() / mean
  }
  let face_count = s.nf.to_double()
  let output = GeometryQuality::{
    vertices: s.nv,
    edges: ne,
    faces: s.nf,
    min_angle_degrees: if s.nf == 0 {
      0.0
    } else {
      smallest
    },
    mean_min_angle_degrees: if s.nf == 0 {
      0.0
    } else {
      angle_sum / face_count
    },
    mean_triangle_quality: if s.nf == 0 {
      0.0
    } else {
      quality_sum / face_count
    },
    edge_min: if ne == 0 {
      0.0
    } else {
      emin * s.scale
    },
    edge_max: emax * s.scale,
    edge_mean: mean * s.scale,
    edge_cv: cv,
  }
  if !finite(output.edge_max) || !finite(output.edge_mean) {
    raise NumericalFailure("quality length overflow")
  }
  output
}
