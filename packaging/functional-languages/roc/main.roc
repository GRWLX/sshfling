app [main!] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br",
    sshfling: "package.roc",
}

import cli.Arg exposing [Arg]
import sshfling.SSHFling

main! : List Arg => Result {} _
main! = |raw_args|
    status = SSHFling.run!(List.map(raw_args, Arg.display))?
    if status == 0 then
        Ok({})
    else
        Err(SSHFlingExited(status))
