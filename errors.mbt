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
} derive(Eq, Show)
