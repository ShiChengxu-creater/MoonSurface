///|
priv suberror RequestError {
  BadRequest(String)
}

///|
/// Execute a bounded JSON geometry job. Returns an ok/error envelope, never partial output.
pub fn execute_json(text : String) -> String {
  try {
    let mut bytes = 0
    let mut depth = 0
    let mut quoted = false
    let mut escaped = false
    for c in text.iter() {
      let n = c.to_int()
      bytes += if n <= 0x7f {
        1
      } else if n <= 0x7ff {
        2
      } else if n <= 0xffff {
        3
      } else {
        4
      }
      if bytes > 16 * 1024 * 1024 {
        raise BadRequest("input exceeds 16 MiB")
      }
      if quoted {
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == '"' {
          quoted = false
        }
      } else if c == '"' {
        quoted = true
      } else if c == '[' || c == '{' {
        depth += 1
        if depth > 16 {
          raise BadRequest("JSON nesting exceeds 16")
        }
      } else if c == ']' || c == '}' {
        depth -= 1
      }
    }
    execute(@json.parse(text)).stringify()
  } catch {
    e =>
      Json::object(
        Map([("ok", Json::boolean(false)), ("error", Json::string("\{e}"))]),
      ).stringify()
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise RequestError {
  match value {
    Object(fields) => fields
    _ => raise BadRequest("expected an object")
  }
}

///|
fn keys(
  fields : Map[String, Json],
  allowed : Array[String],
) -> Unit raise RequestError {
  for key in fields.keys() {
    if !allowed.contains(key) {
      raise BadRequest("unknown field: \{key}")
    }
  }
}

///|
fn number(value : Json) -> Double raise RequestError {
  match value {
    Number(n, ..) if !n.is_nan() && !n.is_inf() => n
    _ => raise BadRequest("expected a finite number")
  }
}

///|
fn integer(value : Json) -> Int raise RequestError {
  let n = number(value)
  if n < -1_000_000.0 || n > 1_000_000.0 || n.to_int().to_double() != n {
    raise BadRequest("expected an integer in [-1000000,1000000]")
  }
  n.to_int()
}

///|
fn array(value : Json) -> Array[Json] raise RequestError {
  match value {
    Array(items) => items
    _ => raise BadRequest("expected an array")
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
) -> Json raise RequestError {
  match fields.get(key) {
    Some(value) => value
    None => raise BadRequest("missing field: \{key}")
  }
}

///|
fn optional_int(
  fields : Map[String, Json],
  key : String,
  fallback : Int,
) -> Int raise RequestError {
  match fields.get(key) {
    Some(value) => integer(value)
    None => fallback
  }
}

///|
fn j_int(n : Int) -> Json {
  Json::number(n.to_double())
}

///|
fn stats(value : @surface.TopologyStats) -> Json {
  Json::object(
    Map([
      ("vertices", j_int(value.vertices)),
      ("edges", j_int(value.edges)),
      ("faces", j_int(value.faces)),
      ("boundary_edges", j_int(value.boundary_edges)),
      ("boundary_loops", j_int(value.boundary_loops)),
      ("components", j_int(value.components)),
      ("euler", j_int(value.euler)),
    ]),
  )
}

///|
fn execute(value : Json) -> Json raise Error {
  let fields = object(value)
  keys(fields, ["format", "positions", "triangles", "operations", "limits"])
  if required(fields, "format") != Json::string("moonsurface/1") {
    raise BadRequest("format must be moonsurface/1")
  }
  let limit_fields = match fields.get("limits") {
    Some(value) => object(value)
    None => Map([])
  }
  keys(limit_fields, [
    "max_vertices", "max_input_faces", "max_output_faces", "max_levels",
  ])
  let limits = @surface.Limits::new(
    max_vertices=optional_int(limit_fields, "max_vertices", 1_000_000),
    max_input_faces=optional_int(limit_fields, "max_input_faces", 250_000),
    max_output_faces=optional_int(limit_fields, "max_output_faces", 1_000_000),
    max_levels=optional_int(limit_fields, "max_levels", 6),
  )
  let vertex_values = array(required(fields, "positions"))
  let face_values = array(required(fields, "triangles"))
  if vertex_values.length() > limits.vertex_limit() ||
    face_values.length() > limits.input_face_limit() {
    raise BadRequest("input count budget exceeded")
  }
  let positions = vertex_values.map(fn(value) raise {
    let row = array(value)
    if row.length() != 3 {
      raise BadRequest("position must have three coordinates")
    }
    @surface.Vec3::{ x: number(row[0]), y: number(row[1]), z: number(row[2]), }
  })
  let faces = face_values.map(fn(value) raise {
    let row = array(value)
    if row.length() != 3 {
      raise BadRequest("triangle must have three indices")
    }
    (integer(row[0]), integer(row[1]), integer(row[2]))
  })
  let mut mesh = @surface.Mesh::from_indexed(positions, faces, limits~)
  let operations = match fields.get("operations") {
    Some(value) => array(value)
    None => []
  }
  if operations.length() > 64 {
    raise BadRequest("at most 64 operations are supported")
  }
  let reports : Array[Json] = []
  for operation in operations {
    let op = object(operation)
    match required(op, "kind") {
      String("loop") => {
        keys(op, ["kind", "levels"])
        let result = @surface.subdivide_loop(
          mesh,
          integer(required(op, "levels")),
        )
        mesh = result.mesh
        reports.push(
          Json::object(
            Map([
              ("kind", Json::string("loop")),
              ("stages", Json::array(result.stages.map(stats))),
            ]),
          ),
        )
      }
      String("split") | String("flip") => {
        let is_split = required(op, "kind") == Json::string("split")
        keys(
          op,
          if is_split {
            ["kind", "edge", "fraction"]
          } else {
            ["kind", "edge"]
          },
        )
        let pair = array(required(op, "edge"))
        if pair.length() != 2 {
          raise BadRequest("edge must contain two vertex indices")
        }
        let a = integer(pair[0])
        let b = integer(pair[1])
        let edge = match mesh.find_edge(a, b) {
          Some(edge) => edge
          None => raise BadRequest("edge does not exist")
        }
        if is_split {
          let fraction = match op.get("fraction") {
            Some(value) => number(value)
            None => 0.5
          }
          let change = mesh.split_edge(edge, fraction~)
          reports.push(
            Json::object(
              Map([
                ("kind", Json::string("split")),
                ("vertex", j_int(change.vertex)),
                ("edge_endpoints", Json::array([j_int(a), j_int(b)])),
              ]),
            ),
          )
        } else {
          let change = mesh.flip_edge(edge)
          reports.push(
            Json::object(
              Map([
                ("kind", Json::string("flip")),
                (
                  "new_endpoints",
                  Json::array([
                    j_int(change.endpoints.0),
                    j_int(change.endpoints.1),
                  ]),
                ),
              ]),
            ),
          )
        }
      }
      _ => raise BadRequest("unsupported operation")
    }
  }
  mesh.validate()
  let output = mesh.to_indexed()
  Json::object(
    Map([
      ("ok", Json::boolean(true)),
      ("format", Json::string("moonsurface-result/1")),
      (
        "positions",
        Json::array(
          output
          .positions()
          .map(fn(p) {
            Json::array([
              Json::number(p.x),
              Json::number(p.y),
              Json::number(p.z),
            ])
          }),
        ),
      ),
      (
        "triangles",
        Json::array(
          output
          .faces()
          .map(fn(f) { Json::array([j_int(f.0), j_int(f.1), j_int(f.2)]) }),
        ),
      ),
      ("stats", stats(mesh.stats())),
      ("operations", Json::array(reports)),
    ]),
  )
}
