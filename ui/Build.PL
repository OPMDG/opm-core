use 5.006;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'OPM',
    dist_author         => q{dalibo},
    dist_version_from   => 'lib/OPM.pm',
    dist_abstract => 'Open PostgreSQL Monitoring',
    release_status      => 'unstable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'Mojolicious' => 0,
        'Mojolicious::Plugin::I18N' => 0,
        'DBD::Pg' => 0,
        'TAP::Harness::Archive' => 0
    },
    add_to_cleanup     => [ 'OPM-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
