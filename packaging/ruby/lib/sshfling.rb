require_relative "sshfling/version"

module SSHFling
  module_function

  def python_candidates
    candidates = []
    configured = ENV.fetch("SSHFLING_PYTHON", "").strip
    candidates << [configured, []] unless configured.empty?
    if Gem.win_platform?
      candidates.concat([["py", ["-3"]], ["python", []], ["python3", []]])
    else
      candidates.concat([["python3", []], ["python", []]])
    end
    candidates
  end

  def runtime_path
    File.expand_path("../runtime/sshfling.py", __dir__)
  end

  def template_dir
    File.expand_path("../runtime/templates", __dir__)
  end

  def run(arguments)
    normalize_template_modes
    candidate = python_candidates.find { |program, _fixed| command_available?(program) }
    raise "Python 3 is required; set SSHFLING_PYTHON to its executable." unless candidate

    program, fixed_arguments = candidate
    environment = {
      "PYTHONUNBUFFERED" => "1",
      "SSHFLING_TEMPLATE_DIR" => template_dir
    }
    system(environment, program, *fixed_arguments, runtime_path, *arguments)
    $CHILD_STATUS ? ($CHILD_STATUS.exitstatus || 1) : ($?.exitstatus || 1)
  end

  def normalize_template_modes
    executable_paths.each do |relative|
      path = File.join(File.dirname(runtime_path), relative)
      File.chmod(0o755, path) if File.file?(path)
    rescue Errno::EPERM
      nil
    end
  end
  private_class_method :normalize_template_modes

  def executable_paths
    [
      "sshfling.py",
      "templates/native/sshfling-linux-account",
      "templates/native/sshfling-unix-identity",
      "templates/production/sshfling-session",
      "templates/scripts/create-network.sh",
      "templates/scripts/generate-ssh-key.sh",
      "templates/scripts/install-local.sh",
      "templates/scripts/uninstall-local.sh",
      "templates/ssh-client/entrypoint.sh",
      "templates/ssh-server/entrypoint.sh",
      "templates/ssh-server/limited-session.sh"
    ]
  end
  private_class_method :executable_paths

  def command_available?(command)
    return File.file?(command) if command.include?(File::SEPARATOR) || (File::ALT_SEPARATOR && command.include?(File::ALT_SEPARATOR))

    extensions = if Gem.win_platform?
                   [""] + ENV.fetch("PATHEXT", ".EXE;.BAT;.CMD").split(File::PATH_SEPARATOR)
                 else
                   [""]
                 end
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
      extensions.any? do |extension|
        candidate = File.join(directory, "#{command}#{extension}")
        File.file?(candidate) && (Gem.win_platform? || File.executable?(candidate))
      end
    end
  end
  private_class_method :command_available?
end
