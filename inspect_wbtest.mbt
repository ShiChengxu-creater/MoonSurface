///|
test "audit refuses broken private connectivity" {
  let p : Array[Vec3] = [
    { x: 0.0, y: 0.0, z: 0.0, },
    { x: 1.0, y: 0.0, z: 0.0, },
    { x: 0.0, y: 1.0, z: 0.0, },
  ]
  let mesh = Mesh::from_indexed(p, [(0, 1, 2)])
  mesh.halfedges[0].next = -1
  try mesh.validate() catch {
    e => assert_true(e is TopologyInvariant("halfedge range"))
  } noraise {
    _ => fail("corrupted connection accepted")
  }
}
