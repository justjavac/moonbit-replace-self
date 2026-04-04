# justjavac/replace_self

[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-replace-self/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-replace-self)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-replace-self/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-replace-self)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-replace-self/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-replace-self)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-replace-self/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-replace-self)

`justjavac/replace_self` is a native MoonBit package for two closely related
deployment tasks:

- replacing the executable file of the currently running process
- deleting the executable file of the currently running process

It is designed for self-updating desktop applications, single-file CLI tools,
installers, and bootstrap launchers that need a small cross-platform primitive
instead of a full updater framework.

## Features

- Linux: atomically replaces the current executable with `rename(2)` and deletes
  it with `unlink(2)`
- macOS: uses the same Unix strategy as Linux
- Windows: launches a detached helper script that waits for process exit and
  then performs the final move or delete
- Small API surface with typed errors
- Native-only implementation with no JavaScript or WebAssembly fallback
- Integration tests that exercise real executable replacement and deletion

## Installation

Add the dependency to your `moon.mod.json`:

```json
{
  "deps": {
    "justjavac/replace_self": "0.1.0"
  }
}
```

This package only supports the native backend. Set `"preferred-target": "native"`
for the smoothest workflow when building command-line tools or desktop apps.

## API

### `replace_self`

```mbt
pub fn replace_self(new_executable : String) -> Result[Unit, ReplaceSelfError]
```

Replaces the executable file of the currently running process.

Requirements:

- `new_executable` must be a non-empty absolute path
- the replacement file must already exist
- the replacement path must not be the same as the current executable path

Platform semantics:

- Linux and macOS complete the replacement before the function returns
- Windows returns after scheduling the replacement helper; the current process
  should exit soon afterward so the helper can finish the move

### `delete_self`

```mbt
pub fn delete_self() -> Result[Unit, ReplaceSelfError]
```

Deletes the executable file of the currently running process.

Platform semantics:

- Linux and macOS unlink the file immediately
- Windows schedules deletion through the detached helper and expects the current
  process to exit shortly afterward

### `ReplaceSelfError`

```mbt
pub enum ReplaceSelfError {
  EmptyReplacementPath
  RelativeReplacementPath(String)
  ReplacementMatchesCurrentExecutable(String)
  ExecutablePathUnavailable
  UnsupportedPlatform(Platform)
  NativeFailure(action~ : String, message~ : String)
}
```

`NativeFailure` preserves the backend action label together with the best
platform error message the package could extract from the operating system.

## Usage

### Replace the current executable

```mbt
match @replace_self.replace_self("/opt/my-app/my-app.next") {
  Ok(()) => ()
  Err(error) => {
    println("update failed: \{error}")
  }
}
```

### Delete the current executable

```mbt
match @replace_self.delete_self() {
  Ok(()) => ()
  Err(error) => {
    println("self-delete failed: \{error}")
  }
}
```

## Windows notes

Windows does not let a running process overwrite or delete its own `.exe`
directly. This package handles that by writing a temporary helper script into
the system temp directory and launching it with `cmd.exe`.

That helper:

1. waits until the current process exits and the executable is unlocked
2. performs the final delete or move
3. removes the temporary script file

Because of that, `Ok(())` on Windows means "scheduled successfully", not "the
file is already gone or replaced".

## Testing

Run the native test suite:

```powershell
moon test --target native
```

The test suite includes:

- validation tests for path rules and error behavior
- white-box helper tests for path joining and polling
- integration tests that launch a temporary fixture executable and verify that
  `replace_self()` and `delete_self()` affect a real copied binary on disk

## Coverage

Generate a local native coverage report:

```powershell
moon coverage clean
moon coverage analyze -p justjavac/replace_self -- -f cobertura -o coverage.xml
```

GitHub Actions uploads coverage from Linux, macOS, and Windows to Codecov, and
the badges at the top of this README update after Codecov finishes processing
the latest `main` branch reports.

## Implementation notes

- Unix replacement is implemented with a same-path `rename`, which is atomic on
  a single filesystem
- Windows replacement and deletion use an external helper script because the
  running executable remains locked
- All public API docs live in the source files so `moon doc` and Mooncakes show
  the same behavior notes as this README

## License

MIT
