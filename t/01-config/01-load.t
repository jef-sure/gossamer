use FindBin qw($Bin);
use lib "$Bin/../../lib";
use Test::Most;

use Gossamer::Config;

sub valueB {
    "bBbB";
}

sub dynParam {
    "dyn";
}

sub sub_hooks {
    $_[1];
}

Gossamer::Config->init;
ok( config,          "loaded config" );
ok( config->appName, "got appNme" );
is( config->appName, "Test App", "got right appNme" );
ok( config->someSection, "got someSection" );
is( config->someSection->valueA, "AAAA", "got someSection valueA" );
is( config->someSection->valueB, "bBbB", "got someSection valueB" );
is( config->param,               "dyn",  "got dynamic parameter" );
ok( config->anotherSection, "got anotherSection" );
is( config->anotherSection->value, "BBB",                              "got anotherSection value" );
is( ref config->request,           'Gossamer::Config::Request',        'section request parsed' );
is( ref config->request->hooks,    'Gossamer::Config::Request::Hooks', 'subsection request hooks parsed' );
is( config->request->hooks->before('before'), 'before', 'before hook' );
is( config->request->hooks->before('after'),  'after',  'after hook' );
ok( config->project_dir =~ /01-config$/,     'project dir' );
ok( config->static_dir =~ /01-config\/www$/, 'static dir' );
is( config->templates_dir, undef, 'empty templates_dir' );

Gossamer::Config->init("test");

ok( config,          "loaded config with test environment" );
ok( config->appName, "got appNme" );
is( config->appName, "Test Env App", "got right appNme" );
ok( config->someSection, "got someSection" );
is( config->someSection->valueA, "AAAA", "got someSection valueA" );
ok( config->anotherSection, "got anotherSection" );
is( config->anotherSection->value, "JSON", "got anotherSection value" );

eval <<'EOE';
package Gossamer::Config::Template;
use strict;
use warnings;
our @ISA = ('Gossamer::Config::base');

sub path {
    "/var/www/public"
}
EOE

Gossamer::Config->init;

ok( config->template, "got template section" );
is( config->template->path, "/var/www/public", "got template path" );

done_testing();
