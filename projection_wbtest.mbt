///|
test "triangle projection has analytic interior edge and vertex barycentrics" {
  let a = Vec3::{ x: 0.0, y: 0.0, z: 0.0, }
  let b = Vec3::{ x: 2.0, y: 0.0, z: 0.0, }
  let c = Vec3::{ x: 0.0, y: 2.0, z: 0.0, }
  let hit = triangle_hit(a, b, c, { x: 0.5, y: 0.5, z: 1.0, }, 0)
  assert_eq(hit.point, { x: 0.5, y: 0.5, z: 0.0, })
  assert_eq(hit.weights, (0.5, 0.25, 0.25))
  assert_eq(triangle_hit(a, b, c, { x: 1.0, y: -1.0, z: 0.0, }, 0).point, {
    x: 1.0,
    y: 0.0,
    z: 0.0,
  })
  assert_eq(triangle_hit(a, b, c, { x: -1.0, y: -1.0, z: 0.0, }, 0).point, a)
}

///|
test "projection forest isolates overlapping material charts and owns its source" {
  let model = Model::new(
    Mesh::from_indexed(
      [
        { x: 0.0, y: 0.0, z: 0.0, },
        { x: 2.0, y: 0.0, z: 0.0, },
        { x: 0.0, y: 2.0, z: 0.0, },
        { x: 0.0, y: 0.0, z: 0.1, },
        { x: 2.0, y: 0.0, z: 0.1, },
        { x: 0.0, y: 2.0, z: 0.1, },
      ],
      [(0, 1, 2), (3, 4, 5)],
    ),
    materials=[3, 7],
    attributes=[
      VertexAttribute::new("field", 1, Linear, [[1], [1], [1], [9], [9], [9]]),
    ],
    corner_uvs=[
      {
        a: { x: 0.0, y: 0.0, },
        b: { x: 1.0, y: 0.0, },
        c: { x: 0.0, y: 1.0, },
      },
      {
        a: { x: 10.0, y: 10.0, },
        b: { x: 11.0, y: 10.0, },
        c: { x: 10.0, y: 11.0, },
      },
    ],
  )
  let reference = ReferenceSurface::new(model.state)
  // Reference queries use Model's centered, normalized coordinate system.
  let query = Vec3::{ x: -0.5, y: -0.5, z: 0.04, }
  let lower = reference.closest(query, 0)
  let upper = reference.closest(query, 1)
  assert_true((lower.point.z + 0.05).abs() < 1.0e-12)
  assert_true((upper.point.z - 0.05).abs() < 1.0e-12)
  assert_eq(reference.sample(lower).rows[0], [1.0])
  assert_eq(reference.sample(upper).rows[0], [9.0])
  model.state.points[0] = { x: 90.0, y: 90.0, z: 90.0, }
  model.state.attributes[0].data[0][0] = 77.0
  assert_eq(reference.closest(query, 0).point, lower.point)
  assert_eq(reference.sample(lower).rows[0], [1.0])
  try reference.closest(query, 999) catch {
    e => assert_true(e is NumericalFailure(_))
  } noraise {
    _ => fail("unknown reference patch accepted")
  }
}

///|
test "reference compaction drops retired faces while retaining surviving patches" {
  let model = Model::new(
    Mesh::from_indexed(
      [
        { x: 0.0, y: 0.0, z: 0.0, },
        { x: 2.0, y: 0.0, z: 0.0, },
        { x: 0.0, y: 2.0, z: 0.0, },
      ],
      [(0, 1, 2)],
    ),
  )
  model.split_edge(0, 1) |> ignore
  assert_eq(model.state.faces.length(), 3)
  let reference = ReferenceSurface::new(model.state)
  assert_eq(reference.faces.length(), 2)
  assert_eq(reference.closest({ x: -0.75, y: -0.75, z: 1.0, }, 0).point, {
    x: -0.75,
    y: -0.75,
    z: 0.0,
  })
}
