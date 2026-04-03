///|
test "replace_self rejects empty public paths" {
  match @replace_self.replace_self("   ") {
    Err(error) => assert_eq(error.to_string(), "EmptyReplacementPath")
    Ok(_) => panic()
  }
}

///|
test "replace_self rejects relative public paths" {
  match @replace_self.replace_self("./next") {
    Err(error) =>
      assert_eq(error.to_string(), "RelativeReplacementPath(\"./next\")")
    Ok(_) => panic()
  }
}
