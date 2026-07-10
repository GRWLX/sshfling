require "sshfling"

expected = ARGV.shift? || exit(1)
unless SSHFling::VERSION == expected && SSHFling.runtime_version == expected
  exit(1)
end
exit SSHFling.run(["--version"])
