package Gossamer::Config;
use strict;
use warnings;
use Module::Load;
use FindBin;
use File::Spec;
use File::Slurper qw(read_binary read_text);
use Hash::Merge::Simple 'merge';
use Sub::Name;
use Carp;
use base 'Exporter';

our @EXPORT = qw(config);

my $config;

sub config {
    $config;
}

sub load_yaml {
    my $ycfg     = shift;
    my $fdata    = read_text($ycfg);
    my @ymodules = qw(YAML::XS YAML::Tiny YAML::Syck YAML);
    for my $module (@ymodules) {
        if (eval {load $module; 1} && (my $load = $module->can("Load"))) {
            return $load->($fdata);
        }
    }
    croak "No YAML module found";
}

sub load_json {
    my $jcfg  = shift;
    my $fdata = read_binary($jcfg);
    $fdata =~ s/\r?\n$//;
    my @jmodules = qw(Cpanel::JSON::XS JSON::XS JSON::PP JSON);
    for my $module (@jmodules) {
        if (eval {load $module; 1}) {
            return $module->new->utf8->decode($fdata);
        }
    }
    croak "No JSON module found";
}

sub init {
    my ($class, $data) = @_;
    my $env_name = !ref $data ? $data : undef;
    $config = {};
    if (not ref $data) {
        my @pdir = (
            File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..')),
            File::Spec->rel2abs($FindBin::Bin),
            File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '../..')),
        );
        my $found = 0;
        for my $pdir (@pdir) {
            my $libdir = File::Spec->rel2abs(File::Spec->catdir($pdir, 'lib'));
            my $cyaml = File::Spec->rel2abs(File::Spec->catfile($pdir, 'config.yaml'));
            my $cyml  = File::Spec->rel2abs(File::Spec->catfile($pdir, 'config.yml'));
            my $cjson = File::Spec->rel2abs(File::Spec->catfile($pdir, 'config.json'));
            my $cfg = -f $cyml ? $cyml : -f $cyaml ? $cyaml : -f $cjson ? $cjson : undef;
            if (-d $libdir && $cfg) {
                $found = 1;
                if (not grep {$libdir eq $_} @INC) {
                    unshift @INC, $libdir;
                }
                $config->{project_dir} = $pdir;
                $data = $cfg =~ /\.ya?ml$/ ? load_yaml($cfg) : load_json($cfg);
                if ($env_name) {
                    my $cyaml = File::Spec->rel2abs(File::Spec->catfile($pdir, 'environment', $env_name . '.yaml'));
                    my $cyml  = File::Spec->rel2abs(File::Spec->catfile($pdir, 'environment', $env_name . '.yml'));
                    my $cjson = File::Spec->rel2abs(File::Spec->catfile($pdir, 'environment', $env_name . '.json'));
                    my $env
                        = -f $cyml  ? $cyml
                        : -f $cyaml ? $cyaml
                        : -f $cjson ? $cjson
                        :             undef;
                    croak "Unknown environment $env_name" if not $cfg;
                    my $env_data = $env =~ /\.ya?ml$/ ? load_yaml($env) : load_json($env);
                    $data = merge $data, $env_data;
                }
                last;
            }
        }
        croak "Unable to find project root dir" if not $found;
    }
    $data ||= {};
    bless $config, $class;
    for my $section (keys %$data) {
        no strict 'refs';
        no warnings 'redefine';
        if ('HASH' eq ref $data->{$section}) {
            my $mod = ucfirst $section;
            if (!@{"Gossamer::Config::${mod}::ISA"}) {
                @{"Gossamer::Config::${mod}::ISA"} = qw(Gossamer::Config::Base);
            }
            $config->{$section} = "Gossamer::Config::${mod}"->new;
            $config->{$section}->load_from_config($data->{$section});
            $config->register_config("Gossamer::Config::${mod}", $section);
        } else {
            if ($data->{$section} && $data->{$section} =~ /^\\&(.*)/) {
                croak "$1 code is not loaded" if not *{$1}{CODE};
                $config->{$section} = *{$1}{CODE};
                *{"Gossamer::Config::$section"} = subname "Gossamer::Config::$section" => $config->{$section};
            } else {
                $config->{$section} = $data->{$section};
                *{"Gossamer::Config::$section"} = subname "Gossamer::Config::$section" => sub {$config->{$section}};
            }
        }
    }
    {
        no strict 'refs';
        my @lcfg = map {substr($_, 0, -2)} grep {/::$/ && !/Base::$/} keys %{"Gossamer::Config::"};
        my @nlcfg = grep {not exists $config->{$_} and not $config->{lcfirst $_}} @lcfg;
        $config->register_config("::$_") for @nlcfg;
    }
}

sub register_config {
    my ($class, $module, $accessor) = @_;
    if (not $accessor) {
        $accessor = $module;
        $accessor =~ s/.*:://;
        $accessor = lcfirst $accessor;
    }
    if ($module =~ /^::/) {
        $module = "Gossamer::Config$module";
    }
    $config->{$accessor} ||= $module->new;
    no strict 'refs';
    no warnings 'redefine';
    *{"Gossamer::Config::$accessor"}
        = subname "Gossamer::Config::$accessor" => sub {$config->{$accessor}};
}

package Gossamer::Config::Base;
use Sub::Name;
use Carp;
use strict;
use warnings;

sub new {
    my $self = $_[1];
    $self = {value => $self} if 'HASH' ne ref $self;
    bless $self, $_[0];
    $self->load_from_config(+{%$self});
    return $self;
}

sub load_from_config {
    my ($class, $data) = @_;
    $class = ref $class if ref $class;
    $data = {value => $data} if 'HASH' ne ref $data;
    for my $accessor (keys %$data) {
        no strict 'refs';
        no warnings 'redefine';
        if (    $data->{$accessor}
            and not ref $data->{$accessor}
            and $data->{$accessor} =~ /^\\&(.*)/)
        {
            croak "$1 code is not loaded" if not *{$1}{CODE};
            *{$class . "::$accessor"}
                = subname "${class}::$accessor" => *{$1}{CODE};
        } else {
            *{$class . "::$accessor"} = subname "${class}::$accessor" => sub {$data->{$accessor}};
        }
    }
}

1;

__END__
=pod
 
=encoding UTF-8
 
=head1 NAME
 
Gossamer::Config - Configure Gossamer to suit your needs
 
=head1 VERSION
 
version 0.01
 
=head1 DESCRIPTION

The Gossamer configuration handles reading the configuration
of your Gossamer apps. 

=head1 CONFIGURED VALUES

All configured values considered read only. You can configure dynamic values
supplying symbolic code references as values. 

For every config section you can define default modules with default values.

=head2 Configuration file path and file names

Config initialization tries to determine project root directory automatically.
Your configuration file  


=head1 AUTHOR
 
Anton Petrusevich
 
=head1 COPYRIGHT AND LICENSE
 
This software is copyright (c) 2017 by Anton Petrusevich.
 
This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
 
=cut
