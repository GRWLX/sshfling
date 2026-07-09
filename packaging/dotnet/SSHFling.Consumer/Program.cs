using SSHFling;

if (args.Length < 1)
{
    Console.Error.WriteLine("expected package version argument");
    return 2;
}

var expectedVersion = args[0];
if (!string.Equals(SSHFlingRunner.Version, expectedVersion, StringComparison.Ordinal))
{
    Console.Error.WriteLine($"library version mismatch: {SSHFlingRunner.Version} != {expectedVersion}");
    return 1;
}

return SSHFlingRunner.Run(args.Skip(1));
