rockspec_format = "3.0"
package = "sshfling"
version = "0.0.0-1"

source = {
  url = "git+https://github.com/GRWLX/sshfling.git",
  tag = "v0.0.0"
}

description = {
  summary = "Lua launcher library and CLI for SSHFling",
  detailed = [[
    A Lua 5.1+ API and executable that launch the bundled canonical SSHFling
    Python runtime with its deployment templates.
  ]],
  homepage = "https://github.com/GRWLX/sshfling",
  license = "Apache-2.0"
}

dependencies = {
  "lua >= 5.1"
}

supported_platforms = {
  "unix"
}

build = {
  type = "builtin",
  modules = {
    sshfling = "lua/sshfling/init.lua"
  },
  install = {
    bin = {
      sshfling = "bin/sshfling"
    }
  }
}
