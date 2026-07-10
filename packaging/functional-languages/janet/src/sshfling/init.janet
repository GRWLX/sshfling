(defn configured-or [name fallback]
  (def value (os/getenv name))
  (if (and value (not= value "")) value fallback))

(def package-root
  (os/realpath (string (module/expand-path (dyn :current-file) ":dir:"))))

(defn runtime-path []
  (configured-or "SSHFLING_RUNTIME"
    (string (configured-or "SSHFLING_PACKAGE_ROOT" package-root)
            "/runtime/sshfling.py")))

(defn template-directory []
  (configured-or "SSHFLING_TEMPLATE_DIR"
    (string (configured-or "SSHFLING_PACKAGE_ROOT" package-root)
            "/runtime/templates")))

(defn run [args]
  (assert (all string? args) "SSHFling arguments must all be strings")
  (if (not (os/stat (runtime-path)))
    127
    (do
      (def command @[(configured-or "SSHFLING_PYTHON" "python3") (runtime-path)])
      (each argument args (array/push command argument))
      (def previous-template (os/getenv "SSHFLING_TEMPLATE_DIR"))
      (os/setenv "SSHFLING_TEMPLATE_DIR" (template-directory))
      (def status
        (try
          (os/execute command :p)
          ([error]
            (eprint "sshfling: " error)
            127)))
      (if previous-template
        (os/setenv "SSHFLING_TEMPLATE_DIR" previous-template)
        (os/setenv "SSHFLING_TEMPLATE_DIR" nil))
      status)))

{:run run
 :runtime-path runtime-path
 :template-directory template-directory}
