(asdf:defsystem "sshfling"
  :description "Common Lisp launcher for the bundled SSHFling runtime"
  :version "0.0.0"
  :author "GRWLX"
  :license "Apache-2.0"
  :depends-on ("uiop")
  :serial t
  :components ((:module "src"
                :components ((:file "package")
                             (:file "sshfling")))
               (:static-file "runtime/sshfling.py")
               (:static-file "runtime/templates/.env.example")
               (:static-file "runtime/templates/compose.server.yml")
               (:static-file "runtime/templates/production/sshfling-session")))

(asdf:defsystem "sshfling/test"
  :depends-on ("sshfling")
  :components ((:module "test" :components ((:file "consumer")))))
