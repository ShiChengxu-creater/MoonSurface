///|
fn v_unit(v : Vec3) -> Vec3 raise SurfaceError {
  let scale = Double::max(abs(v.x), Double::max(abs(v.y), abs(v.z)))
  if scale == 0.0 || !finite(scale) {
    raise NumericalFailure("undefined model normal")
  }
  let out = v_div(v, scale)
  v_scale(out, 1.0 / v_length(out))
}

///|
/// Recompute corner normals in separate smoothing fans at protected edges.
pub fn Model::corner_normals(
  self : Model,
) -> Array[(Vec3, Vec3, Vec3)] raise SurfaceError {
  let s = self.state
  let zero = Vec3::{ x: 0.0, y: 0.0, z: 0.0, }
  let normals = Array::make(3 * s.faces.length(), zero)
  for vertex in 0..<s.points.length() {
    if !s.alive[vertex] {
      continue
    }
    let seen : Map[Int, Bool] = Map([])
    let p = s.points[vertex]
    let mut scale = 0.0
    for other in s.neighbors(vertex) {
      let delta = v_sub(s.points[other], p)
      scale = Double::max(
        scale,
        Double::max(abs(delta.x), Double::max(abs(delta.y), abs(delta.z))),
      )
    }
    for start in s.incident[vertex] {
      if seen.contains(start) {
        continue
      }
      let queue = [start]
      seen[start] = true
      let mut cursor = 0
      let mut sum = zero
      while cursor < queue.length() {
        let f = s.faces[queue[cursor]]
        cursor += 1
        let ab = v_div(v_sub(s.points[f.b], s.points[f.a]), scale)
        let ac = v_div(v_sub(s.points[f.c], s.points[f.a]), scale)
        sum = v_add(sum, v_cross(ab, ac))
        for other in f.vertices() {
          if other == vertex {
            continue
          }
          let key = edge_key(vertex, other)
          if s.constraints.contains(key) {
            continue
          }
          for id in s.edges[key] {
            if !seen.contains(id) {
              seen[id] = true
              queue.push(id)
            }
          }
        }
      }
      let n = v_unit(sum)
      for id in queue {
        let f = s.faces[id]
        let corner = if f.a == vertex {
          0
        } else if f.b == vertex {
          1
        } else {
          2
        }
        normals[3 * id + corner] = n
      }
    }
  }
  let output : Array[(Vec3, Vec3, Vec3)] = []
  for id, f in s.faces {
    if f.alive {
      output.push((normals[3 * id], normals[3 * id + 1], normals[3 * id + 2]))
    }
  }
  output
}
