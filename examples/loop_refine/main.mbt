///|
fn main {
  let mesh = try! @surface.Mesh::from_indexed(
    [
      { x: 1.0, y: 1.0, z: 1.0, },
      { x: -1.0, y: -1.0, z: 1.0, },
      { x: -1.0, y: 1.0, z: -1.0, },
      { x: 1.0, y: -1.0, z: -1.0, },
    ],
    [(0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3)],
  )
  let result = try! @surface.subdivide_loop(mesh, 2)
  try! result.mesh.validate()
  try! assert_eq(result.mesh.face_count(), 64)
  try! assert_eq(mesh.face_count(), 4)
  for level, s in result.stages {
    println(
      "loop_refine: level=\{level} V=\{s.vertices} E=\{s.edges} F=\{s.faces} chi=\{s.euler}",
    )
  }
}
