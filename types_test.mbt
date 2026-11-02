///|
test "default budgets and zero budgets are explicit" {
  let limits = @moonsurface.Limits::new()
  assert_eq(limits.vertex_limit(), 1_000_000)
  assert_eq(limits.input_face_limit(), 250_000)
  assert_eq(limits.output_face_limit(), 1_000_000)
  assert_eq(limits.level_limit(), 6)
  let zero = @moonsurface.Limits::new(max_vertices=0, max_input_faces=0)
  assert_eq(zero.vertex_limit(), 0)
}

///|
test "invalid count limits are recoverable" {
  for (vertices, faces, levels) in [(-1, 1, 0), (1, 1_000_001, 0), (1, 1, 7)] {
    try
      @moonsurface.Limits::new(
        max_vertices=vertices,
        max_output_faces=faces,
        max_levels=levels,
      )
    catch {
      e => assert_true(e is @moonsurface.InvalidArgument(_))
    } noraise {
      _ => fail("invalid budget was accepted")
    }
  }
}
