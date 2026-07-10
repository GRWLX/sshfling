use SSHFling;

proc main(arguments: [] string): int {
  if arguments.size != 2 || SSHFling.version != arguments[1] ||
      SSHFling.runtimeVersion() != arguments[1] then
    return 1;
  return SSHFling.run(["--version"]);
}
