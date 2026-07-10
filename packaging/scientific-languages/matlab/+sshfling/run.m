function status = run(arguments)
%RUN Start the bundled SSHFling runtime and return its exit status.
%   STATUS = SSHFLING.RUN(ARGUMENTS) passes a cell array of character
%   vectors to the packaged Python runtime. This package is validated with
%   GNU Octave and does not claim MathWorks MATLAB runtime conformance.

    if nargin < 1
        arguments = {};
    end

    runtime = sshfling.runtimePath();
    if exist(runtime, 'file') ~= 2
        status = 127;
        return;
    end

    values = normalizeArguments(arguments);
    command = [ ...
        'SSHFLING_TEMPLATE_DIR=', shellQuote(sshfling.templateDirectory()), ...
        ' PYTHONUNBUFFERED=1 ', shellQuote(configuredOr('SSHFLING_PYTHON', 'python3')), ...
        ' ', shellQuote(runtime)];

    for index = 1:numel(values)
        command = [command, ' ', shellQuote(values{index})]; %#ok<AGROW>
    end

    status = system(command);
    if status < 0
        status = 127;
    end
end

function values = normalizeArguments(arguments)
    if ischar(arguments)
        values = {normalizeScalar(arguments, 'argument 1')};
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
            'Arguments must be a character vector or cell array of character vectors.');
    end
end

function value = normalizeScalar(input, label)
    if ischar(input) && (isrow(input) || isempty(input))
        value = input;
    else
        error('sshfling:InvalidArgument', '%s must be a character vector.', label);
    end
    if any(value == char(0))
        error('sshfling:InvalidArgument', '%s contains a NUL character.', label);
    end
end

function quoted = shellQuote(value)
    quoted = ['''' strrep(value, '''', '''"''"''') ''''];
end

function value = configuredOr(name, fallback)
    value = getenv(name);
    if isempty(value)
        value = fallback;
    end
end
