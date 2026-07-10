(define-module (sshfling)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (sshfling-version
            sshfling-runtime-path
            sshfling-template-dir
            sshfling-run))

(define %sshfling-version "0.0.0")

(define (package-root)
  (let ((root (getenv "SSHFLING_PACKAGE_ROOT")))
    (if (and root (not (string-null? root)))
        root
        (error "set SSHFLING_PACKAGE_ROOT before using the Guix Scheme module"))))

(define (sshfling-version)
  %sshfling-version)

(define (sshfling-runtime-path)
  (let ((configured (getenv "SSHFLING_RUNTIME")))
    (if (and configured (not (string-null? configured)))
        configured
        (string-append (package-root) "/libexec/sshfling/sshfling.py"))))

(define (sshfling-template-dir)
  (let ((configured (getenv "SSHFLING_TEMPLATE_DIR")))
    (if (and configured (not (string-null? configured)))
        configured
        (string-append (package-root) "/share/sshfling/templates"))))

(define (find-python)
  (let* ((configured (getenv "SSHFLING_PYTHON"))
         (candidates (if (and configured (not (string-null? configured)))
                         (list configured)
                         '("python3" "python"))))
    (find (lambda (candidate)
            (if (string-contains candidate "/")
                (access? candidate X_OK)
                (search-path (string-split (or (getenv "PATH") "") #\:)
                             candidate)))
          candidates)))

(define (sshfling-run arguments)
  (unless (list? arguments)
    (error "sshfling-run expects a list of string arguments" arguments))
  (let ((python (find-python)))
    (unless python
      (error "Python 3 is required; set SSHFLING_PYTHON to its executable"))
    (let ((old-template (getenv "SSHFLING_TEMPLATE_DIR"))
          (old-unbuffered (getenv "PYTHONUNBUFFERED")))
      (dynamic-wind
        (lambda ()
          (setenv "SSHFLING_TEMPLATE_DIR" (sshfling-template-dir))
          (unless old-unbuffered
            (setenv "PYTHONUNBUFFERED" "1")))
        (lambda ()
          (let ((status (apply system* python (sshfling-runtime-path) arguments)))
            (match (status:exit-val status)
              (#f 1)
              (value value))))
        (lambda ()
          (if old-template
              (setenv "SSHFLING_TEMPLATE_DIR" old-template)
              (unsetenv "SSHFLING_TEMPLATE_DIR"))
          (if old-unbuffered
              (setenv "PYTHONUNBUFFERED" old-unbuffered)
              (unsetenv "PYTHONUNBUFFERED")))))))
