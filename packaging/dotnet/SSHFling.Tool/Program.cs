using System.ComponentModel;
using System.Diagnostics;

var toolBaseDir = AppContext.BaseDirectory;
var scriptPath = Path.Combine(toolBaseDir, "sshfling.py");
var templateDir = Path.Combine(toolBaseDir, "templates");

if (!File.Exists(scriptPath))
{
    Console.Error.WriteLine($"SSHFling.Tool package is missing bundled CLI script: {scriptPath}");
    return 127;
}

if (!Directory.Exists(templateDir))
{
    Console.Error.WriteLine($"SSHFling.Tool package is missing bundled templates: {templateDir}");
    return 127;
}

NormalizeTemplateModes(templateDir);

foreach (var candidate in PythonCandidates())
{
    try
    {
        using var process = StartPython(candidate, scriptPath, templateDir, args);
        process.WaitForExit();
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

Console.Error.WriteLine("SSHFling.Tool requires Python 3 on PATH, or set SSHFLING_PYTHON to a Python 3 executable.");
return 127;

static Process StartPython(PythonCandidate candidate, string scriptPath, string templateDir, string[] args)
{
    var startInfo = new ProcessStartInfo
    {
        FileName = candidate.FileName,
        UseShellExecute = false,
    };
    foreach (var prefixArg in candidate.PrefixArgs)
    {
        startInfo.ArgumentList.Add(prefixArg);
    }
    startInfo.ArgumentList.Add(scriptPath);
    foreach (var arg in args)
    {
        startInfo.ArgumentList.Add(arg);
    }
    if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SSHFLING_TEMPLATE_DIR")))
    {
        startInfo.Environment["SSHFLING_TEMPLATE_DIR"] = templateDir;
    }
    if (!startInfo.Environment.ContainsKey("PYTHONUNBUFFERED"))
    {
        startInfo.Environment["PYTHONUNBUFFERED"] = "1";
    }
    return Process.Start(startInfo) ?? throw new InvalidOperationException("Python process did not start.");
}

static IEnumerable<PythonCandidate> PythonCandidates()
{
    var configuredPython = Environment.GetEnvironmentVariable("SSHFLING_PYTHON");
    if (!string.IsNullOrWhiteSpace(configuredPython))
    {
        yield return new PythonCandidate(configuredPython.Trim(), []);
    }

    if (OperatingSystem.IsWindows())
    {
        yield return new PythonCandidate("py", ["-3"]);
        yield return new PythonCandidate("python", []);
        yield return new PythonCandidate("python3", []);
    }
    else
    {
        yield return new PythonCandidate("python3", []);
        yield return new PythonCandidate("python", []);
    }
}

static void NormalizeTemplateModes(string templateDir)
{
    try
    {
        var secretsDir = Path.Combine(templateDir, "secrets");
        Directory.CreateDirectory(secretsDir);
        var gitkeep = Path.Combine(secretsDir, ".gitkeep");
        if (!File.Exists(gitkeep))
        {
            File.WriteAllText(gitkeep, string.Empty);
        }
    }
    catch (IOException)
    {
    }
    catch (UnauthorizedAccessException)
    {
    }

    if (OperatingSystem.IsWindows())
    {
        return;
    }

    var executableTemplates = new[]
    {
        "production/sshfling-session",
        "scripts/create-network.sh",
        "scripts/generate-ssh-key.sh",
        "scripts/install-local.sh",
        "scripts/uninstall-local.sh",
        "ssh-client/entrypoint.sh",
        "ssh-server/entrypoint.sh",
        "ssh-server/limited-session.sh",
    };

    var mode = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute |
        UnixFileMode.GroupRead | UnixFileMode.GroupExecute |
        UnixFileMode.OtherRead | UnixFileMode.OtherExecute;

    foreach (var relativePath in executableTemplates)
    {
        var path = Path.Combine(templateDir, relativePath);
        if (!File.Exists(path))
        {
            continue;
        }

        try
        {
            File.SetUnixFileMode(path, mode);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
        catch (PlatformNotSupportedException)
        {
        }
    }
}

internal sealed record PythonCandidate(string FileName, string[] PrefixArgs);
