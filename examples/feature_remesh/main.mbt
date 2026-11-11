///|
fn main {
  try! ({
    let positions : Array[@surface.Vec3] = [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: 0.0, y: 1.0, z: 0.0, },
      { x: 0.0, y: 0.0, z: 1.0, },
    ]
    let model = @surface.Model::new(
      @surface.Mesh::from_indexed(positions, [(0, 1, 2), (1, 0, 3)]),
      materials=[7, 11],
      corner_uvs=[
        {
          a: { x: 0.0, y: 0.0, },
          b: { x: 1.0, y: 0.0, },
          c: { x: 0.0, y: 1.0, },
        },
        {
          a: { x: 11.0, y: 0.0, },
          b: { x: 10.0, y: 0.0, },
          c: { x: 10.0, y: 1.0, },
        },
      ],
      attributes=[
        @surface.VertexAttribute::new(
          "position_probe",
          3,
          @surface.Linear,
          positions.map(fn(p) { [p.x, p.y, p.z] }),
        ),
        @surface.VertexAttribute::new("class", 1, @surface.Discrete, [
          [7],
          [7],
          [7],
          [7],
        ]),
      ],
    )
    let result = @surface.remesh_isotropic(
      model,
      0.3,
      iterations=2,
      max_operations=3000,
    )
    result.output.mesh.validate()
    assert_eq(result.output.attributes.length(), 2)
    assert_true(
      result.output.materials.contains(7) &&
      result.output.materials.contains(11),
    )
    let p = result.output.mesh.to_indexed().positions()
    let values = result.output.attributes[0].values()
    let mut length = 0.0
    for i, v in p {
      assert_true(
        (values[i][0] - v.x).abs() < 1.0e-12 &&
        (values[i][1] - v.y).abs() < 1.0e-12 &&
        (values[i][2] - v.z).abs() < 1.0e-12,
      )
    }
    for (a, b) in result.output.feature_edges {
      if p[a].y == 0.0 && p[a].z == 0.0 && p[b].y == 0.0 && p[b].z == 0.0 {
        length += (p[a].x - p[b].x).abs()
      }
    }
    assert_true((length - 1.0).abs() < 1.0e-12)
    println("feature_remesh: attributes=2 materials=2 protected_crease=true")
  })
}
