///|
fn assert_near(
  actual : Double,
  expected : Double,
  tolerance : Double,
) -> Unit raise {
  assert_true((actual - expected).abs() <= tolerance)
}

///|
fn arc_or_fail(result : Result[ArcGeometry, Diagnostic]) -> ArcGeometry raise {
  match result {
    Ok(arc) => arc
    Err(error) => {
      assert_true(false, msg=error.to_text())
      // The assertion above aborts a failing test; this value only satisfies
      // the expression type for the compiler.
      ArcGeometry::from_ijk(
        Point3::origin(),
        Point3::new(1.0, 0.0, 0.0),
        XY,
        false,
        Point3::new(0.0, -1.0, 0.0),
      ).unwrap()
    }
  }
}

///|
test "distance is three dimensional and stable" {
  assert_near(
    distance3(Point3::origin(), Point3::new(2.0, 3.0, 6.0)),
    7.0,
    1.0e-12,
  )
  assert_near(
    Point3::new(1.0e150, 0.0, 0.0).distance_to(Point3::origin()),
    1.0e150,
    1.0e138,
  )
}

///|
test "unit scaling and absolute target" {
  let result = resolve_target_point(
    Point3::new(10.0, 20.0, 30.0),
    Some(1.0),
    None,
    Some(-2.0),
    Inches,
    Absolute,
  ).unwrap()
  assert_near(result.x(), 25.4, 1.0e-12)
  assert_near(result.y(), 20.0, 1.0e-12)
  assert_near(result.z(), -50.8, 1.0e-12)
}

///|
test "incremental target retains missing axes" {
  let result = target_point(
    Point3::new(10.0, 20.0, 30.0),
    Some(2.0),
    None,
    Some(-1.0),
    Millimeters,
    Incremental,
  ).unwrap()
  assert_eq(result, Point3::new(12.0, 20.0, 29.0))
}

///|
test "plane projection round trips all planes" {
  let point = Point3::new(2.0, 3.0, 5.0)
  assert_eq(plane_lift(XY, plane_project(XY, point)), point)
  assert_eq(plane_lift(ZX, plane_project(ZX, point)), point)
  assert_eq(plane_lift(YZ, plane_project(YZ, point)), point)
  let zx = Plane::project(ZX, point)
  assert_eq((zx.u(), zx.v(), zx.axis()), (5.0, 2.0, 3.0))
}

///|
test "ijk counter-clockwise first quadrant" {
  let arc = arc_or_fail(
    solve_arc_ijk(
      Point3::new(1.0, 0.0, 0.0),
      Point3::new(0.0, 1.0, 0.0),
      XY,
      false,
      Point3::new(-1.0, 0.0, 0.0),
    ),
  )
  assert_eq(arc.center(), Point3::origin())
  assert_near(arc.radius(), 1.0, 1.0e-12)
  assert_near(arc.sweep(), @math.PI / 2.0, 1.0e-12)
  assert_near(arc.length(), @math.PI / 2.0, 1.0e-12)
  assert_true(arc.bounds().contains(Point3::new(1.0, 0.0, 0.0)))
}

///|
test "ijk clockwise uses negative sweep" {
  let arc = arc_or_fail(
    solve_arc_ijk(
      Point3::new(1.0, 0.0, 0.0),
      Point3::new(0.0, -1.0, 0.0),
      XY,
      true,
      Point3::new(-1.0, 0.0, 0.0),
    ),
  )
  assert_near(arc.sweep(), -@math.PI / 2.0, 1.0e-12)
  assert_near(arc.bounds().min().y(), -1.0, 1.0e-12)
}

///|
test "ijk reaches the other quadrants" {
  let arc = arc_or_fail(
    solve_arc_ijk(
      Point3::new(-1.0, 0.0, 0.0),
      Point3::new(0.0, -1.0, 0.0),
      XY,
      false,
      Point3::new(1.0, 0.0, 0.0),
    ),
  )
  assert_near(arc.sweep(), @math.PI / 2.0, 1.0e-12)
  assert_near(arc.bounds().min().x(), -1.0, 1.0e-12)
  assert_near(arc.bounds().max().y(), 0.0, 1.0e-12)
}

///|
test "ijk full circle has a complete envelope" {
  let arc = arc_or_fail(
    solve_arc_ijk(
      Point3::new(1.0, 0.0, 0.0),
      Point3::new(1.0, 0.0, 0.0),
      XY,
      false,
      Point3::new(-1.0, 0.0, 0.0),
    ),
  )
  assert_near(arc.sweep(), 2.0 * @math.PI, 1.0e-12)
  assert_near(arc.bounds().min().x(), -1.0, 1.0e-12)
  assert_near(arc.bounds().max().x(), 1.0, 1.0e-12)
  assert_near(arc.bounds().min().y(), -1.0, 1.0e-12)
  assert_near(arc.bounds().max().y(), 1.0, 1.0e-12)
}

///|
test "ijk full circle can be helical" {
  let arc = arc_or_fail(
    solve_arc_ijk(
      Point3::new(1.0, 0.0, 2.0),
      Point3::new(1.0, 0.0, 7.0),
      XY,
      true,
      Point3::new(-1.0, 0.0, 0.0),
    ),
  )
  assert_near(arc.sweep(), -2.0 * @math.PI, 1.0e-12)
  assert_near(arc.axis_delta(), 5.0, 1.0e-12)
  assert_near(arc.length(), @math.hypot(2.0 * @math.PI, 5.0), 1.0e-12)
  assert_near(arc.bounds().max().z(), 7.0, 1.0e-12)
}

///|
test "R positive selects the short semicircle" {
  let arc = arc_or_fail(
    solve_arc_radius(
      Point3::new(-1.0, 0.0, 0.0),
      Point3::new(1.0, 0.0, 0.0),
      XY,
      false,
      1.0,
    ),
  )
  assert_near(arc.sweep().abs(), @math.PI, 1.0e-12)
  assert_near(arc.radius(), 1.0, 1.0e-12)
}

///|
test "R negative selects a long arc" {
  let arc = arc_or_fail(
    solve_arc_radius(
      Point3::new(1.0, 0.0, 0.0),
      Point3::new(0.0, 1.0, 0.0),
      XY,
      false,
      -1.0,
    ),
  )
  assert_true(arc.sweep() > @math.PI)
  assert_near(arc.sweep(), 3.0 * @math.PI / 2.0, 1.0e-12)
}

///|
test "ZX plane uses its ordered axes" {
  let arc = arc_or_fail(
    solve_arc_ijk(
      Point3::new(0.0, 0.0, 1.0),
      Point3::new(1.0, 0.0, 0.0),
      ZX,
      false,
      Point3::new(0.0, 0.0, -1.0),
    ),
  )
  assert_eq(arc.center(), Point3::origin())
  assert_near(arc.sweep(), @math.PI / 2.0, 1.0e-12)
  assert_near(arc.bounds().max().x(), 1.0, 1.0e-12)
}

///|
test "YZ plane supports clockwise motion" {
  let arc = arc_or_fail(
    solve_arc_ijk(
      Point3::new(0.0, 1.0, 0.0),
      Point3::new(0.0, 0.0, -1.0),
      YZ,
      true,
      Point3::new(0.0, -1.0, 0.0),
    ),
  )
  assert_near(arc.sweep(), -@math.PI / 2.0, 1.0e-12)
  assert_near(arc.radius(), 1.0, 1.0e-12)
}

///|
test "helical quarter arc length includes axis rise" {
  let arc = arc_or_fail(
    solve_arc_ijk(
      Point3::new(1.0, 0.0, 0.0),
      Point3::new(0.0, 1.0, 3.0),
      XY,
      false,
      Point3::new(-1.0, 0.0, 0.0),
    ),
  )
  assert_near(arc.axis_delta(), 3.0, 1.0e-12)
  assert_near(arc.length(), @math.hypot(@math.PI / 2.0, 3.0), 1.0e-12)
}

///|
test "R rejects a radius smaller than the chord" {
  let result = solve_arc_radius(
    Point3::new(0.0, 0.0, 0.0),
    Point3::new(4.0, 0.0, 0.0),
    XY,
    false,
    1.0,
  )
  assert_true(result is Err(_))
  assert_eq(result.unwrap_err().code(), "geometry.arc.radius_too_small")
}

///|
test "IJK rejects an endpoint outside the circle" {
  let result = solve_arc_ijk(
    Point3::new(1.0, 0.0, 0.0),
    Point3::new(0.0, 2.0, 0.0),
    XY,
    false,
    Point3::new(-1.0, 0.0, 0.0),
  )
  assert_true(result is Err(_))
  assert_eq(result.unwrap_err().code(), "geometry.arc.endpoint_mismatch")
}

///|
test "invalid and non-finite geometry is diagnosed" {
  let zero = solve_arc_ijk(
    Point3::origin(),
    Point3::new(1.0, 0.0, 0.0),
    XY,
    false,
    Point3::origin(),
  )
  assert_eq(zero.unwrap_err().code(), "geometry.arc.radius.non_positive")
  let nan = solve_arc_radius(
    Point3::new(@math.acos(2.0), 0.0, 0.0),
    Point3::new(1.0, 0.0, 0.0),
    XY,
    false,
    1.0,
  )
  assert_eq(nan.unwrap_err().code(), "geometry.arc.non_finite")
  let target = resolve_target_point(
    Point3::origin(),
    Some(@math.exp(1000.0)),
    None,
    None,
    Millimeters,
    Absolute,
  )
  assert_eq(target.unwrap_err().code(), "geometry.target.non_finite")
}

///|
test "mixed geometry bounds merge lines and arcs" {
  let line = Segment::new(
    LinearSegment,
    1,
    Point3::new(-2.0, 0.0, 0.0),
    Point3::new(2.0, 0.0, 0.0),
    None,
    0.0,
    0.0,
    4.0,
    0.0,
    0.0,
  )
  let arc = arc_or_fail(
    solve_arc_ijk(
      Point3::new(1.0, 0.0, 0.0),
      Point3::new(0.0, 1.0, 0.0),
      XY,
      false,
      Point3::new(-1.0, 0.0, 0.0),
    ),
  )
  let merged = GeometryBounds::empty().add_segment(line).add_arc(arc)
  assert_eq(merged.count(), 2)
  assert_true(merged.bounds().unwrap().contains(Point3::new(-2.0, 0.0, 0.0)))
  assert_true(merged.bounds().unwrap().contains(Point3::new(1.0, 1.0, 0.0)))
}
