use "sshfling"

actor Main
  new create(env: Env) =>
    env.exitcode(SSHFling.run(env.args.slice(1)))
