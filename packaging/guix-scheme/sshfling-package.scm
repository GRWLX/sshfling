(use-modules (ice-9 ftw)
             (gnu packages guile)
             (gnu packages python)
             (guix build-system copy)
             (guix gexp)
             (guix packages))

(package
  (name "sshfling-guix-scheme")
  (version "0.0.0")
  (source
    (local-file (dirname (current-filename))
                "sshfling-guix-scheme-source"
                #:recursive? #t))
  (build-system copy-build-system)
  (arguments
    (list #:install-plan
          #~'(("bin" "bin")
              ("libexec" "libexec")
              ("share" "share")
              ("LICENSE" "share/doc/sshfling-guix-scheme/LICENSE")
              ("package-metadata.json"
               "share/doc/sshfling-guix-scheme/package-metadata.json"))))
  (inputs (list guile-3.0 python))
  (home-page "https://github.com/GRWLX/sshfling")
  (synopsis "Guix Scheme launcher module and CLI for SSHFling")
  (description
    "This package installs a Guile module and command-line launcher for the
bundled canonical SSHFling Python runtime and deployment templates.")
  (license #f))
