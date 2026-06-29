name = "justjavac/replace_self"

version = "0.1.4"

import {
  "moonbitlang/x@0.4.46",
  "justjavac/ffi@0.2.4",
}

readme = "README.mbt.md"

repository = "https://github.com/justjavac/moonbit-replace-self"

license = "MIT"

keywords = [ "self-update", "self-delete", "native" ]

description = "Replace or delete the currently running executable on Linux, macOS, and Windows."

preferred_target = "native"

options(
  source: "src",
)
