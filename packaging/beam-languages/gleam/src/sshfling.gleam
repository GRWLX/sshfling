@external(erlang, "sshfling_ffi", "run")
pub fn run(args: List(String)) -> Int

@external(erlang, "sshfling_ffi", "runtime_path")
pub fn runtime_path() -> String

@external(erlang, "sshfling_ffi", "template_directory")
pub fn template_directory() -> String
