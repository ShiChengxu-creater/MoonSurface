///|
test "indexed data is owned and valid empty input stays empty" {
  let points : Array[@moonsurface.Vec3] = [
    { x: 0.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 0.0, z: 0.0, },
    { x: 0.0, y: 1.0, z: 0.0, },
  ]
  let faces = [(0, 1, 2)]
  let indexed = @moonsurface.IndexedMesh::new(points, faces)
  points[0] = { x: 50.0, y: 0.0, z: 0.0, }
  faces[0] = (2, 1, 0)
  let copy = indexed.positions()
  copy[0] = points[0]
  assert_eq(indexed.positions()[0].x, 0.0)
  assert_eq(indexed.faces(), [(0, 1, 2)])
  assert_eq(@moonsurface.IndexedMesh::new([], []).faces().length(), 0)
}

///|
test "invalid index duplicate winding and degenerate geometry are rejected" {
  let p : Array[@moonsurface.Vec3] = [
    { x: 0.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 0.0, z: 0.0, },
    { x: 0.0, y: 1.0, z: 0.0, },
  ]
  try @moonsurface.IndexedMesh::new(p, [(0, 1, 3)]) catch {
    e => assert_true(e is @moonsurface.InvalidIndex(0, 3))
  } noraise {
    _ => fail("invalid index accepted")
  }
  try @moonsurface.IndexedMesh::new(p, [(0, 1, 2), (2, 1, 0)]) catch {
    e => assert_true(e is @moonsurface.DuplicateFace(1))
  } noraise {
    _ => fail("duplicate accepted")
  }
  try @moonsurface.IndexedMesh::new(p, [(0, 1, 1)]) catch {
    e => assert_true(e is @moonsurface.DegenerateFace(0))
  } noraise {
    _ => fail("degenerate accepted")
  }
}

///|
test "finite extreme geometry and unreferenced vertices have explicit semantics" {
  for scale in [1.0e-300, 1.0e300] {
    let p : Array[@moonsurface.Vec3] = [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: scale, y: 0.0, z: 0.0, },
      { x: 0.0, y: scale, z: 0.0, },
    ]
    assert_eq(@moonsurface.IndexedMesh::new(p, [(0, 1, 2)]).faces().length(), 1)
  }
  try @moonsurface.IndexedMesh::new([{ x: 0.0, y: 0.0, z: 0.0, }], []) catch {
    e => assert_true(e is @moonsurface.IsolatedVertex(0))
  } noraise {
    _ => fail("isolated vertex accepted")
  }
  try
    @moonsurface.IndexedMesh::new([{ x: 1.0 / 0.0, y: 0.0, z: 0.0, }], [])
  catch {
    e => assert_true(e is @moonsurface.NonFiniteCoordinate(0))
  } noraise {
    _ => fail("infinite coordinate accepted")
  }
}

///|
test "input count budgets run before geometry validation" {
  let limits = @moonsurface.Limits::new(max_input_faces=0)
  try @moonsurface.IndexedMesh::new([], [(0, 1, 2)], limits~) catch {
    e => assert_true(e is @moonsurface.LimitExceeded("input faces"))
  } noraise {
    _ => fail("budget accepted")
  }
}
