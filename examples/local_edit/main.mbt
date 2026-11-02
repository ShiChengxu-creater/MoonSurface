///|
fn main {
  let points : Array[@surface.Vec3] = [
    { x: 0.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 1.0, z: 0.0, },
    { x: 0.0, y: 1.0, z: 0.0, },
  ]
  let mesh = try! @surface.Mesh::from_indexed(points, [(0, 1, 2), (0, 2, 3)])
  let diagonal = mesh.find_edge(0, 2).unwrap()
  ignore(try! mesh.flip_edge(diagonal))
  ignore(try! mesh.split_edge(diagonal))
  try! mesh.validate()
  let indexed = mesh.to_indexed()
  let reopened = try! @surface.Mesh::from_indexed(
    indexed.positions(),
    indexed.faces(),
  )
  try! assert_eq(mesh.stats(), reopened.stats())
  let normals = try! mesh.vertex_normals()
  try! assert_eq(normals.length(), 5)
  let s = mesh.stats()
  println(
    "local_edit: V=\{s.vertices} E=\{s.edges} F=\{s.faces} chi=\{s.euler} boundary=\{s.boundary_edges}",
  )
}
