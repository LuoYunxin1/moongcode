///|
pub struct Word {
  letter : Char
  value : Double
  raw : String
  column : Int
} derive(Eq, @debug.Debug)

///|
pub fn Word::new(
  letter : Char,
  value : Double,
  raw : String,
  column : Int,
) -> Word {
  { letter, value, raw, column }
}

///|
pub fn Word::letter(self : Word) -> Char {
  self.letter
}

///|
pub fn Word::value(self : Word) -> Double {
  self.value
}

///|
pub fn Word::raw(self : Word) -> String {
  self.raw
}

///|
pub fn Word::column(self : Word) -> Int {
  self.column
}

///|
pub struct Block {
  source_line : Int
  sequence : Int?
  words : Array[Word]
  comment : String?
  checksum : Int?
  raw : String
} derive(Eq, @debug.Debug)

///|
pub fn Block::new(
  source_line : Int,
  sequence : Int?,
  words : Array[Word],
  comment : String?,
  checksum : Int?,
  raw : String,
) -> Block {
  { source_line, sequence, words: words.copy(), comment, checksum, raw }
}

///|
pub fn Block::source_line(self : Block) -> Int {
  self.source_line
}

///|
pub fn Block::sequence(self : Block) -> Int? {
  self.sequence
}

///|
pub fn Block::words(self : Block) -> Array[Word] {
  self.words.copy()
}

///|
pub fn Block::comment(self : Block) -> String? {
  self.comment
}

///|
pub fn Block::checksum(self : Block) -> Int? {
  self.checksum
}

///|
pub fn Block::raw(self : Block) -> String {
  self.raw
}

///|
pub fn Block::is_empty(self : Block) -> Bool {
  self.words.is_empty()
}

///|
pub fn Block::values(self : Block, letter : Char) -> Array[Double] {
  self.words.filter_map(fn(word) {
    if word.letter() == letter {
      Some(word.value())
    } else {
      None
    }
  })
}

///|
pub fn Block::first_value(self : Block, letter : Char) -> Double? {
  for word in self.words {
    if word.letter() == letter {
      return Some(word.value())
    }
  }
  None
}

///|
pub struct Program {
  blocks : Array[Block]
  diagnostics : Array[Diagnostic]
} derive(Eq, @debug.Debug)

///|
pub fn Program::new(
  blocks : Array[Block],
  diagnostics : Array[Diagnostic],
) -> Program {
  { blocks: blocks.copy(), diagnostics: diagnostics.copy() }
}

///|
pub fn Program::blocks(self : Program) -> Array[Block] {
  self.blocks.copy()
}

///|
pub fn Program::diagnostics(self : Program) -> Array[Diagnostic] {
  self.diagnostics.copy()
}

///|
pub fn Program::is_valid(self : Program) -> Bool {
  !diagnostics_have_errors(self.diagnostics)
}

///|
pub(all) enum Units {
  Millimeters
  Inches
} derive(Eq, @debug.Debug)

///|
pub fn Units::to_text(self : Units) -> String {
  match self {
    Millimeters => "mm"
    Inches => "inch"
  }
}

///|
pub fn Units::scale_to_mm(self : Units) -> Double {
  match self {
    Millimeters => 1.0
    Inches => 25.4
  }
}

///|
pub(all) enum DistanceMode {
  Absolute
  Incremental
} derive(Eq, @debug.Debug)

///|
pub fn DistanceMode::to_text(self : DistanceMode) -> String {
  match self {
    Absolute => "absolute"
    Incremental => "incremental"
  }
}

///|
pub(all) enum ArcDistanceMode {
  ArcIncremental
  ArcAbsolute
} derive(Eq, @debug.Debug)

///|
pub(all) enum Plane {
  XY
  ZX
  YZ
} derive(Eq, @debug.Debug)

///|
pub fn Plane::to_text(self : Plane) -> String {
  match self {
    XY => "XY"
    ZX => "ZX"
    YZ => "YZ"
  }
}

///|
pub(all) enum MotionMode {
  NoMotion
  RapidMotion
  LinearMotion
  ClockwiseArc
  CounterClockwiseArc
} derive(Eq, @debug.Debug)

///|
pub fn MotionMode::to_text(self : MotionMode) -> String {
  match self {
    NoMotion => "none"
    RapidMotion => "G0"
    LinearMotion => "G1"
    ClockwiseArc => "G2"
    CounterClockwiseArc => "G3"
  }
}

///|
pub(all) enum SpindleMode {
  SpindleOff
  SpindleClockwise
  SpindleCounterClockwise
} derive(Eq, @debug.Debug)

///|
pub fn SpindleMode::to_text(self : SpindleMode) -> String {
  match self {
    SpindleOff => "off"
    SpindleClockwise => "clockwise"
    SpindleCounterClockwise => "counter-clockwise"
  }
}

///|
pub(all) enum ProgramStatus {
  Ready
  Paused
  Ended
} derive(Eq, @debug.Debug)

///|
pub struct Point3 {
  x : Double
  y : Double
  z : Double
} derive(Eq, @debug.Debug)

///|
pub fn Point3::new(x : Double, y : Double, z : Double) -> Point3 {
  { x, y, z }
}

///|
pub fn Point3::origin() -> Point3 {
  { x: 0.0, y: 0.0, z: 0.0 }
}

///|
pub fn Point3::x(self : Point3) -> Double {
  self.x
}

///|
pub fn Point3::y(self : Point3) -> Double {
  self.y
}

///|
pub fn Point3::z(self : Point3) -> Double {
  self.z
}

///|
pub fn Point3::with_x(self : Point3, x : Double) -> Point3 {
  { x, y: self.y, z: self.z }
}

///|
pub fn Point3::with_y(self : Point3, y : Double) -> Point3 {
  { x: self.x, y, z: self.z }
}

///|
pub fn Point3::with_z(self : Point3, z : Double) -> Point3 {
  { x: self.x, y: self.y, z }
}

///|
pub fn Point3::to_text(self : Point3) -> String {
  "(" +
  self.x.to_string() +
  "," +
  self.y.to_string() +
  "," +
  self.z.to_string() +
  ")"
}

///|
pub struct MachineState {
  position : Point3
  units : Units
  distance_mode : DistanceMode
  arc_distance_mode : ArcDistanceMode
  plane : Plane
  motion : MotionMode
  feed_mm_min : Double
  spindle_rpm : Double
  spindle : SpindleMode
  tool : Int
  status : ProgramStatus
  elapsed_seconds : Double
} derive(Eq, @debug.Debug)

///|
pub fn MachineState::initial() -> MachineState {
  {
    position: Point3::origin(),
    units: Millimeters,
    distance_mode: Absolute,
    arc_distance_mode: ArcIncremental,
    plane: XY,
    motion: NoMotion,
    feed_mm_min: 0.0,
    spindle_rpm: 0.0,
    spindle: SpindleOff,
    tool: 0,
    status: Ready,
    elapsed_seconds: 0.0,
  }
}

///|
pub fn MachineState::position(self : MachineState) -> Point3 {
  self.position
}

///|
pub fn MachineState::units(self : MachineState) -> Units {
  self.units
}

///|
pub fn MachineState::distance_mode(self : MachineState) -> DistanceMode {
  self.distance_mode
}

///|
pub fn MachineState::arc_distance_mode(self : MachineState) -> ArcDistanceMode {
  self.arc_distance_mode
}

///|
pub fn MachineState::plane(self : MachineState) -> Plane {
  self.plane
}

///|
pub fn MachineState::motion(self : MachineState) -> MotionMode {
  self.motion
}

///|
pub fn MachineState::feed_mm_min(self : MachineState) -> Double {
  self.feed_mm_min
}

///|
pub fn MachineState::spindle_rpm(self : MachineState) -> Double {
  self.spindle_rpm
}

///|
pub fn MachineState::spindle(self : MachineState) -> SpindleMode {
  self.spindle
}

///|
pub fn MachineState::tool(self : MachineState) -> Int {
  self.tool
}

///|
pub fn MachineState::status(self : MachineState) -> ProgramStatus {
  self.status
}

///|
pub fn MachineState::elapsed_seconds(self : MachineState) -> Double {
  self.elapsed_seconds
}

///|
pub fn MachineState::replace(
  self : MachineState,
  position? : Point3 = self.position,
  units? : Units = self.units,
  distance_mode? : DistanceMode = self.distance_mode,
  arc_distance_mode? : ArcDistanceMode = self.arc_distance_mode,
  plane? : Plane = self.plane,
  motion? : MotionMode = self.motion,
  feed_mm_min? : Double = self.feed_mm_min,
  spindle_rpm? : Double = self.spindle_rpm,
  spindle? : SpindleMode = self.spindle,
  tool? : Int = self.tool,
  status? : ProgramStatus = self.status,
  elapsed_seconds? : Double = self.elapsed_seconds,
) -> MachineState {
  {
    position,
    units,
    distance_mode,
    arc_distance_mode,
    plane,
    motion,
    feed_mm_min,
    spindle_rpm,
    spindle,
    tool,
    status,
    elapsed_seconds,
  }
}

///|
pub(all) enum SegmentKind {
  RapidSegment
  LinearSegment
  ClockwiseArcSegment
  CounterClockwiseArcSegment
  DwellSegment
} derive(Eq, @debug.Debug)

///|
pub fn SegmentKind::to_text(self : SegmentKind) -> String {
  match self {
    RapidSegment => "rapid"
    LinearSegment => "linear"
    ClockwiseArcSegment => "arc-cw"
    CounterClockwiseArcSegment => "arc-ccw"
    DwellSegment => "dwell"
  }
}

///|
pub struct Segment {
  kind : SegmentKind
  source_line : Int
  start : Point3
  end : Point3
  center : Point3?
  radius_mm : Double
  sweep_radians : Double
  length_mm : Double
  duration_seconds : Double
  feed_mm_min : Double
} derive(Eq, @debug.Debug)

///|
pub fn Segment::new(
  kind : SegmentKind,
  source_line : Int,
  start : Point3,
  end : Point3,
  center : Point3?,
  radius_mm : Double,
  sweep_radians : Double,
  length_mm : Double,
  duration_seconds : Double,
  feed_mm_min : Double,
) -> Segment {
  {
    kind,
    source_line,
    start,
    end,
    center,
    radius_mm,
    sweep_radians,
    length_mm,
    duration_seconds,
    feed_mm_min,
  }
}

///|
pub fn Segment::kind(self : Segment) -> SegmentKind {
  self.kind
}

///|
pub fn Segment::source_line(self : Segment) -> Int {
  self.source_line
}

///|
pub fn Segment::start(self : Segment) -> Point3 {
  self.start
}

///|
pub fn Segment::end(self : Segment) -> Point3 {
  self.end
}

///|
pub fn Segment::center(self : Segment) -> Point3? {
  self.center
}

///|
pub fn Segment::radius_mm(self : Segment) -> Double {
  self.radius_mm
}

///|
pub fn Segment::sweep_radians(self : Segment) -> Double {
  self.sweep_radians
}

///|
pub fn Segment::length_mm(self : Segment) -> Double {
  self.length_mm
}

///|
pub fn Segment::duration_seconds(self : Segment) -> Double {
  self.duration_seconds
}

///|
pub fn Segment::feed_mm_min(self : Segment) -> Double {
  self.feed_mm_min
}

///|
pub struct TraceStep {
  source_line : Int
  block : Block
  before : MachineState
  after : MachineState
  segments : Array[Segment]
  diagnostics : Array[Diagnostic]
} derive(Eq, @debug.Debug)

///|
pub fn TraceStep::new(
  source_line : Int,
  block : Block,
  before : MachineState,
  after : MachineState,
  segments : Array[Segment],
  diagnostics : Array[Diagnostic],
) -> TraceStep {
  {
    source_line,
    block,
    before,
    after,
    segments: segments.copy(),
    diagnostics: diagnostics.copy(),
  }
}

///|
pub fn TraceStep::source_line(self : TraceStep) -> Int {
  self.source_line
}

///|
pub fn TraceStep::block(self : TraceStep) -> Block {
  self.block
}

///|
pub fn TraceStep::before(self : TraceStep) -> MachineState {
  self.before
}

///|
pub fn TraceStep::after(self : TraceStep) -> MachineState {
  self.after
}

///|
pub fn TraceStep::segments(self : TraceStep) -> Array[Segment] {
  self.segments.copy()
}

///|
pub fn TraceStep::diagnostics(self : TraceStep) -> Array[Diagnostic] {
  self.diagnostics.copy()
}

///|
pub struct Execution {
  program : Program
  steps : Array[TraceStep]
  segments : Array[Segment]
  diagnostics : Array[Diagnostic]
  final_state : MachineState
} derive(Eq, @debug.Debug)

///|
pub fn Execution::new(
  program : Program,
  steps : Array[TraceStep],
  segments : Array[Segment],
  diagnostics : Array[Diagnostic],
  final_state : MachineState,
) -> Execution {
  {
    program,
    steps: steps.copy(),
    segments: segments.copy(),
    diagnostics: diagnostics.copy(),
    final_state,
  }
}

///|
pub fn Execution::program(self : Execution) -> Program {
  self.program
}

///|
pub fn Execution::steps(self : Execution) -> Array[TraceStep] {
  self.steps.copy()
}

///|
pub fn Execution::segments(self : Execution) -> Array[Segment] {
  self.segments.copy()
}

///|
pub fn Execution::diagnostics(self : Execution) -> Array[Diagnostic] {
  self.diagnostics.copy()
}

///|
pub fn Execution::final_state(self : Execution) -> MachineState {
  self.final_state
}

///|
pub fn Execution::is_valid(self : Execution) -> Bool {
  !diagnostics_have_errors(self.diagnostics)
}
