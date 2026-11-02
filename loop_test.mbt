///|
test "Loop moves old tetrahedron vertices and weights opposite edge vertices" {
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
  let before = mesh.to_indexed()
  let refined = mesh.loop_step()
  refined.validate()
  assert_eq(
    (refined.vertex_count(), refined.edge_count(), refined.face_count()),
    (10, 24, 16),
  )
  assert_eq((refined.stats().euler, refined.stats().boundary_edges), (2, 0))
  for v in 0..<4 {
    let q = refined.position(v)
    assert_true((q.x - 0.25 * p[v].x).abs() < 1.0e-12)
    assert_true((q.y - 0.25 * p[v].y).abs() < 1.0e-12)
    assert_true((q.z - 0.25 * p[v].z).abs() < 1.0e-12)
  }
  let @moonsurface.EdgeId(e) = mesh.find_edge(0, 2).unwrap()
  let q = refined.position(4 + e)
  assert_true(
    q.x.abs() < 1.0e-12 && (q.y - 0.5).abs() < 1.0e-12 && q.z.abs() < 1.0e-12,
  )
  assert_eq(mesh.to_indexed(), before)
}

///|
test "boundary stencils use boundary neighbors and preserve topological disk" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 2.0, y: 0.0, z: 0.0, },
      { x: 0.0, y: 2.0, z: 0.0, },
    ],
    [(0, 1, 2)],
  )
  let result = mesh.loop_step()
  result.validate()
  assert_eq(result.position(0), { x: 0.25, y: 0.25, z: 0.0, })
  assert_eq(
    (result.vertex_count(), result.edge_count(), result.face_count()),
    (6, 9, 4),
  )
  assert_eq(
    (result.stats().boundary_edges, result.stats().boundary_loops),
    (6, 1),
  )
  assert_eq(@moonsurface.Mesh::from_indexed([], []).loop_step().face_count(), 0)
}

///|
test "output budget is checked before allocating a refined mesh" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: 0.0, y: 1.0, z: 0.0, },
    ],
    [(0, 1, 2)],
    limits=@moonsurface.Limits::new(max_output_faces=3),
  )
  let before = mesh.to_indexed()
  try mesh.loop_step() catch {
    e => assert_true(e is @moonsurface.LimitExceeded("Loop faces"))
  } noraise {
    _ => fail("over-budget refinement accepted")
  }
  assert_eq(mesh.to_indexed(), before)
}
