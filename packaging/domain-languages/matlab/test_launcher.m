% SPDX-License-Identifier: MIT
function test_launcher()
%TEST_LAUNCHER Conformance probe used by build-domain-languages.sh.

    executable = getenv('SSHFLING_TEST_EXECUTABLE');
    assert(~isempty(executable), 'SSHFLING_TEST_EXECUTABLE is required.');
    status = sshfling.run( ...
        {'--probe', 'argument with spaces', 'literal;$()&'}, executable);
    assert(status == 23, 'Expected fake SSHFling status 23, got %d.', status);
end
