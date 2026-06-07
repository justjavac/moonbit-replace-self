///|
/// Errors returned by `replace_self` package operations.
///
/// Validation failures report incorrect inputs supplied by the caller.
/// Discovery failures report missing runtime information such as the current
/// executable path. `NativeFailure` wraps an operating-system specific failure
/// message produced by the native shim.
pub enum ReplaceSelfError {
  EmptyReplacementPath
  RelativeReplacementPath(String)
  ReplacementMatchesCurrentExecutable(String)
  ExecutablePathUnavailable
  UnsupportedPlatform(Platform)
  NativeFailure(action~ : String, message~ : String)
} derive(Eq, Debug)

///|
pub impl Show for ReplaceSelfError with fn to_string(self) {
  match self {
    EmptyReplacementPath => "EmptyReplacementPath"
    RelativeReplacementPath(path) => "RelativeReplacementPath(\{path})"
    ReplacementMatchesCurrentExecutable(path) =>
      "ReplacementMatchesCurrentExecutable(\{path})"
    ExecutablePathUnavailable => "ExecutablePathUnavailable"
    UnsupportedPlatform(platform) => "UnsupportedPlatform(\{platform})"
    NativeFailure(action~, message~) =>
      "NativeFailure(action=\{action}, message=\{message})"
  }
}
