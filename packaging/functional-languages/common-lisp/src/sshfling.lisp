(in-package #:sshfling)

(defun environment-or-nil (name)
  (let ((value (uiop:getenv name)))
    (and value (plusp (length value)) value)))

(defun package-root ()
  (or (environment-or-nil "SSHFLING_PACKAGE_ROOT")
      (namestring (asdf:system-source-directory "sshfling"))))

(defun runtime-path ()
  (or (environment-or-nil "SSHFLING_RUNTIME")
      (namestring (merge-pathnames "runtime/sshfling.py" (uiop:ensure-directory-pathname (package-root))))))

(defun template-directory ()
  (or (environment-or-nil "SSHFLING_TEMPLATE_DIR")
      (namestring (merge-pathnames "runtime/templates/" (uiop:ensure-directory-pathname (package-root))))))

(defun run (arguments)
  "Run the bundled SSHFling CLI with ARGUMENTS and return its process status."
  (check-type arguments list)
  (unless (every #'stringp arguments)
    (error "SSHFling arguments must all be strings."))
  (let ((runtime (runtime-path)))
    (if (not (probe-file runtime))
        127
        (let ((python (or (environment-or-nil "SSHFLING_PYTHON") "python3")))
          (handler-case
              (uiop:wait-process
               (uiop:launch-program
                (append (list python runtime) arguments)
                :input :interactive
                :output :interactive
                :error-output :interactive))
            (error (condition)
              (format *error-output* "sshfling: ~A~%" condition)
              127))))))
