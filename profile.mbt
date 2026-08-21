///|
pub struct AxisLimits {
  minimum_mm : Double
  maximum_mm : Double
} derive(Eq, @debug.Debug)

///|
pub fn AxisLimits::new(
  minimum_mm : Double,
  maximum_mm : Double,
) -> Result[AxisLimits, String] {
  if minimum_mm.is_nan() ||
    minimum_mm.is_inf() ||
    maximum_mm.is_nan() ||
    maximum_mm.is_inf() {
    Err("axis limits must be finite")
  } else if minimum_mm >= maximum_mm {
    Err("axis minimum must be less than maximum")
  } else {
    Ok({ minimum_mm, maximum_mm })
  }
}

///|
pub fn AxisLimits::minimum_mm(self : AxisLimits) -> Double {
  self.minimum_mm
}

///|
pub fn AxisLimits::maximum_mm(self : AxisLimits) -> Double {
  self.maximum_mm
}

///|
pub fn AxisLimits::contains(self : AxisLimits, value : Double) -> Bool {
  value >= self.minimum_mm && value <= self.maximum_mm
}

///|
pub fn AxisLimits::span_mm(self : AxisLimits) -> Double {
  self.maximum_mm - self.minimum_mm
}

///|
pub struct MachineProfile {
  name : String
  x : AxisLimits
  y : AxisLimits
  z : AxisLimits
  max_feed_mm_min : Double
  rapid_feed_mm_min : Double
  max_spindle_rpm : Double
  max_arc_radius_mm : Double
  max_dwell_seconds : Double
  require_spindle_for_cut : Bool
  allow_rapid_z_down : Bool
  allow_unsupported : Bool
  allowed_tools : Array[Int]
} derive(Eq, @debug.Debug)

///|
pub fn MachineProfile::new(
  name : String,
  x : AxisLimits,
  y : AxisLimits,
  z : AxisLimits,
  max_feed_mm_min : Double,
  rapid_feed_mm_min : Double,
  max_spindle_rpm : Double,
  max_arc_radius_mm : Double,
  max_dwell_seconds : Double,
  require_spindle_for_cut : Bool,
  allow_rapid_z_down : Bool,
  allow_unsupported : Bool,
  allowed_tools : Array[Int],
) -> Result[MachineProfile, String] {
  if name.trim().is_empty() {
    return Err("profile name must not be empty")
  }
  if max_feed_mm_min <= 0.0 ||
    max_feed_mm_min.is_nan() ||
    max_feed_mm_min.is_inf() {
    return Err("maximum feed must be finite and positive")
  }
  if rapid_feed_mm_min <= 0.0 ||
    rapid_feed_mm_min.is_nan() ||
    rapid_feed_mm_min.is_inf() {
    return Err("rapid feed must be finite and positive")
  }
  if max_spindle_rpm < 0.0 ||
    max_spindle_rpm.is_nan() ||
    max_spindle_rpm.is_inf() {
    return Err("maximum spindle speed must be finite and non-negative")
  }
  if max_arc_radius_mm <= 0.0 ||
    max_arc_radius_mm.is_nan() ||
    max_arc_radius_mm.is_inf() {
    return Err("maximum arc radius must be finite and positive")
  }
  if max_dwell_seconds < 0.0 ||
    max_dwell_seconds.is_nan() ||
    max_dwell_seconds.is_inf() {
    return Err("maximum dwell must be finite and non-negative")
  }
  let sorted_tools = allowed_tools.copy()
  sorted_tools.sort_by(fn(a, b) { a.compare(b) })
  for index = 0; index < sorted_tools.length(); index = index + 1 {
    if sorted_tools[index] < 0 || sorted_tools[index] > 999 {
      return Err("tool identifiers must be between 0 and 999")
    }
    if index > 0 && sorted_tools[index] == sorted_tools[index - 1] {
      return Err("tool identifiers must be unique")
    }
  }
  Ok({
    name: name.trim().to_owned(),
    x,
    y,
    z,
    max_feed_mm_min,
    rapid_feed_mm_min,
    max_spindle_rpm,
    max_arc_radius_mm,
    max_dwell_seconds,
    require_spindle_for_cut,
    allow_rapid_z_down,
    allow_unsupported,
    allowed_tools: sorted_tools,
  })
}

///|
pub fn MachineProfile::desktop_mill() -> MachineProfile {
  MachineProfile::new(
    "desktop-mill",
    AxisLimits::new(0.0, 300.0).unwrap(),
    AxisLimits::new(0.0, 180.0).unwrap(),
    AxisLimits::new(-80.0, 20.0).unwrap(),
    2400.0,
    6000.0,
    24000.0,
    500.0,
    30.0,
    true,
    false,
    false,
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  ).unwrap()
}

///|
/// Conservative profile for a small diode-laser engraver.
pub fn MachineProfile::desktop_laser() -> MachineProfile {
  MachineProfile::new(
    "desktop-laser",
    AxisLimits::new(0.0, 400.0).unwrap(),
    AxisLimits::new(0.0, 400.0).unwrap(),
    AxisLimits::new(0.0, 20.0).unwrap(),
    6000.0,
    10000.0,
    1000.0,
    1000.0,
    5.0,
    true,
    false,
    false,
    [0],
  ).unwrap()
}

///|
pub fn MachineProfile::name(self : MachineProfile) -> String {
  self.name
}

///|
pub fn MachineProfile::x(self : MachineProfile) -> AxisLimits {
  self.x
}

///|
pub fn MachineProfile::y(self : MachineProfile) -> AxisLimits {
  self.y
}

///|
pub fn MachineProfile::z(self : MachineProfile) -> AxisLimits {
  self.z
}

///|
pub fn MachineProfile::max_feed_mm_min(self : MachineProfile) -> Double {
  self.max_feed_mm_min
}

///|
pub fn MachineProfile::rapid_feed_mm_min(self : MachineProfile) -> Double {
  self.rapid_feed_mm_min
}

///|
pub fn MachineProfile::max_spindle_rpm(self : MachineProfile) -> Double {
  self.max_spindle_rpm
}

///|
pub fn MachineProfile::max_arc_radius_mm(self : MachineProfile) -> Double {
  self.max_arc_radius_mm
}

///|
pub fn MachineProfile::max_dwell_seconds(self : MachineProfile) -> Double {
  self.max_dwell_seconds
}

///|
pub fn MachineProfile::require_spindle_for_cut(self : MachineProfile) -> Bool {
  self.require_spindle_for_cut
}

///|
pub fn MachineProfile::allow_rapid_z_down(self : MachineProfile) -> Bool {
  self.allow_rapid_z_down
}

///|
pub fn MachineProfile::allow_unsupported(self : MachineProfile) -> Bool {
  self.allow_unsupported
}

///|
pub fn MachineProfile::allowed_tools(self : MachineProfile) -> Array[Int] {
  self.allowed_tools.copy()
}

///|
pub fn MachineProfile::allows_tool(self : MachineProfile, tool : Int) -> Bool {
  self.allowed_tools.is_empty() || self.allowed_tools.contains(tool)
}

///|
pub fn MachineProfile::to_text(self : MachineProfile) -> String {
  let tool_text = self.allowed_tools
    .map(fn(value) { value.to_string() })
    .join(",")
  "MOONGCODE_PROFILE 1\n" +
  "name " +
  self.name +
  "\n" +
  "axis X " +
  self.x.minimum_mm().to_string() +
  " " +
  self.x.maximum_mm().to_string() +
  "\n" +
  "axis Y " +
  self.y.minimum_mm().to_string() +
  " " +
  self.y.maximum_mm().to_string() +
  "\n" +
  "axis Z " +
  self.z.minimum_mm().to_string() +
  " " +
  self.z.maximum_mm().to_string() +
  "\n" +
  "max-feed " +
  self.max_feed_mm_min.to_string() +
  "\n" +
  "rapid-feed " +
  self.rapid_feed_mm_min.to_string() +
  "\n" +
  "max-spindle " +
  self.max_spindle_rpm.to_string() +
  "\n" +
  "max-arc-radius " +
  self.max_arc_radius_mm.to_string() +
  "\n" +
  "max-dwell " +
  self.max_dwell_seconds.to_string() +
  "\n" +
  "require-spindle " +
  self.require_spindle_for_cut.to_string() +
  "\n" +
  "allow-rapid-z-down " +
  self.allow_rapid_z_down.to_string() +
  "\n" +
  "allow-unsupported " +
  self.allow_unsupported.to_string() +
  "\n" +
  "tools " +
  tool_text
}

///|
fn parse_axis_limit(
  fields : Array[String],
  line : Int,
) -> Result[(Char, AxisLimits), Diagnostic] {
  if fields.length() != 4 || fields[1].length() != 1 {
    return Err(
      Diagnostic::error(
        "profile.axis.shape", line, 1, "expected: axis X MIN MAX",
      ),
    )
  }
  let axis = fields[1].to_array()[0]
  if axis != 'X' && axis != 'Y' && axis != 'Z' {
    return Err(
      Diagnostic::error("profile.axis.name", line, 6, "axis must be X, Y, or Z"),
    )
  }
  let minimum = match
    parse_finite_double(fields[2], "profile.axis.minimum", line, 8) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let maximum = match
    parse_finite_double(fields[3], "profile.axis.maximum", line, 8) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match AxisLimits::new(minimum, maximum) {
    Ok(value) => Ok((axis, value))
    Err(message) =>
      Err(Diagnostic::error("profile.axis.range", line, 1, message))
  }
}

///|
fn parse_profile_number(
  fields : Array[String],
  line : Int,
  key : String,
) -> Result[Double, Diagnostic] {
  if fields.length() != 2 || fields[0] != key {
    return Err(
      Diagnostic::error(
        "profile.field.shape",
        line,
        1,
        "expected: " + key + " NUMBER",
      ),
    )
  }
  parse_finite_double(fields[1], "profile." + key, line, key.length() + 2)
}

///|
fn parse_profile_bool(
  fields : Array[String],
  line : Int,
  key : String,
) -> Result[Bool, Diagnostic] {
  if fields.length() != 2 || fields[0] != key {
    return Err(
      Diagnostic::error(
        "profile.field.shape",
        line,
        1,
        "expected: " + key + " BOOLEAN",
      ),
    )
  }
  parse_strict_bool(fields[1], "profile." + key, line)
}

///|
fn parse_tool_list(
  value : String,
  line : Int,
) -> Result[Array[Int], Diagnostic] {
  if value == "*" {
    return Ok([])
  }
  let tools : Array[Int] = []
  for item in value.split(",") {
    let text = item.to_owned()
    let tool = match parse_bounded_int(text, 0, 999, "profile.tools", line) {
      Ok(number) => number
      Err(error) => return Err(error)
    }
    if tools.contains(tool) {
      return Err(
        Diagnostic::error(
          "profile.tools.duplicate",
          line,
          1,
          "duplicate tool " + text,
        ),
      )
    }
    tools.push(tool)
  }
  Ok(tools)
}

///|
pub fn parse_profile(
  source : String,
) -> Result[MachineProfile, Array[Diagnostic]] {
  let lines = split_source_lines(source)
  let diagnostics : Array[Diagnostic] = []
  if lines.is_empty() || lines[0].trim() != "MOONGCODE_PROFILE 1" {
    diagnostics.push(
      Diagnostic::error("profile.header", 1, 1, "expected MOONGCODE_PROFILE 1"),
    )
    return Err(diagnostics)
  }
  let mut name : String? = None
  let mut x : AxisLimits? = None
  let mut y : AxisLimits? = None
  let mut z : AxisLimits? = None
  let mut max_feed : Double? = None
  let mut rapid_feed : Double? = None
  let mut max_spindle : Double? = None
  let mut max_arc_radius : Double? = None
  let mut max_dwell : Double? = None
  let mut require_spindle : Bool? = None
  let mut allow_rapid_z_down : Bool? = None
  let mut allow_unsupported : Bool? = None
  let mut tools : Array[Int]? = None
  for index = 1; index < lines.length(); index = index + 1 {
    let line_number = index + 1
    let clean = lines[index].trim().to_owned()
    if clean.is_empty() || clean.has_prefix("#") {
      continue
    }
    let fields = split_ascii_fields(clean)
    if fields.is_empty() {
      continue
    }
    match fields[0] {
      "name" =>
        if fields.length() != 2 || fields[1].is_empty() {
          diagnostics.push(
            Diagnostic::error(
              "profile.name", line_number, 1, "expected: name IDENTIFIER",
            ),
          )
        } else if name is Some(_) {
          diagnostics.push(
            Diagnostic::error(
              "profile.duplicate", line_number, 1, "duplicate name field",
            ),
          )
        } else {
          name = Some(fields[1])
        }
      "axis" =>
        match parse_axis_limit(fields, line_number) {
          Err(error) => diagnostics.push(error)
          Ok((axis, limits)) =>
            match axis {
              'X' =>
                if x is Some(_) {
                  diagnostics.push(
                    Diagnostic::error(
                      "profile.duplicate", line_number, 1, "duplicate X axis",
                    ),
                  )
                } else {
                  x = Some(limits)
                }
              'Y' =>
                if y is Some(_) {
                  diagnostics.push(
                    Diagnostic::error(
                      "profile.duplicate", line_number, 1, "duplicate Y axis",
                    ),
                  )
                } else {
                  y = Some(limits)
                }
              _ =>
                if z is Some(_) {
                  diagnostics.push(
                    Diagnostic::error(
                      "profile.duplicate", line_number, 1, "duplicate Z axis",
                    ),
                  )
                } else {
                  z = Some(limits)
                }
            }
        }
      "max-feed" =>
        match parse_profile_number(fields, line_number, "max-feed") {
          Ok(v) =>
            if max_feed is Some(_) {
              diagnostics.push(
                Diagnostic::error(
                  "profile.duplicate", line_number, 1, "duplicate max-feed",
                ),
              )
            } else {
              max_feed = Some(v)
            }
          Err(e) => diagnostics.push(e)
        }
      "rapid-feed" =>
        match parse_profile_number(fields, line_number, "rapid-feed") {
          Ok(v) =>
            if rapid_feed is Some(_) {
              diagnostics.push(
                Diagnostic::error(
                  "profile.duplicate", line_number, 1, "duplicate rapid-feed",
                ),
              )
            } else {
              rapid_feed = Some(v)
            }
          Err(e) => diagnostics.push(e)
        }
      "max-spindle" =>
        match parse_profile_number(fields, line_number, "max-spindle") {
          Ok(v) =>
            if max_spindle is Some(_) {
              diagnostics.push(
                Diagnostic::error(
                  "profile.duplicate", line_number, 1, "duplicate max-spindle",
                ),
              )
            } else {
              max_spindle = Some(v)
            }
          Err(e) => diagnostics.push(e)
        }
      "max-arc-radius" =>
        match parse_profile_number(fields, line_number, "max-arc-radius") {
          Ok(v) =>
            if max_arc_radius is Some(_) {
              diagnostics.push(
                Diagnostic::error(
                  "profile.duplicate", line_number, 1, "duplicate max-arc-radius",
                ),
              )
            } else {
              max_arc_radius = Some(v)
            }
          Err(e) => diagnostics.push(e)
        }
      "max-dwell" =>
        match parse_profile_number(fields, line_number, "max-dwell") {
          Ok(v) =>
            if max_dwell is Some(_) {
              diagnostics.push(
                Diagnostic::error(
                  "profile.duplicate", line_number, 1, "duplicate max-dwell",
                ),
              )
            } else {
              max_dwell = Some(v)
            }
          Err(e) => diagnostics.push(e)
        }
      "require-spindle" =>
        match parse_profile_bool(fields, line_number, "require-spindle") {
          Ok(v) =>
            if require_spindle is Some(_) {
              diagnostics.push(
                Diagnostic::error(
                  "profile.duplicate", line_number, 1, "duplicate require-spindle",
                ),
              )
            } else {
              require_spindle = Some(v)
            }
          Err(e) => diagnostics.push(e)
        }
      "allow-rapid-z-down" =>
        match parse_profile_bool(fields, line_number, "allow-rapid-z-down") {
          Ok(v) =>
            if allow_rapid_z_down is Some(_) {
              diagnostics.push(
                Diagnostic::error(
                  "profile.duplicate", line_number, 1, "duplicate allow-rapid-z-down",
                ),
              )
            } else {
              allow_rapid_z_down = Some(v)
            }
          Err(e) => diagnostics.push(e)
        }
      "allow-unsupported" =>
        match parse_profile_bool(fields, line_number, "allow-unsupported") {
          Ok(v) =>
            if allow_unsupported is Some(_) {
              diagnostics.push(
                Diagnostic::error(
                  "profile.duplicate", line_number, 1, "duplicate allow-unsupported",
                ),
              )
            } else {
              allow_unsupported = Some(v)
            }
          Err(e) => diagnostics.push(e)
        }
      "tools" =>
        if fields.length() != 2 {
          diagnostics.push(
            Diagnostic::error(
              "profile.tools", line_number, 1, "expected: tools 0,1,2 or tools *",
            ),
          )
        } else if tools is Some(_) {
          diagnostics.push(
            Diagnostic::error(
              "profile.duplicate", line_number, 1, "duplicate tools field",
            ),
          )
        } else {
          match parse_tool_list(fields[1], line_number) {
            Ok(v) => tools = Some(v)
            Err(e) => diagnostics.push(e)
          }
        }
      key =>
        diagnostics.push(
          Diagnostic::error(
            "profile.unknown",
            line_number,
            1,
            "unknown profile field " + key,
          ),
        )
    }
  }
  let required : Array[(String, Bool)] = [
    ("name", name is Some(_)),
    ("axis X", x is Some(_)),
    ("axis Y", y is Some(_)),
    ("axis Z", z is Some(_)),
    ("max-feed", max_feed is Some(_)),
    ("rapid-feed", rapid_feed is Some(_)),
    ("max-spindle", max_spindle is Some(_)),
    ("max-arc-radius", max_arc_radius is Some(_)),
    ("max-dwell", max_dwell is Some(_)),
    ("require-spindle", require_spindle is Some(_)),
    ("allow-rapid-z-down", allow_rapid_z_down is Some(_)),
    ("allow-unsupported", allow_unsupported is Some(_)),
    ("tools", tools is Some(_)),
  ]
  for pair in required {
    let (field, present) = pair
    if !present {
      diagnostics.push(
        Diagnostic::error(
          "profile.missing",
          1,
          1,
          "missing required field " + field,
        ),
      )
    }
  }
  if diagnostics_have_errors(diagnostics) {
    return Err(diagnostics)
  }
  match
    MachineProfile::new(
      name.unwrap(),
      x.unwrap(),
      y.unwrap(),
      z.unwrap(),
      max_feed.unwrap(),
      rapid_feed.unwrap(),
      max_spindle.unwrap(),
      max_arc_radius.unwrap(),
      max_dwell.unwrap(),
      require_spindle.unwrap(),
      allow_rapid_z_down.unwrap(),
      allow_unsupported.unwrap(),
      tools.unwrap(),
    ) {
    Ok(profile) => Ok(profile)
    Err(message) => {
      diagnostics.push(Diagnostic::error("profile.invalid", 1, 1, message))
      Err(diagnostics)
    }
  }
}
