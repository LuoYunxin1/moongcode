///|
/// Deterministic modal G-code interpreter for offline toolpath replay.
fn interpreter_reline(
  error : Diagnostic,
  line : Int,
  column : Int,
) -> Diagnostic {
  Diagnostic::new(error.severity(), error.code(), line, column, error.message())
}

///|
fn interpreter_error(code : String, line : Int, message : String) -> Diagnostic {
  Diagnostic::error(code, line, 1, message)
}

///|
fn interpreter_warning(
  code : String,
  line : Int,
  message : String,
) -> Diagnostic {
  Diagnostic::warning(code, line, 1, message)
}

///|
fn interpreter_near(left : Double, right : Double) -> Bool {
  (left - right).abs() <= 1.0e-9
}

///|
fn interpreter_integer(
  value : Double,
  code : String,
  line : Int,
) -> Result[Int, Diagnostic] {
  if value.is_nan() || value.is_inf() || value < -1000000.0 || value > 1000000.0 {
    return Err(
      interpreter_error(code, line, "code is outside the supported range"),
    )
  }
  let integer = value.to_int()
  if integer.to_double() != value {
    Err(interpreter_error(code, line, "code must be an integer"))
  } else {
    Ok(integer)
  }
}

///|
fn interpreter_word(
  block : Block,
  letter : Char,
  diagnostics : Array[Diagnostic],
) -> Double? {
  let mut found : Double? = None
  for word in block.words() {
    if word.letter() == letter {
      if found is Some(_) {
        diagnostics.push(
          interpreter_error(
            "interpret.duplicate_word",
            block.source_line(),
            "word " + letter.to_string() + " occurs more than once",
          ),
        )
      } else {
        found = Some(word.value())
      }
    }
  }
  found
}

///|
fn interpreter_has(block : Block, letter : Char) -> Bool {
  block.words().any(fn(word) { word.letter() == letter })
}

///|
fn interpreter_scale(
  value : Double,
  units : Units,
  line : Int,
) -> Result[Double, Diagnostic] {
  match scale_distance_mm(value, units) {
    Ok(result) => Ok(result)
    Err(error) => Err(interpreter_reline(error, line, 1))
  }
}

///|
fn interpreter_axis_point(
  start : Point3,
  block : Block,
  units : Units,
  mode : DistanceMode,
  diagnostics : Array[Diagnostic],
) -> Result[Point3, Diagnostic] {
  let x = interpreter_word(block, 'X', diagnostics)
  let y = interpreter_word(block, 'Y', diagnostics)
  let z = interpreter_word(block, 'Z', diagnostics)
  match resolve_target_point(start, x, y, z, units, mode) {
    Ok(point) => Ok(point)
    Err(error) => Err(interpreter_reline(error, block.source_line(), 1))
  }
}

///|
fn interpreter_arc_offset(
  start : Point3,
  block : Block,
  units : Units,
  arc_mode : ArcDistanceMode,
  diagnostics : Array[Diagnostic],
) -> Result[Point3, Diagnostic] {
  let i = interpreter_word(block, 'I', diagnostics)
  let j = interpreter_word(block, 'J', diagnostics)
  let k = interpreter_word(block, 'K', diagnostics)
  let convert = fn(value : Double?) -> Result[Double?, Diagnostic] {
    match value {
      None => Ok(None)
      Some(raw) =>
        match interpreter_scale(raw, units, block.source_line()) {
          Ok(value) => Ok(Some(value))
          Err(error) => Err(error)
        }
    }
  }
  let ii = match convert(i) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let jj = match convert(j) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let kk = match convert(k) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  match arc_mode {
    ArcIncremental =>
      Ok(Point3::new(ii.unwrap_or(0.0), jj.unwrap_or(0.0), kk.unwrap_or(0.0)))
    ArcAbsolute => {
      let center_x = ii.unwrap_or(start.x())
      let center_y = jj.unwrap_or(start.y())
      let center_z = kk.unwrap_or(start.z())
      Ok(
        Point3::new(
          center_x - start.x(),
          center_y - start.y(),
          center_z - start.z(),
        ),
      )
    }
  }
}

///|
fn interpreter_make_segment(
  kind : SegmentKind,
  line : Int,
  start : Point3,
  end : Point3,
  center : Point3?,
  radius : Double,
  sweep : Double,
  feed : Double,
) -> Segment {
  let length = match kind {
    ClockwiseArcSegment | CounterClockwiseArcSegment => radius * sweep.abs()
    _ => distance3(start, end)
  }
  let duration = if feed > 0.0 { length / feed * 60.0 } else { 0.0 }
  Segment::new(
    kind, line, start, end, center, radius, sweep, length, duration, feed,
  )
}

///|
fn interpret_block(
  block : Block,
  before : MachineState,
  rapid_feed : Double,
  allow_unsupported : Bool,
) -> TraceStep {
  let diagnostics : Array[Diagnostic] = []
  let mut after = before
  let mut units = before.units()
  let mut distance_mode = before.distance_mode()
  let mut arc_distance_mode = before.arc_distance_mode()
  let mut plane = before.plane()
  let mut motion = before.motion()
  let mut feed = before.feed_mm_min()
  let mut spindle_rpm = before.spindle_rpm()
  let mut spindle = before.spindle()
  let mut tool = before.tool()
  let mut status = before.status()
  let segments : Array[Segment] = []
  let mut motion_seen = false
  let mut plane_seen = false
  let mut units_seen = false
  let mut distance_seen = false
  let mut arc_distance_seen = false
  let mut dwell_seen = false
  let mut spindle_seen = false
  let mut stop_seen = false

  if before.status() == Ended && !block.is_empty() {
    diagnostics.push(
      interpreter_error(
        "interpret.after_end",
        block.source_line(),
        "program already ended",
      ),
    )
    return TraceStep::new(
      block.source_line(),
      block,
      before,
      before,
      [],
      diagnostics,
    )
  }
  if before.status() == Paused {
    status = Ready
  }
  for word in block.words() {
    let letter = word.letter()
    if letter == 'G' {
      let code = match
        interpreter_integer(
          word.value(),
          "interpret.g_code",
          block.source_line(),
        ) {
        Ok(value) => value
        Err(_) => {
          if interpreter_near(word.value(), 90.1) ||
            interpreter_near(word.value(), 91.1) {
            if arc_distance_seen {
              diagnostics.push(
                interpreter_error(
                  "interpret.modal_conflict",
                  block.source_line(),
                  "G90.1/G91.1 conflicts with another distance mode",
                ),
              )
            } else {
              arc_distance_seen = true
              arc_distance_mode = if interpreter_near(word.value(), 90.1) {
                ArcAbsolute
              } else {
                ArcIncremental
              }
            }
          } else {
            diagnostics.push(
              interpreter_error(
                "interpret.g_code",
                block.source_line(),
                "G code must be a supported integer",
              ),
            )
          }
          -1
        }
      }
      if code >= 0 {
        match code {
          0 | 1 | 2 | 3 =>
            if motion_seen {
              diagnostics.push(
                interpreter_error(
                  "interpret.modal_conflict",
                  block.source_line(),
                  "more than one motion mode in a block",
                ),
              )
            } else {
              motion_seen = true
              motion = match code {
                0 => RapidMotion
                1 => LinearMotion
                2 => ClockwiseArc
                _ => CounterClockwiseArc
              }
            }
          4 =>
            if dwell_seen {
              diagnostics.push(
                interpreter_error(
                  "interpret.modal_conflict",
                  block.source_line(),
                  "duplicate dwell command",
                ),
              )
            } else {
              dwell_seen = true
            }
          17 | 18 | 19 =>
            if plane_seen {
              diagnostics.push(
                interpreter_error(
                  "interpret.modal_conflict",
                  block.source_line(),
                  "more than one plane in a block",
                ),
              )
            } else {
              plane_seen = true
              plane = match code {
                17 => XY
                18 => ZX
                _ => YZ
              }
            }
          20 | 21 =>
            if units_seen {
              diagnostics.push(
                interpreter_error(
                  "interpret.modal_conflict",
                  block.source_line(),
                  "more than one unit mode in a block",
                ),
              )
            } else {
              units_seen = true
              units = if code == 20 { Inches } else { Millimeters }
            }
          90 | 91 =>
            if distance_seen {
              diagnostics.push(
                interpreter_error(
                  "interpret.modal_conflict",
                  block.source_line(),
                  "more than one distance mode in a block",
                ),
              )
            } else {
              distance_seen = true
              distance_mode = if code == 90 { Absolute } else { Incremental }
            }
          _ =>
            if !allow_unsupported {
              diagnostics.push(
                interpreter_error(
                  "interpret.unsupported_g",
                  block.source_line(),
                  "unsupported G" + code.to_string(),
                ),
              )
            } else {
              diagnostics.push(
                interpreter_warning(
                  "interpret.unsupported_g",
                  block.source_line(),
                  "unsupported G" + code.to_string(),
                ),
              )
            }
        }
      }
    }
  }
  for word in block.words() {
    if word.letter() == 'M' {
      match
        interpreter_integer(
          word.value(),
          "interpret.m_code",
          block.source_line(),
        ) {
        Err(error) => diagnostics.push(error)
        Ok(code) =>
          match code {
            3 | 4 | 5 =>
              if spindle_seen {
                diagnostics.push(
                  interpreter_error(
                    "interpret.modal_conflict",
                    block.source_line(),
                    "more than one spindle command in a block",
                  ),
                )
              } else {
                spindle_seen = true
                spindle = match code {
                  3 => SpindleClockwise
                  4 => SpindleCounterClockwise
                  _ => SpindleOff
                }
              }
            0 | 1 | 2 | 30 =>
              if stop_seen {
                diagnostics.push(
                  interpreter_error(
                    "interpret.modal_conflict",
                    block.source_line(),
                    "more than one program-stop command in a block",
                  ),
                )
              } else {
                stop_seen = true
                status = match code {
                  0 | 1 => Paused
                  _ => Ended
                }
              }
            _ =>
              if !allow_unsupported {
                diagnostics.push(
                  interpreter_error(
                    "interpret.unsupported_m",
                    block.source_line(),
                    "unsupported M" + code.to_string(),
                  ),
                )
              } else {
                diagnostics.push(
                  interpreter_warning(
                    "interpret.unsupported_m",
                    block.source_line(),
                    "unsupported M" + code.to_string(),
                  ),
                )
              }
          }
      }
    }
  }
  let f = interpreter_word(block, 'F', diagnostics)
  match f {
    None => ()
    Some(value) =>
      match interpreter_scale(value, units, block.source_line()) {
        Ok(converted) =>
          if converted <= 0.0 {
            diagnostics.push(
              interpreter_error(
                "interpret.feed.invalid",
                block.source_line(),
                "feed must be positive",
              ),
            )
          } else {
            feed = converted
          }
        Err(error) => diagnostics.push(error)
      }
  }
  match interpreter_word(block, 'S', diagnostics) {
    None => ()
    Some(value) =>
      if value < 0.0 || value.is_nan() || value.is_inf() {
        diagnostics.push(
          interpreter_error(
            "interpret.spindle.invalid",
            block.source_line(),
            "spindle speed must be non-negative and finite",
          ),
        )
      } else {
        spindle_rpm = value
      }
  }
  match interpreter_word(block, 'T', diagnostics) {
    None => ()
    Some(value) =>
      match
        interpreter_integer(
          value,
          "interpret.tool.invalid",
          block.source_line(),
        ) {
        Ok(value) =>
          if value < 0 || value > 999 {
            diagnostics.push(
              interpreter_error(
                "interpret.tool.invalid",
                block.source_line(),
                "tool must be between 0 and 999",
              ),
            )
          } else {
            tool = value
          }
        Err(error) => diagnostics.push(error)
      }
  }
  for word in block.words() {
    if word.letter() == 'L' ||
      word.letter() == 'H' ||
      word.letter() == 'D' ||
      word.letter() == 'E' {
      if !allow_unsupported {
        diagnostics.push(
          interpreter_error(
            "interpret.unsupported_word",
            block.source_line(),
            "unsupported parameter " + word.letter().to_string(),
          ),
        )
      } else {
        diagnostics.push(
          interpreter_warning(
            "interpret.unsupported_word",
            block.source_line(),
            "unsupported parameter " + word.letter().to_string(),
          ),
        )
      }
    }
  }
  let axis_present = interpreter_has(block, 'X') ||
    interpreter_has(block, 'Y') ||
    interpreter_has(block, 'Z')
  let arc_present = interpreter_has(block, 'I') ||
    interpreter_has(block, 'J') ||
    interpreter_has(block, 'K') ||
    interpreter_has(block, 'R')
  if dwell_seen {
    if axis_present ||
      arc_present ||
      interpreter_has(block, 'F') ||
      interpreter_has(block, 'S') ||
      interpreter_has(block, 'T') {
      diagnostics.push(
        interpreter_error(
          "interpret.dwell_conflict",
          block.source_line(),
          "G4 accepts only P and program words",
        ),
      )
    }
    let p = interpreter_word(block, 'P', diagnostics)
    match p {
      None =>
        diagnostics.push(
          interpreter_error(
            "interpret.dwell.missing",
            block.source_line(),
            "G4 requires P dwell seconds",
          ),
        )
      Some(seconds) =>
        if seconds < 0.0 || seconds.is_nan() || seconds.is_inf() {
          diagnostics.push(
            interpreter_error(
              "interpret.dwell.invalid",
              block.source_line(),
              "dwell seconds must be finite and non-negative",
            ),
          )
        } else {
          segments.push(
            Segment::new(
              DwellSegment,
              block.source_line(),
              before.position(),
              before.position(),
              None,
              0.0,
              0.0,
              0.0,
              seconds,
              0.0,
            ),
          )
          after = after.replace(
            elapsed_seconds=before.elapsed_seconds() + seconds,
          )
        }
    }
  } else if interpreter_has(block, 'P') {
    diagnostics.push(
      interpreter_error(
        "interpret.parameter.orphan",
        block.source_line(),
        "P is only valid with G4",
      ),
    )
  }
  if axis_present || arc_present {
    if !motion_seen && motion == NoMotion {
      diagnostics.push(
        interpreter_error(
          "interpret.motion.missing",
          block.source_line(),
          "axis words require G0, G1, G2, or G3",
        ),
      )
    } else if motion == ClockwiseArc || motion == CounterClockwiseArc {
      if interpreter_has(block, 'R') &&
        arc_present &&
        (
          interpreter_has(block, 'I') ||
          interpreter_has(block, 'J') ||
          interpreter_has(block, 'K')
        ) {
        diagnostics.push(
          interpreter_error(
            "interpret.arc.conflict",
            block.source_line(),
            "an arc cannot use both R and IJK",
          ),
        )
      } else {
        let start = before.position()
        let end = match
          interpreter_axis_point(
            start, block, units, distance_mode, diagnostics,
          ) {
          Ok(value) => value
          Err(error) => {
            diagnostics.push(error)
            start
          }
        }
        let solved = if interpreter_has(block, 'R') {
          let radius = interpreter_word(block, 'R', diagnostics).unwrap()
          match interpreter_scale(radius, units, block.source_line()) {
            Ok(value) =>
              solve_arc_radius(start, end, plane, motion == ClockwiseArc, value)
            Err(error) => Err(error)
          }
        } else if interpreter_has(block, 'I') ||
          interpreter_has(block, 'J') ||
          interpreter_has(block, 'K') {
          match
            interpreter_arc_offset(
              start, block, units, arc_distance_mode, diagnostics,
            ) {
            Ok(offset) =>
              solve_arc_ijk(start, end, plane, motion == ClockwiseArc, offset)
            Err(error) => Err(error)
          }
        } else {
          Err(
            interpreter_error(
              "interpret.arc.center_missing",
              block.source_line(),
              "arc requires R or IJK",
            ),
          )
        }
        match solved {
          Err(error) =>
            diagnostics.push(interpreter_reline(error, block.source_line(), 1))
          Ok(arc) => {
            let kind = if motion == ClockwiseArc {
              ClockwiseArcSegment
            } else {
              CounterClockwiseArcSegment
            }
            let segment = interpreter_make_segment(
              kind,
              block.source_line(),
              start,
              end,
              Some(arc.center()),
              arc.radius_mm(),
              arc.sweep_radians(),
              feed,
            )
            if feed <= 0.0 {
              diagnostics.push(
                interpreter_error(
                  "interpret.feed.missing",
                  block.source_line(),
                  "cutting motion requires a positive feed",
                ),
              )
            }
            segments.push(segment)
            after = after.replace(
              position=end,
              elapsed_seconds=before.elapsed_seconds() +
                segment.duration_seconds(),
            )
          }
        }
      }
    } else if motion == RapidMotion || motion == LinearMotion {
      let start = before.position()
      let end = match
        interpreter_axis_point(start, block, units, distance_mode, diagnostics) {
        Ok(value) => value
        Err(error) => {
          diagnostics.push(error)
          start
        }
      }
      if arc_present {
        diagnostics.push(
          interpreter_error(
            "interpret.arc_parameter",
            block.source_line(),
            "IJK/R require G2 or G3",
          ),
        )
      }
      let length = distance3(start, end)
      if length > 1.0e-9 {
        let selected_feed = if motion == RapidMotion {
          rapid_feed
        } else {
          feed
        }
        if selected_feed <= 0.0 {
          diagnostics.push(
            interpreter_error(
              "interpret.feed.missing",
              block.source_line(),
              "motion requires a positive feed",
            ),
          )
        }
        let kind = if motion == RapidMotion {
          RapidSegment
        } else {
          LinearSegment
        }
        let segment = interpreter_make_segment(
          kind,
          block.source_line(),
          start,
          end,
          None,
          0.0,
          0.0,
          selected_feed,
        )
        segments.push(segment)
        after = after.replace(
          position=end,
          elapsed_seconds=before.elapsed_seconds() + segment.duration_seconds(),
        )
      }
    }
  }
  if spindle_rpm == 0.0 && spindle != SpindleOff {
    diagnostics.push(
      interpreter_warning(
        "interpret.spindle.zero_speed",
        block.source_line(),
        "spindle is enabled with zero RPM",
      ),
    )
  }
  after = after.replace(
    units~,
    distance_mode~,
    arc_distance_mode~,
    plane~,
    motion~,
    feed_mm_min=feed,
    spindle_rpm~,
    spindle~,
    tool~,
    status~,
  )
  TraceStep::new(
    block.source_line(),
    block,
    before,
    after,
    segments,
    diagnostics,
  )
}

///|
/// Execute a parsed program and return every modal transition and segment.
pub fn execute_program(
  program : Program,
  initial_state? : MachineState = MachineState::initial(),
  rapid_feed_mm_min? : Double = 6000.0,
  allow_unsupported? : Bool = false,
) -> Execution {
  let diagnostics = program.diagnostics()
  let rapid_feed = if rapid_feed_mm_min > 0.0 &&
    !rapid_feed_mm_min.is_nan() &&
    !rapid_feed_mm_min.is_inf() {
    rapid_feed_mm_min
  } else {
    6000.0
  }
  if rapid_feed_mm_min <= 0.0 ||
    rapid_feed_mm_min.is_nan() ||
    rapid_feed_mm_min.is_inf() {
    diagnostics.push(
      Diagnostic::error(
        "interpret.rapid_feed.invalid", 0, 0, "rapid feed must be finite and positive",
      ),
    )
  }
  let steps : Array[TraceStep] = []
  let segments : Array[Segment] = []
  let mut state = initial_state
  for block in program.blocks() {
    let step = interpret_block(block, state, rapid_feed, allow_unsupported)
    state = step.after()
    for segment in step.segments() {
      segments.push(segment)
    }
    for diagnostic in step.diagnostics() {
      diagnostics.push(diagnostic)
    }
    steps.push(step)
  }
  Execution::new(program, steps, segments, diagnostics, state)
}

///|
/// Parse and execute source text in one deterministic operation.
pub fn interpret_source(
  source : String,
  rapid_feed_mm_min? : Double = 6000.0,
  allow_unsupported? : Bool = false,
) -> Execution {
  execute_program(parse_program(source), rapid_feed_mm_min~, allow_unsupported~)
}
