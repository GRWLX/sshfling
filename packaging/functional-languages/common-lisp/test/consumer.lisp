(require :asdf)
(asdf:load-asd (truename "sshfling.asd"))
(asdf:load-system "sshfling")

(let* ((arguments (uiop:command-line-arguments))
       (smoke-directory (first arguments)))
  (unless smoke-directory
    (error "The consumer requires a smoke-project path."))
  (unless (zerop (sshfling:run '("--version")))
    (error "run(--version) failed."))
  (unless (zerop (sshfling:run (list "init" smoke-directory "--force" "--session-seconds" "60")))
    (error "run(init) failed."))
  (unless (probe-file (merge-pathnames "production/sshfling-session"
                                       (uiop:ensure-directory-pathname smoke-directory)))
    (error "The initialized project is missing the session wrapper.")))
