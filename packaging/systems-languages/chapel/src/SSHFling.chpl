module SSHFling {
  require "sshfling_launcher.h";

  use CTypes;

  param version = "0.0.0";

  extern proc sshfling_launcher_version(): c_ptrConst(c_char);
  extern proc sshfling_launcher_run_nul(
    count: c_size_t,
    arguments: c_ptrConst(c_char)
  ): c_int;

  proc runtimeVersion(): string {
    return try! string.createCopyingBuffer(sshfling_launcher_version());
  }

  proc run(arguments: [] string): int {
    if arguments.size == 0 then
      return sshfling_launcher_run_nul(0:c_size_t, nil):int;
    var packed = "";
    for argument in arguments do
      packed += argument + "\x00";
    return sshfling_launcher_run_nul(
      arguments.size:c_size_t,
      packed.c_str()
    ):int;
  }
}
