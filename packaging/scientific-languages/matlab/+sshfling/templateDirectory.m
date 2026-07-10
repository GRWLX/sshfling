function path = templateDirectory()
%TEMPLATEDIRECTORY Return the bundled SSHFling template directory path.
    root = configuredOr('SSHFLING_PACKAGE_ROOT', packageRoot());
    path = configuredOr('SSHFLING_TEMPLATE_DIR', fullfile(root, 'runtime', 'templates'));
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
