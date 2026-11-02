///|
test "flip updates local degrees lookup and one-rings without renumbering" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 1.0, z: 0.0, },
      { x: 0.0, y: 1.0, z: 0.0, },
    ],
    [(0, 1, 2), (0, 2, 3)],
  )
  let edge = mesh.find_edge(0, 2).unwrap()
  let before = mesh.stats()
  let report = mesh.flip_edge(edge)
  mesh.validate()
  assert_eq(report.edge, edge)
  assert_true(mesh.find_edge(0, 2) is None)
  assert_eq(mesh.find_edge(1, 3), Some(edge))
  assert_eq(mesh.neighbors(0).length(), 2)
  assert_eq(mesh.neighbors(1).length(), 3)
  assert_eq(mesh.stats(), before)
  ignore(mesh.flip_edge(edge))
  mesh.validate()
  assert_eq(mesh.find_edge(0, 2), Some(edge))
}

///|
test "boundary and duplicate diagonal failures preserve the complete snapshot" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 1.0, y: 1.0, z: 1.0, },
      { x: -1.0, y: -1.0, z: 1.0, },
      { x: -1.0, y: 1.0, z: -1.0, },
      { x: 1.0, y: -1.0, z: -1.0, },
    ],
    [(0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3)],
  )
  let before = mesh.to_indexed()
  try mesh.flip_edge(mesh.find_edge(0, 1).unwrap()) catch {
    e => assert_true(e is @moonsurface.DuplicateDiagonal(_, _))
  } noraise {
    _ => fail("duplicate diagonal accepted")
  }
  assert_eq(mesh.to_indexed(), before)
  let patch = @moonsurface.Mesh::from_indexed(before.positions(), [
    (0, 1, 2),
    (2, 1, 3),
  ])
  let snapshot = patch.to_indexed()
  try patch.flip_edge(patch.find_edge(0, 1).unwrap()) catch {
    e => assert_true(e is @moonsurface.BoundaryEdge(_))
  } noraise {
    _ => fail("boundary flip accepted")
  }
  assert_eq(patch.to_indexed(), snapshot)
  patch.validate()
}

///|
test "nonconvex planar flip refuses a local inversion without mutation" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: 0.2, y: 0.2, z: 0.0, },
      { x: 0.0, y: 1.0, z: 0.0, },
    ],
    [(0, 1, 2), (0, 2, 3)],
  )
  let before = mesh.to_indexed()
  try mesh.flip_edge(mesh.find_edge(0, 2).unwrap()) catch {
    e => assert_true(e is @moonsurface.NumericalFailure(_))
  } noraise {
    _ => fail("inverted flip accepted")
  }
  assert_eq(mesh.to_indexed(), before)
  mesh.validate()
}
