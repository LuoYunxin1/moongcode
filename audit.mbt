///|
/// Toolpath metrics and machine-profile safety findings.
pub struct ToolpathStats {
  segment_count : Int
  rapid_count : Int
  cutting_count : Int
  dwell_count : Int
  rapid_distance_mm : Double
  cutting_distance_mm : Double
  arc_distance_mm : Double
  total_distance_mm : Double
  estimated_seconds : Double
  bounds : Bounds3?
} derive(Eq, @debug.Debug)

///|
pub fn ToolpathStats::segment_count(self : ToolpathStats) -> Int {
  self.segment_count
}

///|
pub fn ToolpathStats::rapid_count(self : ToolpathStats) -> Int {
  self.rapid_count
}

///|
pub fn ToolpathStats::cutting_count(self : ToolpathStats) -> Int {
  self.cutting_count
}

///|
pub fn ToolpathStats::dwell_count(self : ToolpathStats) -> Int {
  self.dwell_count
}

///|
pub fn ToolpathStats::rapid_distance_mm(self : ToolpathStats) -> Double {
  self.rapid_distance_mm
}

///|
pub fn ToolpathStats::cutting_distance_mm(self : ToolpathStats) -> Double {
  self.cutting_distance_mm
}

///|
pub fn ToolpathStats::arc_distance_mm(self : ToolpathStats) -> Double {
  self.arc_distance_mm
}

///|
pub fn ToolpathStats::total_distance_mm(self : ToolpathStats) -> Double {
  self.total_distance_mm
}

///|
pub fn ToolpathStats::estimated_seconds(self : ToolpathStats) -> Double {
  self.estimated_seconds
}

///|
pub fn ToolpathStats::bounds(self : ToolpathStats) -> Bounds3? {
  self.bounds
}

///|
/// Render stable metrics including the complete geometric envelope.
pub fn ToolpathStats::to_text(self : ToolpathStats) -> String {
  let mut result = "segments=" + self.segment_count.to_string()
  result += " rapid=" + self.rapid_count.to_string()
  result += " cutting=" + self.cutting_count.to_string()
  result += " dwell=" + self.dwell_count.to_string()
  result += "\ndistance_mm=" + self.total_distance_mm.to_string()
  result += " rapid_mm=" + self.rapid_distance_mm.to_string()
  result += " cutting_mm=" + self.cutting_distance_mm.to_string()
  result += " arc_mm=" + self.arc_distance_mm.to_string()
  result += "\nestimated_seconds=" + self.estimated_seconds.to_string()
  match self.bounds {
    None => result += "\nbounds=empty"
    Some(bounds) =>
      result += "\nbounds=" +
        bounds.min().to_text() +
        ".." +
        bounds.max().to_text()
  }
  result
}

///|
fn audit_add_bounds(current : Bounds3?, next : Bounds3) -> Bounds3 {
  match current {
    None => next
    Some(value) => value.merge(next)
  }
}

///|
/// Summarize distances, duration, counts, and the complete geometric envelope.
pub fn analyze_execution(execution : Execution) -> ToolpathStats {
  let mut rapid_count = 0
  let mut cutting_count = 0
  let mut dwell_count = 0
  let mut rapid_distance = 0.0
  let mut cutting_distance = 0.0
  let mut arc_distance = 0.0
  let mut total_distance = 0.0
  let mut seconds = 0.0
  let mut bounds : Bounds3? = None
  for step in execution.steps() {
    let plane = step.before().plane()
    for segment in step.segments() {
      let length = segment.length_mm()
      let duration = segment.duration_seconds()
      total_distance += length
      seconds += duration
      match segment.kind() {
        RapidSegment => {
          rapid_count += 1
          rapid_distance += length
        }
        LinearSegment => {
          cutting_count += 1
          cutting_distance += length
        }
        ClockwiseArcSegment | CounterClockwiseArcSegment => {
          cutting_count += 1
          cutting_distance += length
          arc_distance += length
        }
        DwellSegment => dwell_count += 1
      }
      bounds = Some(audit_add_bounds(bounds, segment_bounds(segment, plane~)))
    }
  }
  {
    segment_count: execution.segments().length(),
    rapid_count,
    cutting_count,
    dwell_count,
    rapid_distance_mm: rapid_distance,
    cutting_distance_mm: cutting_distance,
    arc_distance_mm: arc_distance,
    total_distance_mm: total_distance,
    estimated_seconds: seconds,
    bounds,
  }
}

///|
pub struct SafetyReport {
  stats : ToolpathStats
  findings : Array[Diagnostic]
} derive(Eq, @debug.Debug)

///|
pub fn SafetyReport::stats(self : SafetyReport) -> ToolpathStats {
  self.stats
}

///|
pub fn SafetyReport::findings(self : SafetyReport) -> Array[Diagnostic] {
  self.findings.copy()
}

///|
pub fn SafetyReport::passed(self : SafetyReport) -> Bool {
  !diagnostics_have_errors(self.findings)
}

///|
/// Check a replay against a bounded machine profile. Findings are stable and
/// line-addressed so CI and operator tooling can explain every rejection.
pub fn audit_execution(
  execution : Execution,
  profile : MachineProfile,
) -> SafetyReport {
  let findings = execution.diagnostics()
  for step in execution.steps() {
    let before = step.before()
    let after = step.after()
    if !profile.allows_tool(after.tool()) {
      findings.push(
        Diagnostic::error(
          "audit.tool.forbidden",
          step.source_line(),
          1,
          "tool T" + after.tool().to_string() + " is not allowed by profile",
        ),
      )
    }
    if after.spindle_rpm() > profile.max_spindle_rpm() {
      findings.push(
        Diagnostic::error(
          "audit.spindle.limit",
          step.source_line(),
          1,
          "spindle speed exceeds profile maximum",
        ),
      )
    }
    for segment in step.segments() {
      let envelope = segment_bounds(segment, plane=before.plane())
      let min = envelope.min()
      let max = envelope.max()
      if !profile.x().contains(min.x()) ||
        !profile.x().contains(max.x()) ||
        !profile.y().contains(min.y()) ||
        !profile.y().contains(max.y()) ||
        !profile.z().contains(min.z()) ||
        !profile.z().contains(max.z()) {
        findings.push(
          Diagnostic::error(
            "audit.workspace.bounds",
            segment.source_line(),
            1,
            "toolpath leaves the machine workspace",
          ),
        )
      }
      match segment.kind() {
        RapidSegment => {
          if segment.feed_mm_min() > profile.rapid_feed_mm_min() {
            findings.push(
              Diagnostic::error(
                "audit.rapid.feed",
                segment.source_line(),
                1,
                "rapid feed exceeds profile maximum",
              ),
            )
          }
          if segment.end().z() < segment.start().z() &&
            !profile.allow_rapid_z_down() {
            findings.push(
              Diagnostic::error(
                "audit.rapid.z_down",
                segment.source_line(),
                1,
                "rapid move descends in Z",
              ),
            )
          }
        }
        LinearSegment | ClockwiseArcSegment | CounterClockwiseArcSegment => {
          if segment.feed_mm_min() > profile.max_feed_mm_min() {
            findings.push(
              Diagnostic::error(
                "audit.feed.limit",
                segment.source_line(),
                1,
                "cutting feed exceeds profile maximum",
              ),
            )
          }
          if profile.require_spindle_for_cut() && after.spindle() == SpindleOff {
            findings.push(
              Diagnostic::error(
                "audit.spindle.off",
                segment.source_line(),
                1,
                "cutting motion runs with spindle off",
              ),
            )
          }
          if (
              segment.kind() == ClockwiseArcSegment ||
              segment.kind() == CounterClockwiseArcSegment
            ) &&
            segment.radius_mm() > profile.max_arc_radius_mm() {
            findings.push(
              Diagnostic::error(
                "audit.arc.radius",
                segment.source_line(),
                1,
                "arc radius exceeds profile maximum",
              ),
            )
          }
        }
        DwellSegment =>
          if segment.duration_seconds() > profile.max_dwell_seconds() {
            findings.push(
              Diagnostic::error(
                "audit.dwell.limit",
                segment.source_line(),
                1,
                "dwell exceeds profile maximum",
              ),
            )
          }
      }
    }
  }
  let final_state = execution.final_state()
  if execution.segments().is_empty() {
    findings.push(
      Diagnostic::warning(
        "audit.program.empty", 0, 0, "program produces no motion or dwell segments",
      ),
    )
  }
  if final_state.status() != Ended {
    findings.push(
      Diagnostic::error(
        "audit.program.unended", 0, 0, "program does not end with M2 or M30",
      ),
    )
  }
  if final_state.spindle() != SpindleOff {
    findings.push(
      Diagnostic::error(
        "audit.spindle.unclosed", 0, 0, "program ends with spindle enabled",
      ),
    )
  }
  { stats: analyze_execution(execution), findings }
}

///|
pub fn safety_report_text(report : SafetyReport) -> String {
  let mut result = if report.passed() { "PASS" } else { "FAIL" }
  let stats = report.stats()
  result += "\nsegments=" + stats.segment_count().to_string()
  result += " distance_mm=" + stats.total_distance_mm().to_string()
  result += " seconds=" + stats.estimated_seconds().to_string()
  if !report.findings().is_empty() {
    result += "\nfindings:"
    for finding in report.findings() {
      result += "\n- " + finding.to_text()
    }
  }
  result
}

///|
/// Render a compact Markdown artifact suitable for CI summaries.
pub fn safety_report_markdown(report : SafetyReport) -> String {
  let stats = report.stats()
  let mut result = if report.passed() {
    "# MoonGCode audit: PASS"
  } else {
    "# MoonGCode audit: FAIL"
  }
  result += "\n\n| Metric | Value |\n| --- | ---: |"
  result += "\n| Segments | " + stats.segment_count().to_string() + " |"
  result += "\n| Distance (mm) | " +
    stats.total_distance_mm().to_string() +
    " |"
  result += "\n| Estimated time (s) | " +
    stats.estimated_seconds().to_string() +
    " |"
  result += "\n\n## Findings"
  if report.findings().is_empty() {
    result += "\n\nNone."
  } else {
    for finding in report.findings() {
      result += "\n\n- `" +
        finding.code() +
        "` line " +
        finding.line().to_string() +
        ": " +
        finding.message()
    }
  }
  result
}
