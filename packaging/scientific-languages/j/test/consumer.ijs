load 'src/sshfling.ijs'
smoke=. 2{ARGV
assert. 0 = run_sshfling_ <'--version'
assert. 0 = run_sshfling_ 'init';smoke;'--force';'--session-seconds';'60'
exit 0
