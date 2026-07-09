open System
open SSHFling

[<EntryPoint>]
let main args =
    if args.Length < 1 then
        Console.Error.WriteLine("expected package version argument")
        2
    else
        let expectedVersion = args[0]
        if not (String.Equals(SSHFlingRunner.Version, expectedVersion, StringComparison.Ordinal)) then
            Console.Error.WriteLine($"library version mismatch: {SSHFlingRunner.Version} != {expectedVersion}")
            1
        else
            SSHFlingRunner.Run(args |> Array.skip 1)
