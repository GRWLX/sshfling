root=. getenv 'SSHFLING_PACKAGE_ROOT'
root=. > (root ; jpath '~addons/sshfling') {~ 0=#root
load root,'/src/sshfling.ijs'
exit run_sshfling_ 2}.ARGV
