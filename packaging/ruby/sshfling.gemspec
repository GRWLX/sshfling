require_relative "lib/sshfling/version"

Gem::Specification.new do |spec|
  spec.name = "sshfling"
  spec.version = SSHFling::VERSION
  spec.authors = ["GRWLX"]
  spec.summary = "Temporary SSH access using standard OpenSSH"
  spec.description = "Ruby launcher and CLI package for the bundled SSHFling runtime."
  spec.homepage = "https://github.com/GRWLX/sshfling"
  spec.licenses = ["Nonstandard"]
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0")

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/GRWLX/sshfling",
    "documentation_uri" => "https://github.com/GRWLX/sshfling/tree/main/docs"
  }

  spec.files = Dir.glob(
    ["bin/**/*", "lib/**/*", "runtime/**/*", "runtime/**/.*", "LICENSE", "README.md"],
    File::FNM_DOTMATCH
  ).select { |path| File.file?(path) }.sort
  spec.bindir = "bin"
  spec.executables = ["sshfling"]
  spec.require_paths = ["lib"]
end
