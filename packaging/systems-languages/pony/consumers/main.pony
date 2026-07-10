use "sshfling"

actor Main
  new create(env: Env) =>
    if env.args.size() != 2 then
      env.exitcode(1)
      return
    end
    try
      let expected = env.args(1)?
      if (SSHFling.version() != expected) or
        (SSHFling.runtime_version() != expected)
      then
        env.exitcode(1)
      else
        env.exitcode(SSHFling.run(["--version"]))
      end
    else
      env.exitcode(1)
    end
