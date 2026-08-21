///|
pub(all) enum Severity {
  Info
  Warning
  Error
} derive(Eq, @debug.Debug)

///|
pub fn Severity::to_text(self : Severity) -> String {
  match self {
    Info => "info"
    Warning => "warning"
    Error => "error"
  }
}

///|
pub struct Diagnostic {
  severity : Severity
  code : String
  line : Int
  column : Int
  message : String
} derive(Eq, @debug.Debug)

///|
pub fn Diagnostic::new(
  severity : Severity,
  code : String,
  line : Int,
  column : Int,
  message : String,
) -> Diagnostic {
  { severity, code, line, column, message }
}

///|
pub fn Diagnostic::error(
  code : String,
  line : Int,
  column : Int,
  message : String,
) -> Diagnostic {
  Diagnostic::new(Error, code, line, column, message)
}

///|
pub fn Diagnostic::warning(
  code : String,
  line : Int,
  column : Int,
  message : String,
) -> Diagnostic {
  Diagnostic::new(Warning, code, line, column, message)
}

///|
pub fn Diagnostic::info(
  code : String,
  line : Int,
  column : Int,
  message : String,
) -> Diagnostic {
  Diagnostic::new(Info, code, line, column, message)
}

///|
pub fn Diagnostic::severity(self : Diagnostic) -> Severity {
  self.severity
}

///|
pub fn Diagnostic::code(self : Diagnostic) -> String {
  self.code
}

///|
pub fn Diagnostic::line(self : Diagnostic) -> Int {
  self.line
}

///|
pub fn Diagnostic::column(self : Diagnostic) -> Int {
  self.column
}

///|
pub fn Diagnostic::message(self : Diagnostic) -> String {
  self.message
}

///|
pub fn Diagnostic::to_text(self : Diagnostic) -> String {
  self.severity.to_text() +
  "[" +
  self.code +
  "] line " +
  self.line.to_string() +
  ":" +
  self.column.to_string() +
  " " +
  self.message
}

///|
pub fn diagnostics_have_errors(values : Array[Diagnostic]) -> Bool {
  values.any(fn(item) { item.severity() == Error })
}

///|
/// Return diagnostics with a selected severity while preserving source order.
pub fn diagnostics_by_severity(
  values : Array[Diagnostic],
  severity : Severity,
) -> Array[Diagnostic] {
  values.filter(fn(item) { item.severity() == severity })
}

///|
/// Count diagnostics with a selected stable code.
pub fn diagnostics_count_code(values : Array[Diagnostic], code : String) -> Int {
  let mut count = 0
  for item in values {
    if item.code() == code {
      count += 1
    }
  }
  count
}

///|
/// Summarize diagnostic severities for command and editor integrations.
pub fn diagnostics_summary(values : Array[Diagnostic]) -> String {
  let errors = diagnostics_by_severity(values, Error).length()
  let warnings = diagnostics_by_severity(values, Warning).length()
  let infos = diagnostics_by_severity(values, Info).length()
  "errors=" +
  errors.to_string() +
  " warnings=" +
  warnings.to_string() +
  " info=" +
  infos.to_string()
}
