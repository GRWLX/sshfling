% SPDX-License-Identifier: MIT
function status = run(arguments, executable)
%RUN Start an installed SSHFling executable and return its exit status.
%   STATUS = SSHFLING.RUN(ARGUMENTS) passes the string/cell array ARGUMENTS
%   to SSHFLING_EXECUTABLE, or to "sshfling" when that environment variable
%   is empty. Standard streams are inherited from MATLAB.
%
%   STATUS = SSHFLING.RUN(ARGUMENTS, EXECUTABLE) selects an executable
%   explicitly. This form exists for testing and controlled embeddings.
%
%   This candidate uses Java ProcessBuilder instead of MATLAB SYSTEM so each
%   argument remains a distinct process argument and is not parsed by a shell.

    if nargin < 1
        arguments = {};
    end
    if nargin < 2 || strlength(string(executable)) == 0
        executable = getenv('SSHFLING_EXECUTABLE');
        if isempty(executable)
            executable = 'sshfling';
        end
    end

    if ~usejava('jvm')
        error('sshfling:JavaRequired', ...
            'SSHFling requires a MATLAB session with a configured JVM.');
    end

    executable = normalizeScalar(executable, 'executable');
    arguments = normalizeArguments(arguments);

    command = java.util.ArrayList();
    command.add(java.lang.String(executable));
    for index = 1:numel(arguments)
        command.add(java.lang.String(arguments{index}));
    end

    builder = java.lang.ProcessBuilder(command);
    builder.inheritIO();
    try
        process = builder.start();
        status = double(process.waitFor());
    catch exception
        wrapped = MException('sshfling:LaunchFailed', ...
            'Could not start SSHFling executable "%s": %s', ...
            executable, exception.message);
        throwAsCaller(wrapped);
    end
end

function values = normalizeArguments(arguments)
    if isstring(arguments)
        if ~isvector(arguments)
            error('sshfling:InvalidArguments', ...
                'Arguments must be a string vector or cell array of text scalars.');
        end
        values = cellstr(arguments(:).');
    elseif iscell(arguments)
        values = cell(size(arguments));
        for index = 1:numel(arguments)
            values{index} = normalizeScalar(arguments{index}, ...
                sprintf('argument %d', index));
        end
        values = values(:).';
    elseif isempty(arguments)
        values = {};
    else
        error('sshfling:InvalidArguments', ...
            'Arguments must be a string vector or cell array of text scalars.');
    end
end

function value = normalizeScalar(input, label)
    if isstring(input) && isscalar(input) && ~ismissing(input)
        value = char(input);
    elseif ischar(input) && (isrow(input) || isempty(input))
        value = input;
    else
        error('sshfling:InvalidArgument', '%s must be a text scalar.', label);
    end
    if any(value == char(0))
        error('sshfling:InvalidArgument', '%s contains a NUL character.', label);
    end
end
