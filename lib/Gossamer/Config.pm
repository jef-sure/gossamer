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

sub _load_yaml {
    my $ycfg     = shift;
    my $fdata    = read_text($ycfg);
    my @ymodules = qw(YAML::XS YAML::Tiny YAML::Syck YAML);
    for my $module (@ymodules) {
        if ( eval { load $module; 1 } && ( my $load = $module->can("Load") ) ) {
            return $load->($fdata);
        }
    }
    croak "No YAML module found";
}

sub _load_json {
    my $jcfg  = shift;
    my $fdata = read_binary($jcfg);
    $fdata =~ s/\r?\n$//;
    my @jmodules = qw(Cpanel::JSON::XS JSON::XS JSON::PP JSON);
    for my $module (@jmodules) {
        if ( eval { load $module; 1 } ) {
            return $module->new->utf8->decode($fdata);
        }
    }
    croak "No JSON module found";
}

sub _find_project_root {
    my @pdir = (
        File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..' ) ),
        File::Spec->rel2abs($FindBin::Bin),
        File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '../..' ) ),
    );

    for my $pdir (@pdir) {
        my $libdir = File::Spec->catdir( $pdir, 'lib' );
        my $cyaml = File::Spec->catfile( $pdir, 'config.yaml' );
        my $cyml  = File::Spec->catfile( $pdir, 'config.yml' );
        my $cjson = File::Spec->catfile( $pdir, 'config.json' );
        my $cfg = -f $cyml ? $cyml : -f $cyaml ? $cyaml : -f $cjson ? $cjson : undef;
        if ( -d $libdir && $cfg ) {
            return ( $pdir, $cfg );
        }
    }
    croak "Unable to find project root dir";
}

sub _load_env_config {
    my ( $pdir, $env_name ) = @_;
    my $cyaml = File::Spec->catfile( $pdir, 'environment', $env_name . '.yaml' );
    my $cyml  = File::Spec->catfile( $pdir, 'environment', $env_name . '.yml' );
    my $cjson = File::Spec->catfile( $pdir, 'environment', $env_name . '.json' );
    my $env
        = -f $cyml  ? $cyml
        : -f $cyaml ? $cyaml
        : -f $cjson ? $cjson
        :             undef;
    croak "Unknown environment $env_name" if not $env;
    my $env_data = $env =~ /\.ya?ml$/ ? _load_yaml($env) : _load_json($env);
    return $env_data;
}

sub _load_default_configs {
    no strict 'refs';
    my @lcfg = map { substr( $_, 0, -2 ) } grep { /::$/ && !/base::$/ } keys %{"Gossamer::Config::"};
    my @nlcfg = grep { not exists $config->{$_} and not $config->{ lcfirst $_ } } @lcfg;
    $config->_register_config("::$_") for @nlcfg;
}

sub _load_config_data {
    my $env_name = shift;
    my $data     = {};
    my ( $pdir, $cfg ) = _find_project_root();
    my $libdir = File::Spec->catdir( $pdir, 'lib' );
    if ( not grep { $libdir eq $_ } @INC ) {
        unshift @INC, $libdir;
    }
    my %defaults = ( project_dir => $pdir );
    for (qw(public_html public static www-static www)) {
        my $dir = File::Spec->catdir( $pdir, $_ );
        if ( -d $dir ) {
            $defaults{static_dir} = $dir;
            last;
        }
    }
    $defaults{static_dir} //= undef;
    for (qw(templates views)) {
        my $dir = File::Spec->catdir( $pdir, $_ );
        if ( -d $dir ) {
            $defaults{templates_dir} = $dir;
            last;
        }
    }
    $defaults{templates_dir} //= undef;
    $data = merge \%defaults, $cfg =~ /\.ya?ml$/ ? _load_yaml($cfg) : _load_json($cfg);
    if ($env_name) {
        my $env_data = _load_env_config($pdir, $env_name);
        $data = merge $data, $env_data;
    }
    return $data;
}

sub _store_sections {
    my $data = shift;
    for my $section ( keys %$data ) {
        no strict 'refs';
        no warnings 'redefine';
        if ( 'HASH' eq ref $data->{$section} ) {
            my $mod = ucfirst $section;
            if ( !@{"Gossamer::Config::${mod}::ISA"} ) {
                @{"Gossamer::Config::${mod}::ISA"} = qw(Gossamer::Config::base);
            }
            $config->{$section} = "Gossamer::Config::${mod}"->new( $data->{$section} );
            $config->_register_config( "Gossamer::Config::${mod}", $section );
        } else {
            if ( $data->{$section} && $data->{$section} =~ /^\\&(.*)/ ) {
                croak "$1 code is not loaded" if not *{$1}{CODE};
                $config->{$section} = *{$1}{CODE};
                *{"Gossamer::Config::$section"} = subname "Gossamer::Config::$section" => $config->{$section};
            } else {
                $config->{$section} = $data->{$section};
                *{"Gossamer::Config::$section"}
                    = subname "Gossamer::Config::$section" => sub { $config->{$section} };
            }
        }
    }
}

sub _register_config {
    my ( $class, $module, $accessor ) = @_;
    if ( not $accessor ) {
        $accessor = $module;
        $accessor =~ s/.*:://;
        $accessor = lcfirst $accessor;
    }
    if ( $module =~ /^::/ ) {
        $module = "Gossamer::Config$module";
    }
    $config->{$accessor} ||= $module->new;
    no strict 'refs';
    no warnings 'redefine';
    *{"Gossamer::Config::$accessor"}
        = subname "Gossamer::Config::$accessor" => sub { $config->{$accessor} };
}

sub init {
    my ( $class, $data ) = @_;
    my $env_name = !ref $data ? $data : undef;
    $config = {};
    $data = _load_config_data($env_name) if 'HASH' ne ref $data;
    bless $config, $class;
    $data ||= {};
    _store_sections($data);
    _load_default_configs();
}

package Gossamer::Config::base;
use Sub::Name;
use Carp;
use strict;
use warnings;

sub new {
    my $self = $_[1];
    $self = { value => $self } if 'HASH' ne ref $self;
    bless $self, $_[0];
    $self->load_from_config( +{%$self} );
    return $self;
}

sub load_from_config {
    my ( $class, $data ) = @_;
    $class = ref $class if ref $class;
    $data = { value => $data } if 'HASH' ne ref $data;
    for my $accessor ( keys %$data ) {
        no strict 'refs';
        no warnings 'redefine';
        if (    $data->{$accessor}
            and not ref $data->{$accessor}
            and $data->{$accessor} =~ /^\\&(.*)/ )
        {
            croak "$1 code is not loaded" if not *{$1}{CODE};
            *{ $class . "::$accessor" }
                = subname "${class}::$accessor" => *{$1}{CODE};
        } else {
            if ( 'HASH' eq ref $data->{$accessor} ) {
                my $mod = ucfirst $accessor;
                if ( !@{"${class}::${mod}::ISA"} ) {
                    @{"${class}::${mod}::ISA"} = qw(Gossamer::Config::base);
                }
                $data->{$accessor} = "${class}::${mod}"->new( $data->{$accessor} );
            }
            *{ $class . "::$accessor" } = subname "${class}::$accessor" => sub { $data->{$accessor} };
        }
    }
}

1;

__END__

=pod
 
=encoding UTF-8
 
=head1 NAME
 
Gossamer::Config - Configure Gossamer to suit your needs
 

=head1 SYNOPSIS

  use Gossamer::Config;
  Gossamer::Config->init;
  say config->project_dir;

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

Your configuration file should be in project root directory.
File name must be one of: config.yml, config.yaml, config.json.

When you initialize config for some specific environment, this
environment config is merged over normal config data.

To load environment config you have to put config in YAML or JSON
format into environment directory under project root directory
with corresponding name like B<test.yaml> and call init() with
environment name as parameter.

  Gossamer::Config->init("test");

Config initialization tries to determine project root, templates 
and static content directories automatically. 
When it can't find templates or static content directories, their
config values will be undefined.  

You can override default values by putting required values in config file.

=head1 CONFIG STRUCTURE

YAML example.

  app_name: Test App
  log_level: INFO
  request:
    hooks:
      before_parse: \&MyApp::start_request
  db:
    dsn: dbi:Pg:dbname=my_app_dbname
    user: dbuser
    password: dbpassword

Basically, config consists of parameters and sections. 
Sections can consist also of subsections and parameters.
Every parameter value starting with B<\&> will be treated as 
symbolic name of function. 

Every section name and parameter name
have accessors in corresponding config module. Config modules
can be preloaded or will be created automatically during config
parsing. They all usually are derived from C<Gossamer::Config::base>.

This particular example config creates following structure:

  Gossamer::Config
    app_name: "Test App"
    log_level: "INFO"
    request: Gossamer::Config::Request
      hooks: Gossamer::Config::Request::Hooks
        before_parse: \&MyApp::start_request
    db: Gossamer::Config::Db
      dsn: "dbi:Pg:dbname=my_app_dbname"
      user: "dbuser"
      password: "dbpassword"

When you need to have some default values for some section,
just load corresponding config module with requred accessors.
   
=head1 AUTHOR
 
Anton Petrusevich
 
=head1 COPYRIGHT AND LICENSE
 
This software is copyright (c) 2017 by Anton Petrusevich.
 
This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
 
=cut
