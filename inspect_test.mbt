///|
test "annulus has two boundary loops and no false connected-component split" {
  let p : Array[@moonsurface.Vec3] = [
    { x: -2.0, y: -2.0, z: 0.0, },
    { x: 2.0, y: -2.0, z: 0.0, },
    { x: 2.0, y: 2.0, z: 0.0, },
    { x: -2.0, y: 2.0, z: 0.0, },
    { x: -1.0, y: -1.0, z: 0.0, },
    { x: 1.0, y: -1.0, z: 0.0, },
    { x: 1.0, y: 1.0, z: 0.0, },
    { x: -1.0, y: 1.0, z: 0.0, },
  ]
  let faces = []
  for i in 0..<4 {
    let j = (i + 1) % 4
    faces.push((i, j, 4 + j))
    faces.push((i, 4 + j, 4 + i))
  }
  let mesh = @moonsurface.Mesh::from_indexed(p, faces)
  mesh.validate()
  let s = mesh.stats()
  assert_eq((s.vertices, s.edges, s.faces), (8, 16, 8))
  assert_eq(
    (s.boundary_edges, s.boundary_loops, s.components, s.euler),
    (8, 2, 1, 0),
  )
  for ring in mesh.boundary_loops() {
    assert_eq(ring.length(), 4)
  }
  let copy = mesh.to_indexed()
  assert_eq(copy.faces(), faces)
  assert_eq(copy.positions(), p)
  @moonsurface.Mesh::from_indexed(copy.positions(), copy.faces()).validate()
}

///|
test "disconnected and empty topology statistics are well defined" {
  let p : Array[@moonsurface.Vec3] = [
    { x: 0.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 0.0, z: 0.0, },
    { x: 0.0, y: 1.0, z: 0.0, },
    { x: 0.0, y: 0.0, z: 1.0, },
    { x: 1.0, y: 0.0, z: 1.0, },
    { x: 0.0, y: 1.0, z: 1.0, },
  ]
  let mesh = @moonsurface.Mesh::from_indexed(p, [(0, 1, 2), (3, 4, 5)])
  mesh.validate()
  assert_eq((mesh.stats().components, mesh.stats().euler), (2, 2))
  let empty = @moonsurface.Mesh::from_indexed([], [])
  empty.validate()
  assert_eq(empty.stats().components, 0)
  try mesh.edge_vertices(@moonsurface.EdgeId(-1)) catch {
    e => assert_true(e is @moonsurface.InvalidElement(-1))
  } noraise {
    _ => fail("invalid edge accepted")
  }
}
