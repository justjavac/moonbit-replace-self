///|
/// Supported host platforms for self-replacement operations.
pub enum Platform {
  Windows
  MacOS
  Linux
  Unsupported
} derive(Eq, Show)

///|
/// Maps a native platform code to the public `Platform` enum.
fn platform_from_code(code : Int) -> Platform {
  match code {
    1 => Platform::Windows
    2 => Platform::MacOS
    3 => Platform::Linux
    _ => Platform::Unsupported
  }
}

///|
/// Returns the current host platform.
fn current_platform() -> Platform {
  platform_from_code(platform_code_ffi())
}
