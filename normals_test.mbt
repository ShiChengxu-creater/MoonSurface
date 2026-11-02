///|
test "face and area-weighted vertex normals survive extreme coordinate scales" {
  for scale in [1.0e-300, 1.0, 1.0e300] {
    let mesh = @moonsurface.Mesh::from_indexed(
      [
        { x: 0.0, y: 0.0, z: 0.0, },
        { x: scale, y: 0.0, z: 0.0, },
        { x: 0.0, y: scale, z: 0.0, },
      ],
      [(0, 1, 2)],
    )
    assert_eq(mesh.face_normals(), [{ x: 0.0, y: 0.0, z: 1.0, }])
    for normal in mesh.vertex_normals() {
      assert_eq(normal, { x: 0.0, y: 0.0, z: 1.0, })
    }
  }
  assert_eq(
    @moonsurface.Mesh::from_indexed([], []).vertex_normals().length(),
    0,
  )
}

///|
test "area weighting is not an unweighted average of face normals" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: 0.0, y: 2.0, z: 0.0, },
      { x: 0.0, y: 0.0, z: 1.0, },
    ],
    [(0, 1, 2), (1, 0, 3)],
  )
  let normal = mesh.vertex_normals()[0]
  assert_true(normal.x.abs() < 1.0e-12)
  assert_true((normal.z / normal.y - 2.0).abs() < 1.0e-12)
  let copy = mesh.copy()
  ignore(copy.split_edge(copy.find_edge(0, 1).unwrap()))
  copy.validate()
  for q in copy.vertex_normals() {
    assert_true((q.x * q.x + q.y * q.y + q.z * q.z - 1.0).abs() < 1.0e-12)
  }
}
