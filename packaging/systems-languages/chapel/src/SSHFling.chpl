module SSHFling {
  use CTypes;

  param version = "0.0.0";

  extern proc sshfling_launcher_version(): c_ptrConst(c_char);
  extern proc sshfling_launcher_run(
    count: c_size_t,
    arguments: c_ptr(c_ptrConst(c_char))
  ): c_int;

  proc runtimeVersion(): string {
    return string.createCopyingBuffer(sshfling_launcher_version());
  }

  proc run(arguments: [] string): int {
    var pointers: [arguments.domain] c_ptrConst(c_char);
    for index in arguments.domain do
      pointers[index] = arguments[index].c_str();

    if arguments.size == 0 then
      return sshfling_launcher_run(0:c_size_t, nil):int;
    return sshfling_launcher_run(
      arguments.size:c_size_t,
      c_ptrTo(pointers[arguments.domain.low])
    ):int;
  }
}
