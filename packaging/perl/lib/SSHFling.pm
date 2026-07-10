package SSHFling;

use strict;
use warnings;

use Errno qw(ENOENT);
use File::Basename qw(dirname);
use File::Spec;

our $VERSION = '0.0.0';

sub version {
    return $VERSION;
}

sub runtime_path {
    return File::Spec->catfile(dirname(__FILE__), 'SSHFling', 'runtime', 'sshfling.py');
}

sub template_dir {
    return File::Spec->catdir(dirname(__FILE__), 'SSHFling', 'runtime', 'templates');
}

sub python_candidates {
    my @candidates;
    my $configured = $ENV{SSHFLING_PYTHON} // '';
    push @candidates, [$configured] if $configured ne '';
    if ($^O eq 'MSWin32') {
        push @candidates, ['py', '-3'], ['python'], ['python3'];
    }
    else {
        push @candidates, ['python3'], ['python'];
    }
    return @candidates;
}

sub _normalize_template_modes {
    return if $^O eq 'MSWin32';
    my @executables = (
        'native/sshfling-linux-account',
        'native/sshfling-unix-identity',
        'production/sshfling-login-shell',
        'production/sshfling-session',
        'scripts/create-network.sh',
        'scripts/generate-ssh-key.sh',
        'scripts/install-local.sh',
        'scripts/uninstall-local.sh',
        'ssh-client/entrypoint.sh',
        'ssh-server/entrypoint.sh',
        'ssh-server/limited-session.sh',
    );
    for my $relative (@executables) {
        my $path = File::Spec->catfile(template_dir(), split m{/}, $relative);
        chmod 0755, $path if -f $path;
    }
}

sub run {
    my @arguments = @_;
    _normalize_template_modes();

    local $ENV{PYTHONUNBUFFERED} = $ENV{PYTHONUNBUFFERED} // '1';
    local $ENV{SSHFLING_TEMPLATE_DIR} = $ENV{SSHFLING_TEMPLATE_DIR} // template_dir();

    for my $candidate (python_candidates()) {
        my ($program, @prefix) = @{$candidate};
        my $status = system { $program } $program, @prefix, runtime_path(), @arguments;
        if ($status == -1) {
            next if $! == ENOENT;
            warn "sshfling: could not execute $program: $!\n";
            return 127;
        }
        return 128 + ($status & 127) if $status & 127;
        return $status >> 8;
    }

    warn "sshfling: Python 3 is required; set SSHFLING_PYTHON to its executable\n";
    return 127;
}

1;

=head1 NAME

SSHFling - launcher API for the bundled SSHFling runtime

=head1 SYNOPSIS

  use SSHFling;
  exit SSHFling::run('--version');

=head1 DESCRIPTION

SSHFling provides a Perl library and executable around the bundled canonical
SSHFling Python runtime and deployment templates.

=cut
