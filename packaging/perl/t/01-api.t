use strict;
use warnings;

use Test::More;
use SSHFling;

ok(SSHFling::version() ne '0.0.0', 'release version was injected');
ok(-f SSHFling::runtime_path(), 'runtime script is packaged');
ok(-d SSHFling::template_dir(), 'template directory is packaged');
is(SSHFling::run('--version'), 0, 'library API runs the CLI');

done_testing();
