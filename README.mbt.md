# replace_self

Cross-platform helpers for replacing or deleting the currently running native
executable.

```mbt nocheck
match @replace_self.replace_self("/tmp/app.next") {
  Ok(()) => ()
  Err(error) => println(error)
}
```

`delete_self()` uses the same platform rules and returns `Result[Unit, ReplaceSelfError]`.
