use strict;
use warnings;

use ExtUtils::MakeMaker;
use File::Find;

my %package_files = (
    'lib/SSHFling.pm' => '$(INST_LIB)/SSHFling.pm',
);

find(
    sub {
        return if -d $_;
        my $source = $File::Find::name;
        $source =~ s{\\}{/}g;
        (my $destination = $source) =~ s{\Alib/}{};
        $package_files{$source} = '$(INST_LIB)/' . $destination;
    },
    'lib/SSHFling/runtime',
);

WriteMakefile(
    NAME          => 'SSHFling',
    VERSION_FROM  => 'lib/SSHFling.pm',
    ABSTRACT_FROM => 'lib/SSHFling.pm',
    AUTHOR        => 'GRWLX',
    LICENSE       => 'restricted',
    EXE_FILES     => ['bin/sshfling'],
    MIN_PERL_VERSION => '5.26.0',
    PREREQ_PM     => {
        'File::Basename' => 0,
        'File::Spec'     => 0,
    },
    TEST_REQUIRES => {
        'Test::More' => 0,
    },
    PM            => \%package_files,
    META_MERGE    => {
        'meta-spec' => { version => 2 },
        resources => {
            homepage   => 'https://github.com/GRWLX/sshfling',
            repository => {
                type => 'git',
                url  => 'https://github.com/GRWLX/sshfling.git',
                web  => 'https://github.com/GRWLX/sshfling',
            },
        },
    },
);
