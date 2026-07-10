import ballerina/io;
import ballerina/file;
import ballerina/os;

const string packageVersion = "0.0.0";

function installedResourceRoot() returns string {
    string packageRoot = os:getEnv("SSHFLING_PACKAGE_ROOT");
    if packageRoot != "" {
        return packageRoot + "/resources/runtime";
    }
    string ballerinaHome = os:getEnv("BALLERINA_HOME_DIR");
    if ballerinaHome == "" {
        string home = os:getEnv("HOME");
        ballerinaHome = home + "/.ballerina";
    }
    return ballerinaHome + "/repositories/local/bala/grwlx/sshfling/" +
        packageVersion + "/any/resources/runtime";
}

public function runtimePath() returns string {
    string configured = os:getEnv("SSHFLING_RUNTIME");
    if configured != "" {
        return configured;
    }
    return installedResourceRoot() + "/sshfling.py";
}

public function templateDirectory() returns string {
    string configured = os:getEnv("SSHFLING_TEMPLATE_DIR");
    if configured != "" {
        return configured;
    }
    return installedResourceRoot() + "/templates";
}

public type RunResult record {|
    int status;
    string stdout;
    string stderr;
|};

function commandArgs(string[] args) returns string[] {
    return [runtimePath(), ...args];
}

function runtimeAvailable(string path) returns boolean {
    boolean|file:Error result = file:test(path, file:EXISTS);
    return result is boolean && result;
}

public function runAndCapture(string[] args) returns RunResult {
    string python = os:getEnv("SSHFLING_PYTHON");
    if python == "" {
        python = "python3";
    }
    string runtime = runtimePath();
    if !runtimeAvailable(runtime) {
        return {status: 127, stdout: "", stderr: "SSHFling runtime is unavailable"};
    }
    os:Process|os:Error process = os:exec(
        {value: python, arguments: commandArgs(args)},
        SSHFLING_TEMPLATE_DIR = templateDirectory(),
        PYTHONUNBUFFERED = "1"
    );
    if process is os:Error {
        return {status: 127, stdout: "", stderr: process.message()};
    }
    byte[]|os:Error stdoutBytes = process.output();
    byte[]|os:Error stderrBytes = process.output(io:stderr);
    int|os:Error status = process.waitForExit();
    string stdout = stdoutBytes is byte[] ? checkpanic string:fromBytes(stdoutBytes) : "";
    string stderr = stderrBytes is byte[] ? checkpanic string:fromBytes(stderrBytes) : "";
    return {status: status is int ? status : 1, stdout, stderr};
}

public function run(string[] args) returns int {
    string python = os:getEnv("SSHFLING_PYTHON");
    if python == "" {
        python = "python3";
    }
    if !runtimeAvailable(runtimePath()) {
        return 127;
    }
    os:Process|os:Error process = os:exec(
        {value: python, arguments: commandArgs(args)},
        SSHFLING_TEMPLATE_DIR = templateDirectory(),
        PYTHONUNBUFFERED = "1"
    );
    if process is os:Error {
        return 127;
    }
    int|os:Error status = process.waitForExit();
    return status is int ? status : 1;
}
