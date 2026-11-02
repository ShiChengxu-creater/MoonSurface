///|
test "closed tetrahedron and open patch expose valid one-rings" {
  let p : Array[@moonsurface.Vec3] = [
    { x: 1.0, y: 1.0, z: 1.0, },
    { x: -1.0, y: -1.0, z: 1.0, },
    { x: -1.0, y: 1.0, z: -1.0, },
    { x: 1.0, y: -1.0, z: -1.0, },
  ]
  let mesh = @moonsurface.Mesh::from_indexed(p, [
    (0, 2, 1),
    (0, 1, 3),
    (0, 3, 2),
    (1, 2, 3),
  ])
  assert_eq(
    (mesh.vertex_count(), mesh.edge_count(), mesh.face_count()),
    (4, 6, 4),
  )
  for v in 0..<4 {
    assert_eq(mesh.neighbors(v).length(), 3)
  }
  assert_true(mesh.find_edge(0, 2) is Some(_))
  assert_true(mesh.find_edge(0, 20) is None)
  let patch = @moonsurface.Mesh::from_indexed(p, [(0, 1, 2), (2, 1, 3)])
  assert_eq(
    (patch.vertex_count(), patch.edge_count(), patch.face_count()),
    (4, 5, 2),
  )
  assert_eq(patch.neighbors(1).length(), 3)
  assert_eq(patch.neighbors(0).length(), 2)
  assert_eq(@moonsurface.Mesh::from_indexed([], []).edge_count(), 0)
}

///|
test "orientation and three-face edges are rejected" {
  let p : Array[@moonsurface.Vec3] = [
    { x: 0.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 0.0, z: 0.0, },
    { x: 0.0, y: 1.0, z: 0.0, },
    { x: 0.0, y: -1.0, z: 0.0, },
  ]
  try @moonsurface.Mesh::from_indexed(p, [(0, 1, 2), (0, 1, 3)]) catch {
    e => assert_true(e is @moonsurface.InconsistentOrientation(0, 1))
  } noraise {
    _ => fail("orientation accepted")
  }
  let q = p.copy()
  q.push({ x: 0.0, y: 0.0, z: 1.0, })
  try
    @moonsurface.Mesh::from_indexed(q, [(0, 1, 2), (1, 0, 3), (0, 1, 4)])
  catch {
    e => assert_true(e is @moonsurface.NonManifoldEdge(0, 1))
  } noraise {
    _ => fail("three-face edge accepted")
  }
}

///|
test "closed bow-tie vertex cannot hide behind manifold edges" {
  let p : Array[@moonsurface.Vec3] = [
    { x: 0.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 0.0, z: 0.0, },
    { x: 0.0, y: 1.0, z: 0.0, },
    { x: 0.0, y: 0.0, z: 1.0, },
    { x: -1.0, y: 0.0, z: 0.0, },
    { x: 0.0, y: -1.0, z: 0.0, },
    { x: 0.0, y: 0.0, z: -1.0, },
  ]
  try
    @moonsurface.Mesh::from_indexed(p, [
      (0, 2, 1),
      (0, 1, 3),
      (0, 3, 2),
      (1, 2, 3),
      (0, 5, 4),
      (0, 4, 6),
      (0, 6, 5),
      (4, 5, 6),
    ])
  catch {
    e => assert_true(e is @moonsurface.NonManifoldVertex(0))
  } noraise {
    _ => fail("disconnected vertex fans accepted")
  }
}
