///|
/// A position in object space. Inputs must contain only finite coordinates.
pub(all) struct Vec3 {
  x : Double
  y : Double
  z : Double
} derive(Eq, Debug)

///|
/// Recoverable validation errors. No operation silently repairs invalid input.
pub suberror SurfaceError {
  InvalidArgument(String)
  LimitExceeded(String)
  InvalidIndex(Int, Int)
  NonFiniteCoordinate(Int)
  DegenerateFace(Int)
  DuplicateFace(Int)
  IsolatedVertex(Int)
  InconsistentOrientation(Int, Int)
  NonManifoldEdge(Int, Int)
  NonManifoldVertex(Int)
  InvalidElement(Int)
  TopologyInvariant(String)
  NumericalFailure(String)
} derive(Eq, Debug)

///|
/// Edge identifiers belong to one mesh. A flip retains the id of its diagonal.
pub(all) struct EdgeId(Int) derive(Eq, Debug)

///|
pub extend EdgeId with Eq::{equal, not_equal}

///|
pub extend EdgeId with @debug.Debug::{to_repr}

///|
/// Count budgets, not an operating-system memory limit.
pub struct Limits {
  max_vertices : Int
  max_input_faces : Int
  max_output_faces : Int
  max_levels : Int
} derive(Eq, Debug)

///|
/// Hard count ceilings also keep halfedge indexes in the signed Int range.
pub fn Limits::new(
  max_vertices? : Int = 1_000_000,
  max_input_faces? : Int = 250_000,
  max_output_faces? : Int = 1_000_000,
  max_levels? : Int = 6,
) -> Limits raise SurfaceError {
  if max_vertices < 0 ||
    max_vertices > 1_000_000 ||
    max_input_faces < 0 ||
    max_input_faces > 1_000_000 ||
    max_output_faces < 0 ||
    max_output_faces > 1_000_000 ||
    max_levels < 0 ||
    max_levels > 6 {
    raise InvalidArgument("limits exceed supported count ceilings")
  }
  { max_vertices, max_input_faces, max_output_faces, max_levels, }
}

///|
/// Default count limits, with no allocation or fallible initialization.
pub fn Limits::default() -> Limits {
  {
    max_vertices: 1_000_000,
    max_input_faces: 250_000,
    max_output_faces: 1_000_000,
    max_levels: 6,
  }
}

///|
/// Configured vertex ceiling.
pub fn Limits::vertex_limit(self : Limits) -> Int {
  self.max_vertices
}

///|
/// Configured input face ceiling.
pub fn Limits::input_face_limit(self : Limits) -> Int {
  self.max_input_faces
}

///|
/// Configured output face ceiling.
pub fn Limits::output_face_limit(self : Limits) -> Int {
  self.max_output_faces
}

///|
/// Configured uniform subdivision level ceiling.
pub fn Limits::level_limit(self : Limits) -> Int {
  self.max_levels
}

///|
pub extend Vec3 with Eq::{equal, not_equal}

///|
pub extend Vec3 with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend SurfaceError with Eq::{equal, not_equal}

///|
pub extend SurfaceError with @debug.Debug::{to_repr}
