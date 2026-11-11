///|
test "triangle projection has analytic interior edge and vertex barycentrics" {
  let a = Vec3::{ x: 0.0, y: 0.0, z: 0.0, }
  let b = Vec3::{ x: 2.0, y: 0.0, z: 0.0, }
  let c = Vec3::{ x: 0.0, y: 2.0, z: 0.0, }
  let hit = triangle_hit(a, b, c, { x: 0.5, y: 0.5, z: 1.0, }, 0)
  assert_eq(hit.point, { x: 0.5, y: 0.5, z: 0.0, })
  assert_eq(hit.weights, (0.5, 0.25, 0.25))
  assert_eq(triangle_hit(a, b, c, { x: 1.0, y: -1.0, z: 0.0, }, 0).point, {
    x: 1.0,
    y: 0.0,
    z: 0.0,
  })
  assert_eq(triangle_hit(a, b, c, { x: -1.0, y: -1.0, z: 0.0, }, 0).point, a)
}
