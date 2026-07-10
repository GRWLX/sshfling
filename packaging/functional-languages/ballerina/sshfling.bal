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

public function run(string[] args) returns int {
    string python = os:getEnv("SSHFLING_PYTHON");
    if python == "" {
        python = "python3";
    }
    string[] commandArgs = [runtimePath(), ...args];
    os:Process|os:Error process = os:exec(
        {value: python, arguments: commandArgs},
        SSHFLING_TEMPLATE_DIR = templateDirectory(),
        PYTHONUNBUFFERED = "1"
    );
    if process is os:Error {
        return 127;
    }
    int|os:Error status = process.waitForExit();
    return status is int ? status : 1;
}
