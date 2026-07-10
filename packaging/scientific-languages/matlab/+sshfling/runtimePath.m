function path = runtimePath()
%RUNTIMEPATH Return the bundled SSHFling Python runtime path.
    root = configuredOr('SSHFLING_PACKAGE_ROOT', packageRoot());
    path = configuredOr('SSHFLING_RUNTIME', fullfile(root, 'runtime', 'sshfling.py'));
end

function value = configuredOr(name, fallback)
    value = getenv(name);
    if isempty(value)
        value = fallback;
    end
end

function root = packageRoot()
    current = mfilename('fullpath');
    root = fileparts(fileparts(current));
end
