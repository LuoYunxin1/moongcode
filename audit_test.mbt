///|
fn audited(source : String) -> SafetyReport {
  audit_execution(interpret_source(source), MachineProfile::desktop_mill())
}

///|
test "statistics count rapid cut arc and dwell" {
  let report = audited(
    "G21 F600 M3 S1000\nG0 X10 Y10 Z5\nG1 Z0\nG2 X0 Y10 I-5 J0\nG4 P1\nM5 M30\n",
  )
  assert_eq(report.stats().segment_count(), 4)
  assert_eq(report.stats().rapid_count(), 1)
  assert_eq(report.stats().dwell_count(), 1)
  assert_true(report.stats().arc_distance_mm() > 0.0)
}

///|
test "safe completed program passes" {
  let report = audited(
    "G21 G90 F300 M3 S1000\nG0 X10 Y10 Z5\nG1 Z0\nG1 X20\nM5 M30\n",
  )
  assert_true(report.passed())
}

///|
test "workspace overflow is rejected" {
  let report = audited("G21 F100 M3 S100\nG1 X400\nM5 M30\n")
  assert_false(report.passed())
  assert_true(
    report.findings().any(fn(item) { item.code() == "audit.workspace.bounds" }),
  )
}

///|
test "feed and spindle limits are rejected" {
  let report = audited("G21 F99999 M3 S99999\nG1 X10\nM5 M30\n")
  assert_true(
    report.findings().any(fn(item) { item.code() == "audit.feed.limit" }),
  )
  assert_true(
    report.findings().any(fn(item) { item.code() == "audit.spindle.limit" }),
  )
}

///|
test "cut with spindle off is rejected" {
  let report = audited("G21 F100\nG1 X10\nM30\n")
  assert_true(
    report.findings().any(fn(item) { item.code() == "audit.spindle.off" }),
  )
}

///|
test "rapid Z descent is rejected" {
  let report = audited("G21 G90\nG0 Z-10\nM30\n")
  assert_true(
    report.findings().any(fn(item) { item.code() == "audit.rapid.z_down" }),
  )
}

///|
test "dwell and arc radius limits are checked" {
  let report = audited("G21 F100 M3 S100\nG2 X10 Y0 R1000\nG4 P99\nM5 M30\n")
  assert_true(
    report.findings().any(fn(item) { item.code() == "audit.arc.radius" }),
  )
  assert_true(
    report.findings().any(fn(item) { item.code() == "audit.dwell.limit" }),
  )
}

///|
test "tool allowlist is checked" {
  let report = audited("T99 M30\n")
  assert_true(
    report.findings().any(fn(item) { item.code() == "audit.tool.forbidden" }),
  )
}

///|
test "unended and unclosed programs are rejected" {
  let report = audited("M3 S100\n")
  assert_true(
    report.findings().any(fn(item) { item.code() == "audit.program.unended" }),
  )
  assert_true(
    report.findings().any(fn(item) { item.code() == "audit.spindle.unclosed" }),
  )
}

///|
test "report text is deterministic" {
  let text = safety_report_text(audited("M30\n"))
  assert_true(text.has_prefix("PASS\nsegments=0"))
  assert_true(text.contains("warning[audit.program.empty]"))
}

///|
test "empty completed program is a warning rather than an error" {
  let report = audited("M30\n")
  assert_true(report.passed())
  assert_eq(report.error_count(), 0)
  assert_eq(report.warning_count(), 1)
  assert_eq(diagnostics_count_code(report.findings(), "audit.program.empty"), 1)
}

///|
test "safety report counts errors independently from warnings" {
  let report = audited("G21 F100\nG1 X400\n")
  assert_true(report.error_count() >= 3)
  assert_eq(report.warning_count(), 0)
  assert_false(report.passed())
}

///|
test "statistics text includes envelope and distance classes" {
  let stats = analyze_execution(
    interpret_source("G21 F60 M3 S100\nG1 X10\nM5 M30\n"),
  )
  let text = stats.to_text()
  assert_true(text.contains("segments=1 rapid=0 cutting=1 dwell=0"))
  assert_true(text.contains("bounds=(0,0,0)..(10,0,0)"))
  assert_true(text.contains("estimated_seconds=10"))
}

///|
test "markdown report exposes decision metrics and findings" {
  let report = audited("M30\n")
  let markdown = safety_report_markdown(report)
  assert_true(markdown.has_prefix("# MoonGCode audit: PASS"))
  assert_true(markdown.contains("| Segments | 0 |"))
  assert_true(markdown.contains("`audit.program.empty` line 0"))
}

///|
test "same-block plane switch has the same envelope as a separate block" {
  for
    command in [
      "G18 G2 X0 Z10 R5", "G18 G3 X0 Z10 R5", "G19 G2 Y0 Z10 R5", "G19 G3 Y0 Z10 R5",
    ] {
    let same = interpret_source("G21 F60 M3 S1000\n" + command + "\nM5 M30\n")
    let split = interpret_source(
      "G21 F60 M3 S1000\n" +
      command[0:3].to_owned() +
      "\n" +
      command[4:].to_owned() +
      "\nM5 M30\n",
    )
    assert_true(same.is_valid())
    assert_true(split.is_valid())
    assert_eq(
      analyze_execution(same).bounds(),
      analyze_execution(split).bounds(),
    )
    let same_report = audit_execution(same, MachineProfile::desktop_mill())
    let split_report = audit_execution(split, MachineProfile::desktop_mill())
    assert_eq(same_report.passed(), split_report.passed())
  }
}

///|
test "same-block G18 full circle detects hidden Z workspace excursion" {
  let profile = MachineProfile::new(
    "shallow-z",
    AxisLimits::new(-100.0, 100.0).unwrap(),
    AxisLimits::new(-100.0, 100.0).unwrap(),
    AxisLimits::new(-4.0, 4.0).unwrap(),
    2400.0,
    6000.0,
    24000.0,
    500.0,
    30.0,
    true,
    false,
    false,
    [0],
  ).unwrap()
  let execution = interpret_source("G21 F60 M3 S1000\nG18 G2 I5 K0\nM5 M30\n")
  assert_true(execution.is_valid())
  let report = audit_execution(execution, profile)
  assert_false(report.passed())
  assert_true(
    report
    .findings()
    .any(fn(d) { d.code() == "audit.workspace.bounds" && d.line() == 2 }),
  )
}
