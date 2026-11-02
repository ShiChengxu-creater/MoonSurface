///|
test "interior split preserves the open patch topology and old vertex ids" {
  let p : Array[@moonsurface.Vec3] = [
    { x: 0.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 1.0, z: 0.0, },
    { x: 0.0, y: 1.0, z: 0.0, },
  ]
  let mesh = @moonsurface.Mesh::from_indexed(p, [(0, 1, 2), (0, 2, 3)])
  let edge = mesh.find_edge(0, 2).unwrap()
  let report = mesh.split_edge(edge)
  mesh.validate()
  assert_eq(report.vertex, 4)
  assert_eq(report.created_faces.length(), 2)
  assert_eq(
    (mesh.vertex_count(), mesh.edge_count(), mesh.face_count()),
    (5, 8, 4),
  )
  assert_eq((mesh.stats().euler, mesh.stats().boundary_edges), (1, 4))
  assert_eq(mesh.position(4), { x: 0.5, y: 0.5, z: 0.0, })
  for i in 0..<4 {
    assert_eq(mesh.position(i), p[i])
  }
  assert_true(mesh.find_edge(0, 2) is None)
}

///|
test "boundary split closes the exterior loop including reversed halfedge orientation" {
  for pair in [(0, 1), (1, 2), (0, 2)] {
    let mesh = @moonsurface.Mesh::from_indexed(
      [
        { x: 0.0, y: 0.0, z: 0.0, },
        { x: 1.0, y: 0.0, z: 0.0, },
        { x: 0.0, y: 1.0, z: 0.0, },
      ],
      [(0, 1, 2)],
    )
    let edge = mesh.find_edge(pair.0, pair.1).unwrap()
    let report = mesh.split_edge(edge, fraction=0.25)
    mesh.validate()
    assert_eq(report.created_faces.length(), 1)
    assert_eq(
      (mesh.vertex_count(), mesh.edge_count(), mesh.face_count()),
      (4, 5, 2),
    )
    assert_eq(mesh.boundary_loops()[0].length(), 4)
    assert_true(mesh.is_boundary_edge(edge))
  }
}

///|
test "split validation errors leave indexed data and topology unchanged" {
  let p : Array[@moonsurface.Vec3] = [
    { x: 0.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 0.0, z: 0.0, },
    { x: 0.0, y: 1.0, z: 0.0, },
  ]
  let mesh = @moonsurface.Mesh::from_indexed(p, [(0, 1, 2)])
  let before = mesh.to_indexed()
  for t in [0.0, 1.0, 1.0e-300] {
    try mesh.split_edge(mesh.find_edge(0, 1).unwrap(), fraction=t) catch {
      e =>
        assert_true(
          e is @moonsurface.InvalidArgument(_) ||
          e is @moonsurface.NumericalFailure(_),
        )
    } noraise {
      _ => fail("invalid split accepted")
    }
    assert_eq(mesh.to_indexed(), before)
    mesh.validate()
  }
  let limited = @moonsurface.Mesh::from_indexed(
    p,
    [(0, 1, 2)],
    limits=@moonsurface.Limits::new(max_output_faces=1),
  )
  try limited.split_edge(limited.find_edge(0, 1).unwrap()) catch {
    e => assert_true(e is @moonsurface.LimitExceeded("split faces"))
  } noraise {
    _ => fail("over-budget split accepted")
  }
  assert_eq(limited.to_indexed(), before)
  limited.validate()
}
