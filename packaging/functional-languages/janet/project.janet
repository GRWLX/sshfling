(declare-project
  :name "sshfling"
  :description "Janet launcher for the bundled SSHFling runtime"
  :version "0.0.0"
  :license "LicenseRef-Proprietary"
  :url "https://github.com/GRWLX/sshfling"
  :entry "src/sshfling/init.janet"
  :dependencies @[]
  :files @["src" "test" "runtime" "LICENSE" "README.md"])

(declare-source
  :prefix "sshfling"
  :source ["src/sshfling/init.janet" "runtime"])

(declare-binscript
  :main "bin/sshfling"
  :hardcode-syspath true
  :is-janet false)
