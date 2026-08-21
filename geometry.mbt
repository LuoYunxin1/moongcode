/// Deterministic, allocation-light geometry primitives used by the toolpath
/// interpreter.  The module deliberately has no parser or machine-state
/// dependencies: all coordinates are expressed in millimetres at its public
/// boundaries, except where a `Units` argument is explicitly supplied.

///|
/// A small, explicit tolerance keeps geometric decisions stable across the
/// wasm-gc, wasm, js, and native backends.
pub const GEOMETRY_TOLERANCE : Double = 1.0e-7

///|
/// Values below this radius cannot describe a useful machine arc.
pub const GEOMETRY_MIN_RADIUS : Double = 1.0e-9

///|
/// Direction of travel when looking down the positive normal of a `Plane`.
pub(all) enum ArcDirection {
  Clockwise
  CounterClockwise
} derive(Eq, @debug.Debug)

///|
/// A point expressed in the two axes of a selected plane plus its orthogonal
/// (helix) coordinate.  Plane axes are ordered XY, ZX, and YZ respectively.
pub struct PlanePoint {
  u : Double
  v : Double
  axis : Double
} derive(Eq, @debug.Debug)

///|
/// A finite, normalized axis-aligned bounding box.
pub struct Bounds3 {
  min : Point3
  max : Point3
} derive(Eq, @debug.Debug)

///|
/// Short name retained for callers that use `Bounds` in their own APIs.
pub type Bounds = Bounds3

///|
/// Resolved circular/helical motion.  `sweep` is signed: positive is
/// counter-clockwise and negative is clockwise in the plane's ordered axes.
pub struct ArcGeometry {
  start : Point3
  end : Point3
  plane : Plane
  clockwise : Bool
  center : Point3
  radius : Double
  sweep : Double
  length : Double
  bounds : Bounds3
  axis_delta : Double
} derive(Eq, @debug.Debug)

///|
/// Input to the generic arc solver. Exactly one of `center_offset` and
/// `radius` must be present.
pub struct ArcSpec {
  plane : Plane
  clockwise : Bool
  center_offset : Point3?
  radius : Double?
  tolerance : Double
} derive(Eq, @debug.Debug)

///|
/// A mixed line/arc envelope. It is intentionally immutable from the outside
/// and can be merged repeatedly while a toolpath is being built.
pub struct GeometryBounds {
  bounds : Bounds3?
  count : Int
} derive(Eq, @debug.Debug)

///|
fn geometry_error(code : String, message : String) -> Diagnostic {
  Diagnostic::error(code, 0, 0, message)
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn finite_point(point : Point3) -> Bool {
  finite(point.x()) && finite(point.y()) && finite(point.z())
}

///|
fn min_double(left : Double, right : Double) -> Double {
  if left < right {
    left
  } else {
    right
  }
}

///|
fn max_double(left : Double, right : Double) -> Double {
  if left > right {
    left
  } else {
    right
  }
}

///|
fn point_min(left : Point3, right : Point3) -> Point3 {
  Point3::new(
    min_double(left.x(), right.x()),
    min_double(left.y(), right.y()),
    min_double(left.z(), right.z()),
  )
}

///|
fn point_max(left : Point3, right : Point3) -> Point3 {
  Point3::new(
    max_double(left.x(), right.x()),
    max_double(left.y(), right.y()),
    max_double(left.z(), right.z()),
  )
}

///|
/// Stable Euclidean distance in three dimensions.
pub fn distance3(first : Point3, second : Point3) -> Double {
  let dx = second.x() - first.x()
  let dy = second.y() - first.y()
  let dz = second.z() - first.z()
  @math.hypot(@math.hypot(dx, dy), dz)
}

///|
/// Alias with the conventional spelling used by geometry callers.
pub fn distance(first : Point3, second : Point3) -> Double {
  distance3(first, second)
}

///|
/// Method form of `distance3`.
pub fn Point3::distance_to(self : Point3, other : Point3) -> Double {
  distance3(self, other)
}

///|
/// Scale a coordinate distance into millimetres and reject non-finite input.
pub fn scale_distance_mm(
  value : Double,
  units : Units,
) -> Result[Double, Diagnostic] {
  if !finite(value) {
    return Err(
      geometry_error("geometry.units.non_finite", "distance must be finite"),
    )
  }
  let scaled = value * units.scale_to_mm()
  if !finite(scaled) {
    return Err(
      geometry_error(
        "geometry.units.overflow", "unit conversion produced a non-finite distance",
      ),
    )
  }
  Ok(scaled)
}

///|
/// Convert a millimetre distance to another machine unit.
pub fn convert_distance(
  value : Double,
  from : Units,
  to : Units,
) -> Result[Double, Diagnostic] {
  match scale_distance_mm(value, from) {
    Err(error) => Err(error)
    Ok(mm) => {
      let result = mm / to.scale_to_mm()
      if !finite(result) {
        Err(
          geometry_error(
            "geometry.units.overflow", "unit conversion produced a non-finite distance",
          ),
        )
      } else {
        Ok(result)
      }
    }
  }
}

///|
/// Resolve optional G-code axis words against a start point. Missing words
/// retain their previous coordinate. Absolute words replace coordinates;
/// incremental words are added after unit conversion.
pub fn resolve_target_point(
  start : Point3,
  x : Double?,
  y : Double?,
  z : Double?,
  units : Units,
  mode : DistanceMode,
) -> Result[Point3, Diagnostic] {
  if !finite_point(start) {
    return Err(
      geometry_error(
        "geometry.target.non_finite_start", "start point must contain only finite coordinates",
      ),
    )
  }
  let scale = units.scale_to_mm()
  let converted = fn(value : Double?) -> Result[Double?, Diagnostic] {
    match value {
      None => Ok(None)
      Some(raw) =>
        if !finite(raw) {
          Err(
            geometry_error(
              "geometry.target.non_finite", "target axis must be finite",
            ),
          )
        } else {
          let result = raw * scale
          if !finite(result) {
            Err(
              geometry_error(
                "geometry.target.overflow", "target axis conversion produced a non-finite value",
              ),
            )
          } else {
            Ok(Some(result))
          }
        }
    }
  }
  let xx = match converted(x) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let yy = match converted(y) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let zz = match converted(z) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let apply = fn(previous : Double, value : Double?) -> Double {
    match mode {
      Absolute => value.unwrap_or(previous)
      Incremental => previous + value.unwrap_or(0.0)
    }
  }
  let target = Point3::new(
    apply(start.x(), xx),
    apply(start.y(), yy),
    apply(start.z(), zz),
  )
  if !finite_point(target) {
    Err(
      geometry_error(
        "geometry.target.overflow", "resolved target point is non-finite",
      ),
    )
  } else {
    Ok(target)
  }
}

///|
/// Positional-word spelling retained for integrations that call the helper
/// directly from a G-code evaluator.
pub fn target_point(
  start : Point3,
  x : Double?,
  y : Double?,
  z : Double?,
  units : Units,
  mode : DistanceMode,
) -> Result[Point3, Diagnostic] {
  resolve_target_point(start, x, y, z, units, mode)
}

///|
/// Project a 3D point into the ordered coordinates of a machine plane.
pub fn plane_project(plane : Plane, point : Point3) -> PlanePoint {
  match plane {
    XY => { u: point.x(), v: point.y(), axis: point.z() }
    ZX => { u: point.z(), v: point.x(), axis: point.y() }
    YZ => { u: point.y(), v: point.z(), axis: point.x() }
  }
}

///|
/// Method spelling of `plane_project`.
pub fn Plane::project(self : Plane, point : Point3) -> PlanePoint {
  plane_project(self, point)
}

///|
/// Lift plane coordinates back into a 3D point.
pub fn plane_lift(plane : Plane, value : PlanePoint) -> Point3 {
  match plane {
    XY => Point3::new(value.u, value.v, value.axis)
    ZX => Point3::new(value.v, value.axis, value.u)
    YZ => Point3::new(value.axis, value.u, value.v)
  }
}

///|
/// Convenience constructor for projected coordinates.
pub fn PlanePoint::new(u : Double, v : Double, axis : Double) -> PlanePoint {
  { u, v, axis }
}

///|
pub fn PlanePoint::u(self : PlanePoint) -> Double {
  self.u
}

///|
pub fn PlanePoint::v(self : PlanePoint) -> Double {
  self.v
}

///|
pub fn PlanePoint::axis(self : PlanePoint) -> Double {
  self.axis
}

///|
pub fn PlanePoint::first(self : PlanePoint) -> Double {
  self.u
}

///|
pub fn PlanePoint::second(self : PlanePoint) -> Double {
  self.v
}

///|
/// Method spelling of `plane_lift`.
pub fn Plane::lift(self : Plane, value : PlanePoint) -> Point3 {
  plane_lift(self, value)
}

///|
pub fn Bounds3::from_points(first : Point3, second : Point3) -> Bounds3 {
  { min: point_min(first, second), max: point_max(first, second) }
}

///|
pub fn Bounds3::from_point(point : Point3) -> Bounds3 {
  { min: point, max: point }
}

///|
pub fn Bounds3::min(self : Bounds3) -> Point3 {
  self.min
}

///|
pub fn Bounds3::max(self : Bounds3) -> Point3 {
  self.max
}

///|
pub fn Bounds3::include_point(self : Bounds3, point : Point3) -> Bounds3 {
  { min: point_min(self.min, point), max: point_max(self.max, point) }
}

///|
pub fn Bounds3::merge(self : Bounds3, other : Bounds3) -> Bounds3 {
  { min: point_min(self.min, other.min), max: point_max(self.max, other.max) }
}

///|
pub fn Bounds3::contains(
  self : Bounds3,
  point : Point3,
  tolerance? : Double = GEOMETRY_TOLERANCE,
) -> Bool {
  let tol = if finite(tolerance) && tolerance >= 0.0 {
    tolerance
  } else {
    GEOMETRY_TOLERANCE
  }
  point.x() >= self.min.x() - tol &&
  point.x() <= self.max.x() + tol &&
  point.y() >= self.min.y() - tol &&
  point.y() <= self.max.y() + tol &&
  point.z() >= self.min.z() - tol &&
  point.z() <= self.max.z() + tol
}

///|
pub fn merge_bounds(first : Bounds3, second : Bounds3) -> Bounds3 {
  first.merge(second)
}

///|
fn normalized_tolerance(value : Double) -> Double {
  if finite(value) && value > 0.0 {
    value
  } else {
    GEOMETRY_TOLERANCE
  }
}

///|
fn scaled_tolerance(radius : Double, tolerance : Double) -> Double {
  let base = normalized_tolerance(tolerance)
  let scaled = radius.abs() * 1.0e-8
  if scaled > base {
    scaled
  } else {
    base
  }
}

///|
fn normalize_angle(value : Double) -> Double {
  let turn = 2.0 * @math.PI
  let quotient = @math.floor(value / turn)
  let mut result = value - quotient * turn
  if result < 0.0 {
    result = result + turn
  }
  if result >= turn {
    result = result - turn
  }
  result
}

///|
fn arc_sweep(
  start_angle : Double,
  end_angle : Double,
  clockwise : Bool,
  full_circle : Bool,
) -> Double {
  if full_circle {
    if clockwise {
      -2.0 * @math.PI
    } else {
      2.0 * @math.PI
    }
  } else if clockwise {
    let delta = normalize_angle(start_angle - end_angle)
    -delta
  } else {
    normalize_angle(end_angle - start_angle)
  }
}

///|
fn angle_distance(
  start_angle : Double,
  target_angle : Double,
  clockwise : Bool,
) -> Double {
  if clockwise {
    normalize_angle(start_angle - target_angle)
  } else {
    normalize_angle(target_angle - start_angle)
  }
}

///|
fn point_at_arc_angle(
  plane : Plane,
  center : PlanePoint,
  radius : Double,
  angle : Double,
  axis : Double,
) -> Point3 {
  plane_lift(
    plane,
    PlanePoint::new(
      center.u + radius * @math.cos(angle),
      center.v + radius * @math.sin(angle),
      axis,
    ),
  )
}

///|
fn arc_bounds_raw(
  start : Point3,
  end : Point3,
  center : Point3,
  radius : Double,
  sweep : Double,
  plane : Plane,
) -> Bounds3 {
  let start_plane = plane_project(plane, start)
  let center_plane = plane_project(plane, center)
  let mut result = Bounds3::from_points(start, end)
  let start_angle = @math.atan2(
    start_plane.v - center_plane.v,
    start_plane.u - center_plane.u,
  )
  let clockwise = sweep < 0.0
  let magnitude = sweep.abs()
  let axis_delta = start_plane.axis - plane_project(plane, end).axis
  let cardinal = [0.0, @math.PI / 2.0, @math.PI, 3.0 * @math.PI / 2.0]
  for target in cardinal {
    let distance_along = angle_distance(start_angle, target, clockwise)
    if magnitude >= 2.0 * @math.PI - GEOMETRY_TOLERANCE ||
      distance_along <= magnitude + GEOMETRY_TOLERANCE {
      let fraction = if magnitude <= GEOMETRY_MIN_RADIUS {
        0.0
      } else {
        let raw = distance_along / magnitude
        if raw < 0.0 {
          0.0
        } else if raw > 1.0 {
          1.0
        } else {
          raw
        }
      }
      let axis = start_plane.axis - axis_delta * fraction
      result = result.include_point(
        point_at_arc_angle(plane, center_plane, radius, target, axis),
      )
    }
  }
  result
}

///|
fn make_arc(
  start : Point3,
  end : Point3,
  plane : Plane,
  clockwise : Bool,
  center : Point3,
  radius : Double,
  sweep : Double,
  tolerance : Double,
) -> Result[ArcGeometry, Diagnostic] {
  if !finite_point(start) ||
    !finite_point(end) ||
    !finite_point(center) ||
    !finite(radius) ||
    !finite(sweep) {
    return Err(
      geometry_error(
        "geometry.arc.non_finite", "arc coordinates and derived values must be finite",
      ),
    )
  }
  if radius <= GEOMETRY_MIN_RADIUS {
    return Err(
      geometry_error(
        "geometry.arc.radius.non_positive", "arc radius must be greater than zero",
      ),
    )
  }
  if sweep.abs() <= GEOMETRY_MIN_RADIUS {
    return Err(
      geometry_error("geometry.arc.degenerate", "arc sweep must be non-zero"),
    )
  }
  let start_plane = plane_project(plane, start)
  let end_plane = plane_project(plane, end)
  let center_plane = plane_project(plane, center)
  let start_radius = @math.hypot(
    start_plane.u - center_plane.u,
    start_plane.v - center_plane.v,
  )
  let end_radius = @math.hypot(
    end_plane.u - center_plane.u,
    end_plane.v - center_plane.v,
  )
  let tolerance_value = scaled_tolerance(radius, tolerance)
  if (start_radius - radius).abs() > tolerance_value ||
    (end_radius - radius).abs() > tolerance_value {
    return Err(
      geometry_error(
        "geometry.arc.endpoint_mismatch", "arc endpoint is outside the requested circle tolerance",
      ),
    )
  }
  let length = @math.hypot(
    radius * sweep.abs(),
    end_plane.axis - start_plane.axis,
  )
  if !finite(length) {
    return Err(
      geometry_error("geometry.arc.numeric", "arc length is non-finite"),
    )
  }
  let bounds = arc_bounds_raw(start, end, center, radius, sweep, plane)
  Ok({
    start,
    end,
    plane,
    clockwise,
    center,
    radius,
    sweep,
    length,
    bounds,
    axis_delta: end_plane.axis - start_plane.axis,
  })
}

///|
fn solve_ijk_internal(
  start : Point3,
  end : Point3,
  plane : Plane,
  clockwise : Bool,
  offset : Point3,
  tolerance : Double,
) -> Result[ArcGeometry, Diagnostic] {
  if !finite_point(start) || !finite_point(end) || !finite_point(offset) {
    return Err(
      geometry_error(
        "geometry.arc.non_finite", "arc input coordinates must be finite",
      ),
    )
  }
  let start_plane = plane_project(plane, start)
  let offset_plane = plane_project(plane, offset)
  let tol = normalized_tolerance(tolerance)
  if offset_plane.axis.abs() > tol {
    return Err(
      geometry_error(
        "geometry.arc.ijk.normal_offset", "IJK center offset must lie in the selected plane",
      ),
    )
  }
  let center_plane = PlanePoint::new(
    start_plane.u + offset_plane.u,
    start_plane.v + offset_plane.v,
    start_plane.axis,
  )
  let center = plane_lift(plane, center_plane)
  let radius = @math.hypot(
    start_plane.u - center_plane.u,
    start_plane.v - center_plane.v,
  )
  if !finite(radius) || radius <= GEOMETRY_MIN_RADIUS {
    return Err(
      geometry_error(
        "geometry.arc.radius.non_positive", "IJK center offset produces a zero or invalid radius",
      ),
    )
  }
  let end_plane = plane_project(plane, end)
  let chord = @math.hypot(
    end_plane.u - start_plane.u,
    end_plane.v - start_plane.v,
  )
  let full_circle = chord <= scaled_tolerance(radius, tol)
  let start_angle = @math.atan2(
    start_plane.v - center_plane.v,
    start_plane.u - center_plane.u,
  )
  let end_angle = @math.atan2(
    end_plane.v - center_plane.v,
    end_plane.u - center_plane.u,
  )
  let sweep = arc_sweep(start_angle, end_angle, clockwise, full_circle)
  make_arc(start, end, plane, clockwise, center, radius, sweep, tol)
}

///|
/// Solve an arc whose centre is supplied as an IJK offset from the start.
pub fn solve_arc_ijk(
  start : Point3,
  end : Point3,
  plane : Plane,
  clockwise : Bool,
  offset : Point3,
  tolerance? : Double = GEOMETRY_TOLERANCE,
) -> Result[ArcGeometry, Diagnostic] {
  solve_ijk_internal(start, end, plane, clockwise, offset, tolerance)
}

///|
/// Explicit spelling for callers that prefer the construction terminology.
pub fn solve_arc_with_ijk(
  start : Point3,
  end : Point3,
  plane : Plane,
  clockwise : Bool,
  offset : Point3,
  tolerance? : Double = GEOMETRY_TOLERANCE,
) -> Result[ArcGeometry, Diagnostic] {
  solve_arc_ijk(start, end, plane, clockwise, offset, tolerance~)
}

///|
fn candidate_sweep(
  start : PlanePoint,
  end : PlanePoint,
  center : PlanePoint,
  clockwise : Bool,
) -> Double {
  let start_angle = @math.atan2(start.v - center.v, start.u - center.u)
  let end_angle = @math.atan2(end.v - center.v, end.u - center.u)
  arc_sweep(start_angle, end_angle, clockwise, false)
}

///|
fn choose_radius_center(
  start : PlanePoint,
  end : PlanePoint,
  radius : Double,
  clockwise : Bool,
  positive_radius : Bool,
  tolerance : Double,
) -> (PlanePoint, Double)? {
  let du = end.u - start.u
  let dv = end.v - start.v
  let chord = @math.hypot(du, dv)
  if chord <= normalized_tolerance(tolerance) {
    return None
  }
  let half = chord / 2.0
  let h2 = radius * radius - half * half
  if h2 <
    -scaled_tolerance(radius, tolerance) * scaled_tolerance(radius, tolerance) {
    return None
  }
  let h = if h2 <= 0.0 { 0.0 } else { h2.sqrt() }
  let mid_u = (start.u + end.u) / 2.0
  let mid_v = (start.v + end.v) / 2.0
  let perp_u = -dv / chord
  let perp_v = du / chord
  let first = PlanePoint::new(
    mid_u + perp_u * h,
    mid_v + perp_v * h,
    start.axis,
  )
  let second = PlanePoint::new(
    mid_u - perp_u * h,
    mid_v - perp_v * h,
    start.axis,
  )
  let first_sweep = candidate_sweep(start, end, first, clockwise)
  let second_sweep = candidate_sweep(start, end, second, clockwise)
  let first_magnitude = first_sweep.abs()
  let second_magnitude = second_sweep.abs()
  let pi = @math.PI
  let eps = normalized_tolerance(tolerance)
  let first_matches = if positive_radius {
    first_magnitude <= pi + eps
  } else {
    first_magnitude >= pi - eps
  }
  let second_matches = if positive_radius {
    second_magnitude <= pi + eps
  } else {
    second_magnitude >= pi - eps
  }
  if first_matches && !second_matches {
    Some((first, first_sweep))
  } else if second_matches && !first_matches {
    Some((second, second_sweep))
  } else if first_matches && second_matches {
    // On a diameter both candidates are semicircles. Choosing the first is
    // deterministic and keeps the sign controlled solely by direction.
    if first_magnitude <= second_magnitude {
      Some((first, first_sweep))
    } else {
      Some((second, second_sweep))
    }
  } else if first_magnitude < second_magnitude {
    Some((first, first_sweep))
  } else {
    Some((second, second_sweep))
  }
}

///|
fn solve_radius_internal(
  start : Point3,
  end : Point3,
  plane : Plane,
  clockwise : Bool,
  requested_radius : Double,
  tolerance : Double,
) -> Result[ArcGeometry, Diagnostic] {
  if !finite_point(start) || !finite_point(end) || !finite(requested_radius) {
    return Err(
      geometry_error(
        "geometry.arc.non_finite", "arc input coordinates must be finite",
      ),
    )
  }
  if requested_radius == 0.0 {
    return Err(
      geometry_error(
        "geometry.arc.radius.non_positive", "R radius must be non-zero",
      ),
    )
  }
  let radius = requested_radius.abs()
  if radius <= GEOMETRY_MIN_RADIUS {
    return Err(
      geometry_error(
        "geometry.arc.radius.non_positive", "R radius must be greater than zero",
      ),
    )
  }
  let start_plane = plane_project(plane, start)
  let end_plane = plane_project(plane, end)
  let chord = @math.hypot(
    end_plane.u - start_plane.u,
    end_plane.v - start_plane.v,
  )
  let tol = normalized_tolerance(tolerance)
  if chord <= tol {
    return Err(
      geometry_error(
        "geometry.arc.full_circle_requires_center", "an R arc needs distinct planar endpoints; use IJK for a full circle",
      ),
    )
  }
  if radius < chord / 2.0 - scaled_tolerance(radius, tol) {
    return Err(
      geometry_error(
        "geometry.arc.radius_too_small", "absolute R radius is smaller than half the endpoint chord",
      ),
    )
  }
  let chosen = choose_radius_center(
    start_plane,
    end_plane,
    radius,
    clockwise,
    requested_radius > 0.0,
    tol,
  )
  let (center_plane, sweep) = match chosen {
    None =>
      return Err(
        geometry_error(
          "geometry.arc.radius_too_small", "R radius cannot construct a stable circle through the endpoints",
        ),
      )
    Some(value) => value
  }
  let center = plane_lift(plane, center_plane)
  make_arc(start, end, plane, clockwise, center, radius, sweep, tol)
}

///|
/// Solve an arc from the signed G-code R parameter. Positive R selects the
/// short arc; negative R selects the long arc. Direction controls the sign of
/// the resulting sweep.
pub fn solve_arc_radius(
  start : Point3,
  end : Point3,
  plane : Plane,
  clockwise : Bool,
  radius : Double,
  tolerance? : Double = GEOMETRY_TOLERANCE,
) -> Result[ArcGeometry, Diagnostic] {
  solve_radius_internal(start, end, plane, clockwise, radius, tolerance)
}

///|
pub fn solve_arc_with_radius(
  start : Point3,
  end : Point3,
  plane : Plane,
  clockwise : Bool,
  radius : Double,
  tolerance? : Double = GEOMETRY_TOLERANCE,
) -> Result[ArcGeometry, Diagnostic] {
  solve_arc_radius(start, end, plane, clockwise, radius, tolerance~)
}

///|
/// Build an IJK arc specification.
pub fn ArcSpec::ijk(
  plane : Plane,
  clockwise : Bool,
  offset : Point3,
  tolerance? : Double = GEOMETRY_TOLERANCE,
) -> ArcSpec {
  {
    plane,
    clockwise,
    center_offset: Some(offset),
    radius: None,
    tolerance: normalized_tolerance(tolerance),
  }
}

///|
/// Build an R arc specification.
pub fn ArcSpec::radius(
  plane : Plane,
  clockwise : Bool,
  radius : Double,
  tolerance? : Double = GEOMETRY_TOLERANCE,
) -> ArcSpec {
  {
    plane,
    clockwise,
    center_offset: None,
    radius: Some(radius),
    tolerance: normalized_tolerance(tolerance),
  }
}

///|
pub fn ArcSpec::plane(self : ArcSpec) -> Plane {
  self.plane
}

///|
pub fn ArcSpec::clockwise(self : ArcSpec) -> Bool {
  self.clockwise
}

///|
pub fn ArcSpec::center_offset(self : ArcSpec) -> Point3? {
  self.center_offset
}

///|
pub fn ArcSpec::radius_value(self : ArcSpec) -> Double? {
  self.radius
}

///|
pub fn ArcSpec::tolerance(self : ArcSpec) -> Double {
  self.tolerance
}

///|
/// Solve either representation selected in an `ArcSpec`.
pub fn solve_arc(
  start : Point3,
  end : Point3,
  spec : ArcSpec,
) -> Result[ArcGeometry, Diagnostic] {
  match (spec.center_offset, spec.radius) {
    (Some(offset), None) =>
      solve_arc_ijk(
        start,
        end,
        spec.plane,
        spec.clockwise,
        offset,
        tolerance=spec.tolerance,
      )
    (None, Some(radius)) =>
      solve_arc_radius(
        start,
        end,
        spec.plane,
        spec.clockwise,
        radius,
        tolerance=spec.tolerance,
      )
    _ =>
      Err(
        geometry_error(
          "geometry.arc.spec.invalid", "arc specification must contain exactly one of IJK or R",
        ),
      )
  }
}

///|
pub fn ArcGeometry::from_ijk(
  start : Point3,
  end : Point3,
  plane : Plane,
  clockwise : Bool,
  offset : Point3,
  tolerance? : Double = GEOMETRY_TOLERANCE,
) -> Result[ArcGeometry, Diagnostic] {
  solve_arc_ijk(start, end, plane, clockwise, offset, tolerance~)
}

///|
pub fn ArcGeometry::from_radius(
  start : Point3,
  end : Point3,
  plane : Plane,
  clockwise : Bool,
  radius : Double,
  tolerance? : Double = GEOMETRY_TOLERANCE,
) -> Result[ArcGeometry, Diagnostic] {
  solve_arc_radius(start, end, plane, clockwise, radius, tolerance~)
}

///|
pub fn ArcGeometry::start(self : ArcGeometry) -> Point3 {
  self.start
}

///|
pub fn ArcGeometry::end(self : ArcGeometry) -> Point3 {
  self.end
}

///|
pub fn ArcGeometry::plane(self : ArcGeometry) -> Plane {
  self.plane
}

///|
pub fn ArcGeometry::clockwise(self : ArcGeometry) -> Bool {
  self.clockwise
}

///|
pub fn ArcGeometry::center(self : ArcGeometry) -> Point3 {
  self.center
}

///|
pub fn ArcGeometry::radius(self : ArcGeometry) -> Double {
  self.radius
}

///|
pub fn ArcGeometry::radius_mm(self : ArcGeometry) -> Double {
  self.radius
}

///|
pub fn ArcGeometry::sweep(self : ArcGeometry) -> Double {
  self.sweep
}

///|
pub fn ArcGeometry::sweep_radians(self : ArcGeometry) -> Double {
  self.sweep
}

///|
pub fn ArcGeometry::length(self : ArcGeometry) -> Double {
  self.length
}

///|
pub fn ArcGeometry::length_mm(self : ArcGeometry) -> Double {
  self.length
}

///|
pub fn ArcGeometry::bounds(self : ArcGeometry) -> Bounds3 {
  self.bounds
}

///|
pub fn ArcGeometry::axis_delta(self : ArcGeometry) -> Double {
  self.axis_delta
}

///|
/// Bounds of a straight or circular `Segment`. For an arc, callers should
/// pass its plane; the default XY is useful for the common G17 case.
pub fn bounds_of_segment(segment : Segment, plane? : Plane = XY) -> Bounds3 {
  match segment.center() {
    None => Bounds3::from_points(segment.start(), segment.end())
    Some(center) => {
      let radius = segment.radius_mm()
      if !finite(radius) ||
        radius <= GEOMETRY_MIN_RADIUS ||
        segment.sweep_radians().abs() <= GEOMETRY_MIN_RADIUS {
        Bounds3::from_points(segment.start(), segment.end())
      } else {
        arc_bounds_raw(
          segment.start(),
          segment.end(),
          center,
          radius,
          segment.sweep_radians(),
          plane,
        )
      }
    }
  }
}

///|
pub fn segment_bounds(segment : Segment, plane? : Plane = XY) -> Bounds3 {
  bounds_of_segment(segment, plane~)
}

///|
pub fn bounds_of_arc(arc : ArcGeometry) -> Bounds3 {
  arc.bounds
}

///|
pub fn GeometryBounds::empty() -> GeometryBounds {
  { bounds: None, count: 0 }
}

///|
pub fn GeometryBounds::count(self : GeometryBounds) -> Int {
  self.count
}

///|
pub fn GeometryBounds::value(self : GeometryBounds) -> Bounds3? {
  self.bounds
}

///|
pub fn GeometryBounds::bounds(self : GeometryBounds) -> Bounds3? {
  self.bounds
}

///|
pub fn GeometryBounds::add_bounds(
  self : GeometryBounds,
  value : Bounds3,
) -> GeometryBounds {
  let merged = match self.bounds {
    None => value
    Some(current) => current.merge(value)
  }
  { bounds: Some(merged), count: self.count + 1 }
}

///|
pub fn GeometryBounds::add_segment(
  self : GeometryBounds,
  segment : Segment,
  plane? : Plane = XY,
) -> GeometryBounds {
  self.add_bounds(bounds_of_segment(segment, plane~))
}

///|
pub fn GeometryBounds::add_arc(
  self : GeometryBounds,
  arc : ArcGeometry,
) -> GeometryBounds {
  self.add_bounds(arc.bounds)
}

///|
pub fn GeometryBounds::merge(
  self : GeometryBounds,
  other : GeometryBounds,
) -> GeometryBounds {
  match (self.bounds, other.bounds) {
    (None, None) => GeometryBounds::empty()
    (Some(value), None) => { bounds: Some(value), count: self.count }
    (None, Some(value)) => { bounds: Some(value), count: other.count }
    (Some(left), Some(right)) =>
      { bounds: Some(left.merge(right)), count: self.count + other.count }
  }
}

///|
/// Merge a line and an arc envelope in one operation.
pub fn merge_segment_and_arc(
  segment : Segment,
  arc : ArcGeometry,
  plane? : Plane = XY,
) -> Bounds3 {
  bounds_of_segment(segment, plane~).merge(arc.bounds)
}
