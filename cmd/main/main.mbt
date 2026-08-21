///|
fn demo_source() -> String {
  "G21 G90 F600\n" +
  "T1 M3 S12000\n" +
  "G0 X10 Y10 Z5\n" +
  "G1 Z0\n" +
  "G1 X30 Y10\n" +
  "G2 X10 Y10 I-10 J0\n" +
  "G4 P0.5\n" +
  "M5 M30\n"
}

///|
fn usage() -> String {
  "MoonGCode - deterministic G-code replay and safety preflight\n" +
  "usage: moon run cmd/main -- <command> [file]\n\n" +
  "commands: demo, profiles, validate, normalize, trace, analyze, audit, audit-laser, audit-profile, audit-md, explain\n" +
  "file is UTF-8 G-code; demo uses a built-in program"
}

///|
fn read_source(path : String) -> Result[String, String] {
  Ok(@fs.read_file_to_string(path)) catch {
    @fs.IOError(message) => Err(message)
  }
}

///|
fn stats_text(execution : @lib.Execution) -> String {
  let stats = @lib.analyze_execution(execution)
  "segments=" +
  stats.segment_count().to_string() +
  " rapid=" +
  stats.rapid_count().to_string() +
  " cutting=" +
  stats.cutting_count().to_string() +
  " dwell=" +
  stats.dwell_count().to_string() +
  " distance_mm=" +
  stats.total_distance_mm().to_string() +
  " seconds=" +
  stats.estimated_seconds().to_string()
}

///|
fn main {
  let raw = @env.args()
  let commands = [
    "demo", "profiles", "validate", "normalize", "trace", "analyze", "audit", "audit-laser",
    "audit-profile", "audit-md", "explain", "help", "--help", "-h",
  ]
  let mut command_index = raw.length()
  for index, value in raw {
    if command_index == raw.length() && commands.contains(value) {
      command_index = index
    }
  }
  let args = if command_index < raw.length() {
    raw[command_index:].to_owned()
  } else {
    ["demo"]
  }
  let command = args[0]
  if command == "help" || command == "--help" || command == "-h" {
    println(usage())
    return
  }
  if command == "profiles" {
    println("=== desktop-mill ===")
    println(@lib.MachineProfile::desktop_mill().to_text())
    println("=== desktop-laser ===")
    println(@lib.MachineProfile::desktop_laser().to_text())
    return
  }
  let source = if command == "demo" && args.length() == 1 {
    demo_source()
  } else {
    if args.length() < 2 {
      println("cli.file.required: provide a G-code file or use demo")
      @sys.exit(2)
      return
    }
    match read_source(args[1]) {
      Ok(value) => value
      Err(message) => {
        println("io.read.failed: " + message)
        @sys.exit(2)
        return
      }
    }
  }
  let program = @lib.parse_program(source)
  if command == "validate" {
    println(@lib.validate_report(program))
    if !program.is_valid() {
      @sys.exit(1)
    }
    return
  }
  if command == "normalize" {
    println(@lib.normalize_program(program, preserve_comments=true))
    return
  }
  if command == "explain" {
    println(@lib.explain_program(program))
    return
  }
  let execution = @lib.execute_program(program)
  match command {
    "trace" => println(@lib.execution_trace_text(execution))
    "analyze" => println(stats_text(execution))
    "audit" => {
      let report = @lib.audit_execution(
        execution,
        @lib.MachineProfile::desktop_mill(),
      )
      println(@lib.safety_report_text(report))
      if !report.passed() {
        @sys.exit(1)
      }
    }
    "audit-laser" => {
      let report = @lib.audit_execution(
        execution,
        @lib.MachineProfile::desktop_laser(),
      )
      println(@lib.safety_report_text(report))
      if !report.passed() {
        @sys.exit(1)
      }
    }
    "audit-profile" => {
      if args.length() < 3 {
        println("cli.profile.required: provide G-code and profile files")
        @sys.exit(2)
        return
      }
      let profile_source = match read_source(args[2]) {
        Ok(value) => value
        Err(message) => {
          println("io.profile.failed: " + message)
          @sys.exit(2)
          return
        }
      }
      let profile = match @lib.parse_profile(profile_source) {
        Ok(value) => value
        Err(diagnostics) => {
          for diagnostic in diagnostics {
            println(diagnostic.to_text())
          }
          @sys.exit(2)
          return
        }
      }
      let report = @lib.audit_execution(execution, profile)
      println(@lib.safety_report_text(report))
      if !report.passed() {
        @sys.exit(1)
      }
    }
    "audit-md" => {
      let report = @lib.audit_execution(
        execution,
        @lib.MachineProfile::desktop_mill(),
      )
      println(@lib.safety_report_markdown(report))
      if !report.passed() {
        @sys.exit(1)
      }
    }
    "demo" => {
      println("=== normalize ===")
      println(@lib.normalize_program(program, preserve_comments=true))
      println("=== trace ===")
      println(@lib.execution_trace_text(execution))
      println("=== analyze ===")
      println(stats_text(execution))
      println("=== audit ===")
      println(
        @lib.safety_report_text(
          @lib.audit_execution(execution, @lib.MachineProfile::desktop_mill()),
        ),
      )
    }
    _ => {
      println("cli.command.unknown: " + command)
      println(usage())
      @sys.exit(2)
    }
  }
}
