///|
test "preflight matches actual closed and open multi-level counts" {
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
  let result = @moonsurface.subdivide_loop(mesh, 2)
  result.mesh.validate()
  assert_eq(result.stages.length(), 3)
  assert_eq(result.stages[2], result.mesh.stats())
  assert_eq(
    (
      result.mesh.vertex_count(),
      result.mesh.edge_count(),
      result.mesh.face_count(),
    ),
    (34, 96, 64),
  )
  assert_eq(mesh.to_indexed(), before)
  let open = @moonsurface.Mesh::from_indexed(before.positions(), [
    (0, 1, 2),
    (2, 1, 3),
  ])
  let refined = @moonsurface.subdivide_loop(open, 2)
  assert_eq(refined.stages[2], refined.mesh.stats())
  assert_eq(refined.mesh.stats().boundary_edges, 16)
}

///|
test "all requested budgets are checked and zero levels returns detached storage" {
  let p : Array[@moonsurface.Vec3] = [
    { x: 0.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 0.0, z: 0.0, },
    { x: 0.0, y: 1.0, z: 0.0, },
  ]
  let mesh = @moonsurface.Mesh::from_indexed(p, [(0, 1, 2)])
  let result = @moonsurface.subdivide_loop(mesh, 0)
  ignore(result.mesh.split_edge(result.mesh.find_edge(0, 1).unwrap()))
  assert_eq(mesh.vertex_count(), 3)
  for count in [-1, 7] {
    try @moonsurface.subdivide_loop(mesh, count) catch {
      e =>
        assert_true(
          e is @moonsurface.InvalidArgument(_) ||
          e is @moonsurface.LimitExceeded(_),
        )
    } noraise {
      _ => fail("invalid level count accepted")
    }
  }
  let limited = @moonsurface.Mesh::from_indexed(
    p,
    [(0, 1, 2)],
    limits=@moonsurface.Limits::new(max_input_faces=1, max_output_faces=16),
  )
  assert_eq(@moonsurface.subdivide_loop(limited, 2).mesh.face_count(), 16)
  let narrow = @moonsurface.Mesh::from_indexed(
    p,
    [(0, 1, 2)],
    limits=@moonsurface.Limits::new(max_output_faces=15),
  )
  let before = narrow.to_indexed()
  try @moonsurface.subdivide_loop(narrow, 2) catch {
    e => assert_true(e is @moonsurface.LimitExceeded("Loop faces"))
  } noraise {
    _ => fail("final-level budget accepted")
  }
  assert_eq(narrow.to_indexed(), before)
  let zero = @moonsurface.Mesh::from_indexed(
    p,
    [(0, 1, 2)],
    limits=@moonsurface.Limits::new(max_levels=0),
  )
  try zero.loop_step() catch {
    e => assert_true(e is @moonsurface.LimitExceeded("Loop levels"))
  } noraise {
    _ => fail("single-step level budget bypassed")
  }
}
