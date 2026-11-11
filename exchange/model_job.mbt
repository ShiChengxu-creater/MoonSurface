///|
fn vec2(value : Json) -> @surface.Vec2 raise RequestError {
  let row = array(value)
  if row.length() != 2 {
    raise BadRequest("UV must have two coordinates")
  }
  { x: number(row[0]), y: number(row[1]), }
}

///|
fn quality(value : @surface.GeometryQuality) -> Json {
  Json::object(
    Map([
      ("vertices", j_int(value.vertices)),
      ("edges", j_int(value.edges)),
      ("faces", j_int(value.faces)),
      ("min_angle_degrees", Json::number(value.min_angle_degrees)),
      ("mean_min_angle_degrees", Json::number(value.mean_min_angle_degrees)),
      ("mean_triangle_quality", Json::number(value.mean_triangle_quality)),
      ("edge_min", Json::number(value.edge_min)),
      ("edge_max", Json::number(value.edge_max)),
      ("edge_mean", Json::number(value.edge_mean)),
      ("edge_cv", Json::number(value.edge_cv)),
    ]),
  )
}

///|
fn optional_number(
  fields : Map[String, Json],
  key : String,
  fallback : Double,
) -> Double raise RequestError {
  match fields.get(key) {
    Some(value) => number(value)
    None => fallback
  }
}

///|
fn optional_array(
  fields : Map[String, Json],
  key : String,
) -> Array[Json] raise RequestError {
  match fields.get(key) {
    Some(value) => array(value)
    None => []
  }
}

///|
fn j_pair(pair : (Int, Int)) -> Json {
  Json::array([j_int(pair.0), j_int(pair.1)])
}

///|
fn model_execute(fields : Map[String, Json]) -> Json raise Error {
  keys(fields, [
    "format", "positions", "triangles", "attributes", "corner_uvs", "materials",
    "feature_edges", "sharp_angle", "operations",
  ])
  let vertex_values = array(required(fields, "positions"))
  let face_values = array(required(fields, "triangles"))
  if vertex_values.length() > 1_000_000 || face_values.length() > 250_000 {
    raise BadRequest("model input count budget")
  }
  let points = vertex_values.map(fn(value) raise {
    let row = array(value)
    if row.length() != 3 {
      raise BadRequest("position width")
    }
    @surface.Vec3::{ x: number(row[0]), y: number(row[1]), z: number(row[2]), }
  })
  let faces = face_values.map(fn(value) raise {
    let row = array(value)
    if row.length() != 3 {
      raise BadRequest("triangle width")
    }
    (integer(row[0]), integer(row[1]), integer(row[2]))
  })
  let attrs : Array[@surface.VertexAttribute] = []
  let attr_inputs = optional_array(fields, "attributes")
  if attr_inputs.length() > 16 {
    raise BadRequest("attribute channel budget")
  }
  for value in attr_inputs {
    let attr = object(value)
    keys(attr, ["name", "width", "interpolation", "values"])
    let name = match required(attr, "name") {
      String(name) => name
      _ => raise BadRequest("attribute name")
    }
    let width = integer(required(attr, "width"))
    let mode = match required(attr, "interpolation") {
      String("linear") => @surface.Linear
      String("unit") => @surface.UnitVector
      String("discrete") => @surface.Discrete
      _ => raise BadRequest("attribute interpolation")
    }
    let rows = array(required(attr, "values")).map(fn(value) raise {
      array(value).map(number)
    })
    attrs.push(@surface.VertexAttribute::new(name, width, mode, rows))
  }
  let uvs = optional_array(fields, "corner_uvs").map(fn(value) raise {
    let corners = array(value)
    if corners.length() != 3 {
      raise BadRequest("corner UV count")
    }
    @surface.CornerUV::{
      a: vec2(corners[0]),
      b: vec2(corners[1]),
      c: vec2(corners[2]),
    }
  })
  let materials = optional_array(fields, "materials").map(integer)
  let features = optional_array(fields, "feature_edges").map(fn(value) raise {
    let pair = array(value)
    if pair.length() != 2 {
      raise BadRequest("feature edge width")
    }
    (integer(pair[0]), integer(pair[1]))
  })
  let mut model = @surface.Model::new(
    @surface.Mesh::from_indexed(points, faces),
    attributes=attrs,
    corner_uvs=uvs,
    materials~,
    feature_edges=features,
    sharp_angle_degrees=optional_number(fields, "sharp_angle", 45.0),
  )
  let operations = optional_array(fields, "operations")
  if operations.length() > 64 {
    raise BadRequest("operation budget")
  }
  let reports : Array[Json] = []
  let mut last_snapshot : @surface.ModelSnapshot? = None
  for value in operations {
    let op = object(value)
    match required(op, "kind") {
      String("remesh") => {
        keys(op, [
          "kind", "target_edge_length", "iterations", "max_operations", "relaxation",
          "minimum_angle", "max_deviation",
        ])
        let result = @surface.remesh_isotropic(
          model,
          number(required(op, "target_edge_length")),
          iterations=optional_int(op, "iterations", 3),
          max_operations=optional_int(op, "max_operations", 20_000),
          relaxation=optional_number(op, "relaxation", 0.5),
          minimum_angle=optional_number(op, "minimum_angle", 10.0),
          max_deviation=optional_number(op, "max_deviation", 0.0),
        )
        let report = result.report
        let reason = match report.stop {
          @surface.IterationLimit => "iteration_limit"
          @surface.OperationBudget => "operation_budget"
          @surface.StableUnderConstraints => "stable_under_constraints"
          @surface.StorageLimit => "storage_limit"
        }
        reports.push(
          Json::object(
            Map([
              ("kind", Json::string("remesh")),
              ("iterations", j_int(report.iterations)),
              ("attempts", j_int(report.attempts)),
              ("splits", j_int(report.splits)),
              ("collapses", j_int(report.collapses)),
              ("flips", j_int(report.flips)),
              ("relaxed", j_int(report.relaxed)),
              ("rejected", j_int(report.rejected)),
              ("rejected_topology", j_int(report.rejected_topology)),
              ("rejected_geometry", j_int(report.rejected_geometry)),
              ("rejected_attributes", j_int(report.rejected_attributes)),
              ("rejected_budget", j_int(report.rejected_budget)),
              ("minimum_angle", Json::number(report.minimum_angle)),
              ("max_deviation", Json::number(report.max_deviation)),
              ("stop", Json::string(reason)),
              ("before", quality(result.before)),
              ("after", quality(result.after)),
              ("vertex_map", Json::array(result.output.vertex_map.map(j_int))),
              ("face_map", Json::array(result.output.face_map.map(j_int))),
            ]),
          ),
        )
        model = @surface.Model::new(
          result.output.mesh,
          attributes=result.output.attributes,
          corner_uvs=result.output.corner_uvs,
          materials=result.output.materials,
          feature_edges=result.output.feature_edges,
          sharp_angle_degrees=180.0,
        )
        last_snapshot = Some(result.output)
      }
      String("split") | String("flip") | String("collapse") => {
        let kind = required(op, "kind")
        keys(
          op,
          if kind == Json::string("flip") {
            ["kind", "edge"]
          } else {
            ["kind", "edge", "fraction"]
          },
        )
        let pair = array(required(op, "edge"))
        if pair.length() != 2 {
          raise BadRequest("model edge width")
        }
        let a = integer(pair[0])
        let b = integer(pair[1])
        let fraction = optional_number(
          op,
          "fraction",
          if kind == Json::string("split") {
            0.5
          } else {
            0.0
          },
        )
        if kind == Json::string("split") {
          let vertex = model.split_edge(a, b, fraction~)
          reports.push(
            Json::object(Map([("kind", kind), ("vertex", j_int(vertex))])),
          )
        } else if kind == Json::string("flip") {
          model.flip_edge(a, b)
          reports.push(Json::object(Map([("kind", kind)])))
        } else {
          model.collapse_edge(a, b, fraction~)
          reports.push(Json::object(Map([("kind", kind)])))
        }
        last_snapshot = None
      }
      _ => raise BadRequest("unsupported model operation")
    }
  }
  let snapshot = match last_snapshot {
    Some(value) => value
    None => model.compact()
  }
  snapshot.mesh.validate()
  let mesh = snapshot.mesh.to_indexed()
  let corner_normals = model.corner_normals()
  Json::object(
    Map([
      ("ok", Json::boolean(true)),
      ("format", Json::string("moonsurface-model-result/1")),
      (
        "positions",
        Json::array(
          mesh
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
          mesh
          .faces()
          .map(fn(f) { Json::array([j_int(f.0), j_int(f.1), j_int(f.2)]) }),
        ),
      ),
      (
        "attributes",
        Json::array(
          snapshot.attributes.map(fn(attr) {
            let mode = match attr.interpolation {
              @surface.Linear => "linear"
              @surface.UnitVector => "unit"
              @surface.Discrete => "discrete"
            }
            Json::object(
              Map([
                ("name", Json::string(attr.name)),
                ("width", j_int(attr.width)),
                ("interpolation", Json::string(mode)),
                (
                  "values",
                  Json::array(
                    attr
                    .values()
                    .map(fn(row) {
                      Json::array(row.map(fn(n) { Json::number(n) }))
                    }),
                  ),
                ),
              ]),
            )
          }),
        ),
      ),
      (
        "corner_uvs",
        Json::array(
          snapshot.corner_uvs.map(fn(uv) {
            Json::array(
              [uv.a, uv.b, uv.c].map(fn(p) {
                Json::array([Json::number(p.x), Json::number(p.y)])
              }),
            )
          }),
        ),
      ),
      ("materials", Json::array(snapshot.materials.map(j_int))),
      (
        "corner_normals",
        Json::array(
          corner_normals.map(fn(ns) {
            Json::array(
              [ns.0, ns.1, ns.2].map(fn(n) {
                Json::array([
                  Json::number(n.x),
                  Json::number(n.y),
                  Json::number(n.z),
                ])
              }),
            )
          }),
        ),
      ),
      ("face_charts", Json::array(snapshot.face_charts.map(j_int))),
      ("feature_edges", Json::array(snapshot.feature_edges.map(j_pair))),
      ("vertex_map", Json::array(snapshot.vertex_map.map(j_int))),
      ("face_map", Json::array(snapshot.face_map.map(j_int))),
      ("stats", stats(snapshot.mesh.stats())),
      ("operations", Json::array(reports)),
    ]),
  )
}
