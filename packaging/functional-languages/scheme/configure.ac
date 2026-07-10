AC_INIT([sshfling-guile], [0.0.0], [https://github.com/GRWLX/sshfling/issues])
AC_CONFIG_SRCDIR([module/sshfling.scm.in])
AC_PROG_INSTALL
AC_PATH_PROG([GUILE], [guile])
AS_IF([test -z "$GUILE"], [AC_MSG_ERROR([Guile 3.0 is required])])
AC_CONFIG_FILES([Makefile module/sshfling.scm bin/sshfling-guile])
AC_OUTPUT
