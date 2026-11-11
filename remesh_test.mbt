///|
fn uneven_grid() -> @moonsurface.Model raise @moonsurface.SurfaceError {
  let xs : Array[Double] = [0, 0.08, 0.30, 0.65, 1]
  let ys : Array[Double] = [0, 0.15, 0.4, 0.7, 1]
  let points : Array[@moonsurface.Vec3] = []
  let field : Array[Array[Double]] = []
  for y in ys {
    for x in xs {
      points.push({ x, y, z: 0.0, })
      field.push([x + 2.0 * y])
    }
  }
  let faces : Array[(Int, Int, Int)] = []
  let uvs : Array[@moonsurface.CornerUV] = []
  for y in 0..<4 {
    for x in 0..<4 {
      let v = y * 5 + x
      for f in [(v, v + 1, v + 6), (v, v + 6, v + 5)] {
        faces.push(f)
        uvs.push({
          a: { x: points[f.0].x, y: points[f.0].y, },
          b: { x: points[f.1].x, y: points[f.1].y, },
          c: { x: points[f.2].x, y: points[f.2].y, },
        })
      }
    }
  }
  @moonsurface.Model::new(
    @moonsurface.Mesh::from_indexed(points, faces),
    corner_uvs=uvs,
    attributes=[
      @moonsurface.VertexAttribute::new("field", 1, @moonsurface.Linear, field),
    ],
  )
}

///|
test "isotropic remeshing improves uneven grid and resamples a linear field" {
  let input = uneven_grid()
  let before = input.compact().mesh.to_indexed()
  let result = @moonsurface.remesh_isotropic(
    input,
    0.22,
    iterations=3,
    max_operations=4000,
  )
  result.output.mesh.validate()
  assert_eq(input.compact().mesh.to_indexed(), before)
  assert_eq(result.output.mesh.stats().euler, 1)
  assert_true(
    result.report.splits > 0 &&
    result.report.collapses > 0 &&
    result.report.relaxed > 0,
  )
  assert_true(result.after.edge_cv < result.before.edge_cv)
  assert_true(
    result.after.min_angle_degrees + 1.0e-6 >=
    Double::min(result.before.min_angle_degrees, 10.0),
  )
  assert_true(
    result.after.mean_triangle_quality > result.before.mean_triangle_quality,
  )
  let positions = result.output.mesh.to_indexed().positions()
  let values = result.output.attributes[0].values()
  for i, p in positions {
    assert_true(p.z.abs() < 1.0e-12)
    assert_true((values[i][0] - p.x - 2.0 * p.y).abs() < 1.0e-10)
  }
  for i, face in result.output.mesh.to_indexed().faces() {
    let uv = result.output.corner_uvs[i]
    for (v, p) in [(face.0, uv.a), (face.1, uv.b), (face.2, uv.c)] {
      assert_true(
        (positions[v].x - p.x).abs() < 1.0e-10 &&
        (positions[v].y - p.y).abs() < 1.0e-10,
      )
    }
  }
  for v in 0..<25 {
    if v < 5 || v >= 20 || v % 5 == 0 || v % 5 == 4 {
      let mapped = result.output.vertex_map[v]
      assert_true(mapped >= 0)
      assert_eq(result.output.mesh.position(mapped), input.position(v))
    }
  }
}

///|
test "zero attempt budget returns an owned valid unchanged model" {
  let input = uneven_grid()
  let result = @moonsurface.remesh_isotropic(input, 0.2, max_operations=0)
  assert_eq(result.report.stop, @moonsurface.OperationBudget)
  assert_eq(result.report.attempts, 0)
  assert_eq(result.output.mesh.to_indexed(), input.compact().mesh.to_indexed())
  result.output.mesh.split_edge(result.output.mesh.find_edge(0, 1).unwrap())
  |> ignore
  assert_eq(input.vertex_count(), 25)
}

///|
test "storage ceiling is an explicit remesh stop and preserves the input" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: 0.0, y: 1.0, z: 0.0, },
    ],
    [(0, 1, 2)],
    limits=@moonsurface.Limits::new(max_vertices=3),
  )
  let model = @moonsurface.Model::new(mesh)
  let result = @moonsurface.remesh_isotropic(model, 0.1)
  assert_eq(result.report.stop, @moonsurface.StorageLimit)
  assert_eq(result.report.rejected_budget, 1)
  assert_eq(result.output.mesh.to_indexed(), mesh.to_indexed())
}

///|
test "remeshing retains material crease and independent UV islands" {
  let input = @moonsurface.Model::new(
    @moonsurface.Mesh::from_indexed(
      [
        { x: 0.0, y: 0.0, z: 0.0, },
        { x: 1.0, y: 0.0, z: 0.0, },
        { x: 0.0, y: 1.0, z: 0.0, },
        { x: 0.0, y: 0.0, z: 1.0, },
      ],
      [(0, 1, 2), (1, 0, 3)],
    ),
    materials=[7, 11],
    corner_uvs=[
      {
        a: { x: 0.0, y: 0.0, },
        b: { x: 1.0, y: 0.0, },
        c: { x: 0.0, y: 1.0, },
      },
      {
        a: { x: 11.0, y: 0.0, },
        b: { x: 10.0, y: 0.0, },
        c: { x: 10.0, y: 1.0, },
      },
    ],
  )
  let result = @moonsurface.remesh_isotropic(
    input,
    0.3,
    iterations=2,
    max_operations=3000,
  )
  result.output.mesh.validate()
  let positions = result.output.mesh.to_indexed().positions()
  for i, uv in result.output.corner_uvs {
    let material = result.output.materials[i]
    for p in [uv.a, uv.b, uv.c] {
      assert_true((material == 7 && p.x < 2.0) || (material == 11 && p.x > 9.0))
    }
  }
  let mut crease_length = 0.0
  for (a, b) in result.output.feature_edges {
    let p = positions[a]
    let q = positions[b]
    if p.y == 0.0 && p.z == 0.0 && q.y == 0.0 && q.z == 0.0 {
      crease_length += (p.x - q.x).abs()
    }
  }
  assert_true((crease_length - 1.0).abs() < 1.0e-12)
}
