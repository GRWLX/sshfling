(use-modules (sshfling))

(define arguments (cdr (command-line)))
(when (null? arguments)
  (error "The consumer requires a smoke-project path"))
(define smoke-directory (car arguments))

(unless (zero? (run '("--version")))
  (error "run(--version) failed"))
(unless (zero? (run (list "init" smoke-directory "--force" "--session-seconds" "60")))
  (error "run(init) failed"))
(unless (file-exists? (string-append smoke-directory "/production/sshfling-session"))
  (error "The initialized project is missing the session wrapper"))
