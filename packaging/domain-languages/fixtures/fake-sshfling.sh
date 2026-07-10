#!/bin/sh
# SPDX-License-Identifier: MIT

if [ "$#" -ne 3 ] || \
   [ "$1" != "--probe" ] || \
   [ "$2" != "argument with spaces" ] || \
   [ "$3" != "literal;\$()&" ]; then
    printf '%s\n' "fake sshfling received an invalid argument vector" >&2
    exit 97
fi

printf '%s\n' "fake sshfling stdout"
printf '%s\n' "fake sshfling stderr" >&2
exit 23
