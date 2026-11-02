///|
test "geometry jobs execute multiple operations and return complete output" {
  let input = "{\"format\":\"moonsurface/1\",\"positions\":[[0,0,0],[1,0,0],[1,1,0],[0,1,0]],\"triangles\":[[0,1,2],[0,2,3]],\"operations\":[{\"kind\":\"flip\",\"edge\":[0,2]},{\"kind\":\"loop\",\"levels\":1}]}"
  let value = @json.parse(@exchange.execute_json(input))
  guard value is Object(fields) else { fail("missing response object") }
  assert_eq(fields.get("ok"), Some(Json::boolean(true)))
  guard fields.get("triangles") is Some(Array(faces)) else {
    fail("missing faces")
  }
  assert_eq(faces.length(), 8)
}

///|
test "protocol errors do not contain a partially processed mesh" {
  for
    text in [
      "{", "{}", "{\"format\":\"moonsurface/1\",\"positions\":[],\"triangles\":[],\"unexpected\":1}",
      "{\"format\":\"moonsurface/1\",\"positions\":[[0,0,0],[1,0,0],[0,1,0]],\"triangles\":[[0,1,2]],\"operations\":[{\"kind\":\"split\",\"edge\":[0,1]},{\"kind\":\"flip\",\"edge\":[0,2]}]}",
    ] {
    let value = @json.parse(@exchange.execute_json(text))
    guard value is Object(fields) else { fail("missing error object") }
    assert_eq(fields.get("ok"), Some(Json::boolean(false)))
    assert_true(fields.get("positions") is None)
  }
}

///|
test "split fraction follows requested endpoint order" {
  let text = "{\"format\":\"moonsurface/1\",\"positions\":[[0,0,0],[4,0,0],[0,4,0]],\"triangles\":[[0,1,2]],\"operations\":[{\"kind\":\"split\",\"edge\":[1,0],\"fraction\":0.25}]}"
  let value = @json.parse(@exchange.execute_json(text))
  guard value is Object(fields) else { fail("missing response") }
  assert_eq(fields.get("ok"), Some(Json::boolean(true)))
  guard fields.get("positions") is Some(Array(points)) else {
    fail("missing positions")
  }
  assert_eq(points[3], Json::array([3, 0, 0]))
}
