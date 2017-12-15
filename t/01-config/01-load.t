use FindBin qw($Bin);
use lib "$Bin/../../lib";
use Test::Most;

use Gossamer::Config;

Gossamer::Config->init;
ok(config,          "loaded config");
ok(config->appName, "got appNme");
is(config->appName, "Test App", "got right appNme");
ok(config->someSection, "got someSection");
is(config->someSection->valueA, "AAAA", "got someSection valueA");
ok(config->anotherSection, "got anotherSection");
is(config->anotherSection->value, "BBB", "got anotherSection value");

Gossamer::Config->init("test");

ok(config,          "loaded config");
ok(config->appName, "got appNme");
is(config->appName, "Test App", "got right appNme");
ok(config->someSection, "got someSection");
is(config->someSection->valueA, "AAAA", "got someSection valueA");
ok(config->anotherSection, "got anotherSection");
is(config->anotherSection->value, "JSON", "got anotherSection value");

eval <<'EOE';
package Gossamer::Config::Template;
use strict;
use warnings;
our @ISA = ('Gossamer::Config::Base');

sub path {
    "/var/www/public"
}
EOE

Gossamer::Config->init;

ok(config->template, "got template section");
is(config->template->path, "/var/www/public", "got template path");


done_testing();
