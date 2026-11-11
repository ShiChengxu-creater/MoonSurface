///|
fn triangle_model(
  attrs : Array[@moonsurface.VertexAttribute],
) -> @moonsurface.Model raise @moonsurface.SurfaceError {
  @moonsurface.Model::new(
    @moonsurface.Mesh::from_indexed(
      [
        { x: 0.0, y: 0.0, z: 0.0, },
        { x: 2.0, y: 0.0, z: 0.0, },
        { x: 0.0, y: 2.0, z: 0.0, },
      ],
      [(0, 1, 2)],
    ),
    attributes=attrs,
  )
}

///|
test "model split interpolates owned numeric channels and unit normals" {
  let model = triangle_model([
    @moonsurface.VertexAttribute::new("color", 3, @moonsurface.Linear, [
      [0, 0, 0],
      [1, 0, 0],
      [0, 1, 0],
    ]),
    @moonsurface.VertexAttribute::new("normal", 3, @moonsurface.UnitVector, [
      [0, 0, 2],
      [0, 2, 0],
      [2, 0, 0],
    ]),
  ])
  let v = model.split_edge(0, 1, fraction=0.25)
  assert_eq(v, 3)
  let output = model.compact()
  output.mesh.validate()
  assert_eq(output.mesh.position(v), { x: 0.5, y: 0.0, z: 0.0, })
  assert_eq(output.attributes[0].values()[3], [0.25, 0.0, 0.0])
  let n = output.attributes[1].values()[3]
  assert_true((n[1] * n[1] + n[2] * n[2] - 1.0).abs() < 1.0e-12)
  let detached = output.attributes[0].values()
  detached[0][0] = 99.0
  assert_eq(model.compact().attributes[0].values()[0][0], 0.0)
}

///|
test "discrete conflicts and cancelling normals reject before edits" {
  for
    attr in [
      @moonsurface.VertexAttribute::new("label", 1, @moonsurface.Discrete, [
        [1],
        [2],
        [1],
      ]),
      @moonsurface.VertexAttribute::new("normal", 3, @moonsurface.UnitVector, [
        [1, 0, 0],
        [-1, 0, 0],
        [0, 1, 0],
      ]),
    ] {
    let model = triangle_model([attr])
    let before = model.compact()
    try model.split_edge(0, 1) catch {
      _ => ()
    } noraise {
      _ => fail("invalid interpolation accepted")
    }
    assert_eq(model.compact().mesh.to_indexed(), before.mesh.to_indexed())
    assert_eq(model.vertex_count(), 3)
  }
}

///|
test "UV seam splitting keeps independent corner values and protects edits" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 1.0, z: 0.0, },
      { x: 0.0, y: 1.0, z: 0.0, },
    ],
    [(0, 1, 2), (0, 2, 3)],
  )
  let model = @moonsurface.Model::new(mesh, corner_uvs=[
    { a: { x: 0.0, y: 0.0, }, b: { x: 1.0, y: 0.0, }, c: { x: 1.0, y: 1.0, }, },
    {
      a: { x: 10.0, y: 10.0, },
      b: { x: 11.0, y: 11.0, },
      c: { x: 10.0, y: 11.0, },
    },
  ])
  assert_true(model.is_protected(0, 2))
  let before = model.compact().mesh.to_indexed()
  try model.flip_edge(0, 2) catch {
    e => assert_true(e is @moonsurface.ProtectedFeature(0, 2))
  } noraise {
    _ => fail("seam flipped")
  }
  assert_eq(model.compact().mesh.to_indexed(), before)
  let v = model.split_edge(0, 2)
  assert_true(model.is_protected(0, v) && model.is_protected(v, 2))
  let output = model.compact()
  assert_eq(output.corner_uvs.length(), 4)
  for uv in output.corner_uvs {
    for p in [uv.a, uv.b, uv.c] {
      assert_true(p.x < 2.0 || p.x > 9.0)
    }
  }
  output.mesh.validate()
}

///|
test "material and dihedral features are retained and normals stay discontinuous" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: 0.0, y: 1.0, z: 0.0, },
      { x: 0.0, y: 0.0, z: 1.0, },
    ],
    [(0, 1, 2), (1, 0, 3)],
  )
  let model = @moonsurface.Model::new(mesh, materials=[3, 7])
  assert_true(model.is_protected(0, 1))
  let normals = model.corner_normals()
  assert_true((normals[0].0.z - 1.0).abs() < 1.0e-12)
  assert_true(normals[1].0.z.abs() < 1.0e-12)
  model.split_edge(0, 1) |> ignore
  assert_eq(model.compact().materials, [3, 3, 7, 7])
}

///|
test "local collapse compacts once with explicit deleted vertex mapping" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: -1.0, y: 0.0, z: 0.0, },
      { x: 0.0, y: 1.0, z: 0.0, },
      { x: 0.0, y: -1.0, z: 0.0, },
      { x: 0.0, y: 0.0, z: 1.0, },
      { x: 0.0, y: 0.0, z: -1.0, },
    ],
    [
      (0, 2, 4),
      (2, 1, 4),
      (1, 3, 4),
      (3, 0, 4),
      (2, 0, 5),
      (1, 2, 5),
      (3, 1, 5),
      (0, 3, 5),
    ],
  )
  let model = @moonsurface.Model::new(mesh, sharp_angle_degrees=180.0)
  model.collapse_edge(0, 2)
  let result = model.compact()
  result.mesh.validate()
  assert_eq(result.vertex_map, [0, 1, -1, 2, 3, 4])
  assert_eq(
    (
      result.mesh.vertex_count(),
      result.mesh.face_count(),
      result.mesh.stats().euler,
    ),
    (5, 6, 2),
  )
  try model.position(2) catch {
    _ => ()
  } noraise {
    _ => fail("deleted vertex accessible")
  }
  assert_eq(mesh.vertex_count(), 6)
}
