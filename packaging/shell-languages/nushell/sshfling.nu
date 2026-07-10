export def sshfling-version [] {
    "0.0.0"
}

export def sshfling-package-root [] {
    if ("SSHFLING_PACKAGE_ROOT" in $env) and (($env.SSHFLING_PACKAGE_ROOT | str length) > 0) {
        $env.SSHFLING_PACKAGE_ROOT
    } else {
        error make {msg: "sshfling: set SSHFLING_PACKAGE_ROOT before using the Nushell module"}
    }
}

export def sshfling-runtime-path [] {
    if ("SSHFLING_RUNTIME" in $env) and (($env.SSHFLING_RUNTIME | str length) > 0) {
        $env.SSHFLING_RUNTIME
    } else {
        sshfling-package-root | path join libexec sshfling sshfling.py
    }
}

export def sshfling-template-dir [] {
    if ("SSHFLING_TEMPLATE_DIR" in $env) and (($env.SSHFLING_TEMPLATE_DIR | str length) > 0) {
        $env.SSHFLING_TEMPLATE_DIR
    } else {
        sshfling-package-root | path join share sshfling templates
    }
}

export def --wrapped sshfling-run [...arguments: string] {
    let candidates = if ("SSHFLING_PYTHON" in $env) and (($env.SSHFLING_PYTHON | str length) > 0) {
        [$env.SSHFLING_PYTHON]
    } else {
        [python3 python]
    }
    let python = ($candidates | where {|candidate| (which $candidate | is-not-empty)} | first)
    let templates = (sshfling-template-dir)
    let runtime = (sshfling-runtime-path)
    with-env {
        PYTHONUNBUFFERED: ($env.PYTHONUNBUFFERED? | default "1"),
        SSHFLING_TEMPLATE_DIR: $templates
    } {
        run-external $python $runtime ...$arguments
    }
}
