///|
/// Interpolation contracts for bounded, numeric vertex channels.
pub(all) enum Interpolation {
  Linear
  UnitVector
  Discrete
} derive(Eq, Debug)

///|
pub extend Interpolation with Eq::{equal, not_equal}

///|
pub extend Interpolation with @debug.Debug::{to_repr}

///|
/// Owned vertex data. Dimension is 1..4; UnitVector requires dimension three.
pub struct VertexAttribute {
  name : String
  width : Int
  interpolation : Interpolation
  priv data : Array[Array[Double]]
}

///|
pub fn VertexAttribute::new(
  name : String,
  width : Int,
  interpolation : Interpolation,
  data : Array[Array[Double]],
) -> VertexAttribute raise SurfaceError {
  if name.is_empty() ||
    name.length() > 64 ||
    width < 1 ||
    width > 4 ||
    (interpolation == UnitVector && width != 3) {
    raise InvalidArgument("invalid attribute declaration")
  }
  let rows : Array[Array[Double]] = []
  for row in data {
    if row.length() != width || !row.iter().all(finite) {
      raise InvalidArgument("attribute shape or non-finite value")
    }
    rows.push(attribute_normalize(row.copy(), interpolation))
  }
  { name, width, interpolation, data: rows, }
}

///|
pub fn VertexAttribute::values(self : VertexAttribute) -> Array[Array[Double]] {
  self.data.map(fn(row) { row.copy() })
}

///|
fn attribute_copy(a : VertexAttribute) -> VertexAttribute {
  { ..a, data: a.values(), }
}

///|
fn attribute_normalize(
  row : Array[Double],
  mode : Interpolation,
) -> Array[Double] raise SurfaceError {
  if mode != UnitVector {
    return row
  }
  let scale = Double::max(abs(row[0]), Double::max(abs(row[1]), abs(row[2])))
  if scale == 0.0 {
    raise NumericalFailure("zero attribute normal")
  }
  let x = row[0] / scale
  let y = row[1] / scale
  let z = row[2] / scale
  let length = (x * x + y * y + z * z).sqrt()
  [x / length, y / length, z / length]
}

///|
fn attribute_blend(
  attribute : VertexAttribute,
  a : Int,
  b : Int,
  fraction : Double,
) -> Array[Double] raise SurfaceError {
  let left = attribute.data[a]
  let right = attribute.data[b]
  if attribute.interpolation == Discrete && left != right {
    raise AttributeConflict(attribute.name)
  }
  let row : Array[Double] = []
  for axis in 0..<attribute.width {
    row.push(lerp_scalar(left[axis], right[axis], fraction))
  }
  attribute_normalize(row, attribute.interpolation)
}

///|
pub(all) struct Vec2 {
  x : Double
  y : Double
} derive(Eq, Debug)

///|
pub extend Vec2 with Eq::{equal, not_equal}

///|
pub extend Vec2 with @debug.Debug::{to_repr}

///|
/// Per-face-corner UVs, in exactly the same order as a triangle's corners.
pub(all) struct CornerUV {
  a : Vec2
  b : Vec2
  c : Vec2
} derive(Eq, Debug)

///|
pub extend CornerUV with Eq::{equal, not_equal}

///|
pub extend CornerUV with @debug.Debug::{to_repr}

///|
fn uv_lerp(a : Vec2, b : Vec2, t : Double) -> Vec2 {
  { x: lerp_scalar(a.x, b.x, t), y: lerp_scalar(a.y, b.y, t), }
}

///|
fn uv_equal(a : Vec2, b : Vec2) -> Bool {
  abs(a.x - b.x) <= 1.0e-10 && abs(a.y - b.y) <= 1.0e-10
}

///|
fn uv_sign(uv : CornerUV) -> Double {
  let scale = Double::max(
    1.0,
    Double::max(
      Double::max(abs(uv.a.x), abs(uv.a.y)),
      Double::max(
        Double::max(abs(uv.b.x), abs(uv.b.y)),
        Double::max(abs(uv.c.x), abs(uv.c.y)),
      ),
    ),
  )
  let ux = uv.b.x / scale - uv.a.x / scale
  let uy = uv.b.y / scale - uv.a.y / scale
  let vx = uv.c.x / scale - uv.a.x / scale
  let vy = uv.c.y / scale - uv.a.y / scale
  ux * vy - uy * vx
}

///|
fn uv_survives(old : CornerUV?, proposed : CornerUV?) -> Bool {
  match (old, proposed) {
    (Some(a), Some(b)) => {
      let before = uv_sign(a)
      let after = uv_sign(b)
      before == 0.0 ||
      (before > 0.0 && after > 0.0) ||
      (before < 0.0 && after < 0.0)
    }
    _ => true
  }
}
