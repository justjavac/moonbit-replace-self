///|
/// Supported host platforms for self-replacement operations.
pub enum Platform {
  Windows
  MacOS
  Linux
  Unsupported
} derive(Eq, Debug)

///|
pub impl Show for Platform with fn to_string(self) {
  match self {
    Windows => "Windows"
    MacOS => "MacOS"
    Linux => "Linux"
    Unsupported => "Unsupported"
  }
}

///|
/// Maps a native platform code to the public `Platform` enum.
fn platform_from_code(code : Int) -> Platform {
  match code {
    1 => Windows
    2 => MacOS
    3 => Linux
    _ => Unsupported
  }
}

///|
/// Returns the current host platform.
fn current_platform() -> Platform {
  platform_from_code(platform_code_ffi())
}
