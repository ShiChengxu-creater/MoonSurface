///|
fn original_id(mapping : Array[Int], dense : Int) -> Int {
  for id, value in mapping {
    if value == dense {
      return id
    }
  }
  -1
}

///|
fn same_model_snapshot(
  a : @moonsurface.ModelSnapshot,
  b : @moonsurface.ModelSnapshot,
) -> Unit raise {
  assert_eq(a.mesh.to_indexed(), b.mesh.to_indexed())
  assert_eq(a.corner_uvs, b.corner_uvs)
  assert_eq(a.materials, b.materials)
  assert_eq(a.feature_edges, b.feature_edges)
  assert_eq(a.vertex_map, b.vertex_map)
  assert_eq(a.face_map, b.face_map)
  assert_eq(a.face_charts, b.face_charts)
  assert_eq(a.attributes.length(), b.attributes.length())
  for i in 0..<a.attributes.length() {
    assert_eq(a.attributes[i].values(), b.attributes[i].values())
  }
}

///|
test "seeded model edit chains preserve topology fields and rejected-state snapshots" {
  let mut splits = 0
  let mut flips = 0
  let mut collapses = 0
  let mut rejected = 0
  for seed in [113, 701, 2027, 6111] {
    let model = uneven_grid()
    let mut rng = seed
    for _ in 0..<120 {
      let before = model.compact()
      rng = (25173 * rng + 13849) % 65536
      let faces = before.mesh.to_indexed().faces()
      let face = faces[rng % faces.length()]
      let a = original_id(before.vertex_map, face.0)
      let b = original_id(before.vertex_map, face.1)
      assert_true(a >= 0 && b >= 0)
      let kind = rng / 256 % 3
      try {
        if kind == 0 {
          model.split_edge(a, b, fraction=0.4) |> ignore
          splits += 1
        } else if kind == 1 {
          model.flip_edge(a, b)
          flips += 1
        } else {
          model.collapse_edge(a, b, fraction=0.5)
          collapses += 1
        }
      } catch {
        _ => {
          rejected += 1
          same_model_snapshot(before, model.compact())
        }
      }
      let after = model.compact()
      after.mesh.validate()
      assert_eq(after.mesh.stats().euler, 1)
      assert_eq(after.mesh.stats().components, 1)
      let field = after.attributes[0].values()
      for v, p in after.mesh.to_indexed().positions() {
        assert_true((field[v][0] - p.x - 2.0 * p.y).abs() < 1.0e-10)
      }
      for i, f in after.mesh.to_indexed().faces() {
        let uv = after.corner_uvs[i]
        for (v, u) in [(f.0, uv.a), (f.1, uv.b), (f.2, uv.c)] {
          let p = after.mesh.position(v)
          assert_true(
            (p.x - u.x).abs() < 1.0e-10 && (p.y - u.y).abs() < 1.0e-10,
          )
        }
      }
    }
  }
  assert_true(splits > 50 && flips > 0 && collapses > 0 && rejected > 50)
}

///|
test "repeated remesh and compact reimport keep analytic data and pinned boundary" {
  let mut model = uneven_grid()
  for target in [0.25, 0.19, 0.28] {
    let result = @moonsurface.remesh_isotropic(
      model,
      target,
      iterations=1,
      max_operations=2000,
    )
    let output = result.output
    output.mesh.validate()
    assert_eq(output.mesh.stats().euler, 1)
    let rows = output.attributes[0].values()
    for v, p in output.mesh.to_indexed().positions() {
      assert_true((rows[v][0] - p.x - 2.0 * p.y).abs() < 1.0e-10)
    }
    model = @moonsurface.Model::new(
      output.mesh,
      attributes=output.attributes,
      corner_uvs=output.corner_uvs,
      materials=output.materials,
      feature_edges=output.feature_edges,
    )
    for (a, b) in output.feature_edges {
      assert_true(model.is_protected(a, b))
    }
  }
}

///|
test "slot failure leaves model attributes and identifiers unchanged" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: 0.0, y: 1.0, z: 0.0, },
    ],
    [(0, 1, 2)],
    limits=@moonsurface.Limits::new(max_vertices=3),
  )
  let model = @moonsurface.Model::new(mesh, attributes=[
    @moonsurface.VertexAttribute::new("field", 1, @moonsurface.Linear, [
      [0],
      [1],
      [1],
    ]),
  ])
  let before = model.compact()
  try model.split_edge(0, 1) catch {
    e => assert_true(e is @moonsurface.LimitExceeded(_))
  } noraise {
    _ => fail("vertex slot ceiling ignored")
  }
  same_model_snapshot(before, model.compact())
}

///|
test "explicit coplanar feature alone protects flip and inherited children" {
  let mesh = @moonsurface.Mesh::from_indexed(
    [
      { x: 0.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 0.0, z: 0.0, },
      { x: 1.0, y: 1.0, z: 0.0, },
      { x: 0.0, y: 1.0, z: 0.0, },
    ],
    [(0, 1, 2), (0, 2, 3)],
  )
  let plain = @moonsurface.Model::new(mesh)
  assert_true(!plain.is_protected(0, 2))
  let tagged = @moonsurface.Model::new(mesh, feature_edges=[(2, 0)])
  let before = tagged.compact()
  try tagged.flip_edge(0, 2) catch {
    e => assert_true(e is @moonsurface.ProtectedFeature(_, _))
  } noraise {
    _ => fail("explicit feature flipped")
  }
  same_model_snapshot(before, tagged.compact())
  let vertex = tagged.split_edge(2, 0, fraction=0.25)
  assert_true(tagged.is_protected(2, vertex) && tagged.is_protected(vertex, 0))
}

///|
test "empty and zero iteration remeshing return finite detached snapshots" {
  let empty = @moonsurface.Model::new(@moonsurface.Mesh::from_indexed([], []))
  let result = @moonsurface.remesh_isotropic(empty, 0.5)
  assert_eq(result.output.mesh.face_count(), 0)
  assert_eq(result.report.stop, @moonsurface.StableUnderConstraints)
  assert_eq(result.report.attempts, 0)
  assert_eq(result.after.mean_triangle_quality, 0.0)
  let model = uneven_grid()
  let snapshot = model.compact()
  let zero = @moonsurface.remesh_isotropic(model, 0.2, iterations=0)
  assert_eq(zero.report.stop, @moonsurface.IterationLimit)
  assert_eq(zero.report.iterations, 0)
  same_model_snapshot(snapshot, zero.output)
}

///|
test "invalid remesh options reject without changing the input" {
  let model = uneven_grid()
  let before = model.compact()
  for i in 0..<6 {
    try {
      if i == 0 {
        @moonsurface.remesh_isotropic(model, 0.0) |> ignore
      } else if i == 1 {
        @moonsurface.remesh_isotropic(model, 0.2, iterations=11) |> ignore
      } else if i == 2 {
        @moonsurface.remesh_isotropic(model, 0.2, max_operations=-1) |> ignore
      } else if i == 3 {
        @moonsurface.remesh_isotropic(model, 0.2, relaxation=1.1) |> ignore
      } else if i == 4 {
        @moonsurface.remesh_isotropic(model, 0.2, minimum_angle=61) |> ignore
      } else {
        @moonsurface.remesh_isotropic(model, 0.2, max_deviation=-1.0) |> ignore
      }
    } catch {
      e => assert_true(e is @moonsurface.InvalidArgument(_))
    } noraise {
      _ => fail("invalid options accepted")
    }
    same_model_snapshot(before, model.compact())
  }
}
