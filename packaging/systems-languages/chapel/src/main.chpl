use SSHFling;

proc main(arguments: [] string): int {
  return SSHFling.run(arguments[1..]);
}
