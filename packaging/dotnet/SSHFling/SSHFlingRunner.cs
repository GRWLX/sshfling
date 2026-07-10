using System.ComponentModel;
using System.Diagnostics;
using System.Reflection;

namespace SSHFling;

/// <summary>Python executable and fixed arguments used to start SSHFling.</summary>
public sealed record PythonCandidate(string FileName, IReadOnlyList<string> PrefixArgs);

/// <summary>Runs the bundled SSHFling Python runtime from .NET applications.</summary>
public static class SSHFlingRunner
{
    private const string ResourcePrefix = "SSHFling.Resources.";

    private static readonly ResourceEntry[] Resources =
    [
        new("sshfling.py", "sshfling.py", true),
        new("templates.env.example", "templates/.env.example", false),
        new("templates.LICENSE", "templates/LICENSE", false),
        new("templates.README.md", "templates/README.md", false),
        new("templates.compose.server.yml", "templates/compose.server.yml", false),
        new("templates.compose.client.yml", "templates/compose.client.yml", false),
        new("templates.native.sshfling-linux-account", "templates/native/sshfling-linux-account", true),
        new("templates.native.sshfling-unix-identity", "templates/native/sshfling-unix-identity", true),
        new("templates.scripts.install-local.sh", "templates/scripts/install-local.sh", true),
        new("templates.scripts.uninstall-local.sh", "templates/scripts/uninstall-local.sh", true),
        new("templates.scripts.create-network.sh", "templates/scripts/create-network.sh", true),
        new("templates.scripts.generate-ssh-key.sh", "templates/scripts/generate-ssh-key.sh", true),
        new("templates.secrets.gitkeep", "templates/secrets/.gitkeep", false),
        new("templates.ssh-client.Dockerfile", "templates/ssh-client/Dockerfile", false),
        new("templates.ssh-client.entrypoint.sh", "templates/ssh-client/entrypoint.sh", true),
        new("templates.ssh-server.Dockerfile", "templates/ssh-server/Dockerfile", false),
        new("templates.ssh-server.entrypoint.sh", "templates/ssh-server/entrypoint.sh", true),
        new("templates.ssh-server.limited-session.sh", "templates/ssh-server/limited-session.sh", true),
        new("templates.ssh-server.sshd_config", "templates/ssh-server/sshd_config", false),
        new("templates.production.sshfling-login-shell", "templates/production/sshfling-login-shell", true),
        new("templates.production.sshfling-session", "templates/production/sshfling-session", true),
        new("templates.systemd.sshflingd.service", "templates/systemd/sshflingd.service", false),
        new("templates.systemd.sshfling-prune.service", "templates/systemd/sshfling-prune.service", false),
        new("templates.systemd.sshfling-prune.timer", "templates/systemd/sshfling-prune.timer", false),
        new("templates.systemd.sshflingd.env.example", "templates/systemd/sshflingd.env.example", false),
    ];

    /// <summary>Gets the package assembly version.</summary>
    public static string Version => typeof(SSHFlingRunner).Assembly
        .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
        .InformationalVersion.Split('+', 2)[0] ?? "0.0.0";

    /// <summary>Returns Python launchers in platform preference order.</summary>
    public static IReadOnlyList<PythonCandidate> PythonCandidates()
    {
        var candidates = new List<PythonCandidate>();
        var configuredPython = Environment.GetEnvironmentVariable("SSHFLING_PYTHON");
        if (!string.IsNullOrWhiteSpace(configuredPython))
        {
            candidates.Add(new PythonCandidate(configuredPython.Trim(), []));
        }

        if (OperatingSystem.IsWindows())
        {
            candidates.Add(new PythonCandidate("py", ["-3"]));
            candidates.Add(new PythonCandidate("python", []));
            candidates.Add(new PythonCandidate("python3", []));
        }
        else
        {
            candidates.Add(new PythonCandidate("python3", []));
            candidates.Add(new PythonCandidate("python", []));
        }
        return candidates;
    }

    /// <summary>Runs SSHFling synchronously with inherited standard streams.</summary>
    public static int Run(IEnumerable<string> arguments) => RunAsync(arguments).GetAwaiter().GetResult();

    /// <summary>Runs SSHFling asynchronously with inherited standard streams.</summary>
    public static async Task<int> RunAsync(
        IEnumerable<string> arguments,
        CancellationToken cancellationToken = default)
    {
        var runtimeDirectory = Path.Combine(Path.GetTempPath(), $"sshfling-dotnet-{Guid.NewGuid():N}");
        Directory.CreateDirectory(runtimeDirectory);
        try
        {
            await ExtractRuntimeAsync(runtimeDirectory, cancellationToken);
            var scriptPath = Path.Combine(runtimeDirectory, "sshfling.py");
            var templateDir = Path.Combine(runtimeDirectory, "templates");

            foreach (var candidate in PythonCandidates())
            {
                try
                {
                    using var process = StartPython(candidate, scriptPath, templateDir, arguments);
                    try
                    {
                        await process.WaitForExitAsync(cancellationToken);
                    }
                    catch (OperationCanceledException)
                    {
                        if (!process.HasExited)
                        {
                            process.Kill(entireProcessTree: true);
                        }
                        throw;
                    }
                    return process.ExitCode;
                }
                catch (Win32Exception)
                {
                    // Try the next conventional Python launcher name.
                }
                catch (FileNotFoundException)
                {
                    // Try the next conventional Python launcher name.
                }
            }

            Console.Error.WriteLine(
                "SSHFling requires Python 3 on PATH, or set SSHFLING_PYTHON to a Python 3 executable.");
            return 127;
        }
        finally
        {
            try
            {
                Directory.Delete(runtimeDirectory, recursive: true);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    private static Process StartPython(
        PythonCandidate candidate,
        string scriptPath,
        string templateDir,
        IEnumerable<string> arguments)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = candidate.FileName,
            UseShellExecute = false,
        };
        foreach (var prefixArgument in candidate.PrefixArgs)
        {
            startInfo.ArgumentList.Add(prefixArgument);
        }
        startInfo.ArgumentList.Add(scriptPath);
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        startInfo.Environment["SSHFLING_TEMPLATE_DIR"] = templateDir;
        startInfo.Environment["PYTHONUNBUFFERED"] = "1";
        return Process.Start(startInfo) ?? throw new InvalidOperationException("Python process did not start.");
    }

    private static async Task ExtractRuntimeAsync(string runtimeDirectory, CancellationToken cancellationToken)
    {
        var assembly = typeof(SSHFlingRunner).Assembly;
        var root = Path.GetFullPath(runtimeDirectory) + Path.DirectorySeparatorChar;
        foreach (var entry in Resources)
        {
            var target = Path.GetFullPath(Path.Combine(runtimeDirectory, entry.RelativePath));
            if (!target.StartsWith(root, StringComparison.Ordinal))
            {
                throw new InvalidDataException($"Bundled resource escapes runtime directory: {entry.RelativePath}");
            }
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            await using var source = assembly.GetManifestResourceStream(ResourcePrefix + entry.ResourceName)
                ?? throw new InvalidDataException($"Missing bundled resource: {entry.ResourceName}");
            await using var destination = File.Create(target);
            await source.CopyToAsync(destination, cancellationToken);
            await destination.FlushAsync(cancellationToken);

            if (entry.Executable && !OperatingSystem.IsWindows())
            {
                File.SetUnixFileMode(
                    target,
                    UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute |
                    UnixFileMode.GroupRead | UnixFileMode.GroupExecute |
                    UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
            }
        }
    }

    private sealed record ResourceEntry(string ResourceName, string RelativePath, bool Executable);
}
