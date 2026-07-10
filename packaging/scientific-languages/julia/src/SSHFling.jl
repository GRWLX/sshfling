module SSHFling

export run, runtime_path, template_directory

configured_or(name, default) = let value = get(ENV, name, "")
    isempty(value) ? default : value
end

runtime_path() = configured_or(
    "SSHFLING_RUNTIME",
    normpath(joinpath(@__DIR__, "..", "runtime", "sshfling.py")),
)

template_directory() = configured_or(
    "SSHFLING_TEMPLATE_DIR",
    normpath(joinpath(@__DIR__, "..", "runtime", "templates")),
)

function run(args::AbstractVector{<:AbstractString})
    isfile(runtime_path()) || return 127
    python = configured_or("SSHFLING_PYTHON", "python3")
    command = Cmd([python, runtime_path(), String.(args)...])
    command = addenv(
        command,
        "SSHFLING_TEMPLATE_DIR" => template_directory(),
        "PYTHONUNBUFFERED" => "1",
    )
    try
        process = Base.run(ignorestatus(command))
        return process.exitcode
    catch error
        error isa Base.IOError || rethrow()
        return 127
    end
end

end
