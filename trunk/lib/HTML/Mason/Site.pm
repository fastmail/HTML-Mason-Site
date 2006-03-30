package HTML::Mason::Site;

use strict;
use warnings;
use 5.006001;

use base qw(Class::Accessor);

use UNIVERSAL::require;
use NEXT;
use YAML::Syck ();
use IO::All;
use File::Basename ();
use Scalar::Util ();
use CGI::Cookie ();
use Object::Array;

# fatalsToBrowser isn't working for some reason
use CGI::Carp;

__PACKAGE__->mk_accessors(
  'config',
);

__PACKAGE__->mk_ro_accessors(
  'name',
);

our $ABORT = "html_mason_site_abort\n";

my @STD_MODULES = (
  { name => 'Carp',      args => [qw(carp)] },
  { name => 'CGI::Carp', args => [qw(fatalsToBrowser)] },
);

my @STD_CTYPES = (
  { is  => qr!^text/! },
  { not => qr!php! },
);

=head1 NAME

HTML::Mason::Site - encapsulate per-site Mason handlers

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

=head1 METHODS

=head2 new

=cut

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  # invoke overridden config mutator in case we were passed
  # a YAML file location
  $self->config($self->config) unless ref $self->config;
  $self->{name} ||= delete $self->config->{name};
  return $self;
}

=head2 name

=head2 config

=cut

sub config {
  my $self = shift;
  if (@_) {
    my $arg = shift;
    if (! ref $arg && -f $arg) {
      my $name = $arg;
      $arg = YAML::Syck::Load(io($arg)->all);
      $arg->{name} = File::Basename::basename($name, ".yml");
    }
    $arg = $self->_canonical_config($arg);
    $self->_config_accessor($arg);
  }
  return $self->_config_accessor;
}

sub _expand_ctype {
  my ($ctype) = @_;
  if (ref $ctype eq 'ARRAY') {
    return Object::Array->new([ map { _expand_ctype($_) } @$ctype ]);
  } elsif (ref $ctype eq 'HASH') {
    return { not => qr/$ctype->{not}/i };
  } else {
    return { is  => qr/$ctype/i };
  }
}

sub _canonical_config {
  my ($self, $arg) = @_;

  for my $module (@{ $arg->{modules} ||= [] }) {
    if (ref $module eq 'HASH') {
      $module->{args} ||= [];
    } else {
      $module = { name => $module, args => [] };
    }
  }

  $arg->{content_types} = _expand_ctype($arg->{content_types} || [ @STD_CTYPES ]);

  for my $global (keys %{ $arg->{globals} ||= {} }) {
    warn "found allowed global: $global\n";
    $arg->{handler}->{allow_globals} ||= [];
    push @{ $arg->{handler}->{allow_globals} }, $global;
  }    

  return $arg;
}

=head2 mason_config

=cut

sub mason_config {
  my $self = shift;
  if (@_) {
    while (my ($key, $val) = each %{ $_[0] }) {
      $self->config->{handler}->{$key} = $val;
    }
  }
  return wantarray
    ? %{ $self->config->{handler} }
      : $self->config->{handler};
}

=head2 comp_roots

Returns only the directories, not the keys

=cut

sub comp_roots {
  my $self = shift;
  my $root = $self->mason_config->{comp_root};
  $root = ref $root eq 'ARRAY' ? [
    map { $_->[1] } @{ $root }
  ] : [ $root ];
  return wantarray ? @{ $root } : $root;
}

=head2 require_modules

=cut

sub _command_import {
  package HTML::Mason::Commands;
  shift->import(@_);
}

sub require_modules {
  my $self = shift;
  for my $module (@STD_MODULES, @{ $self->config->{modules} }) {
    print STDERR "requiring $module->{name}\n";
    $module->{name}->require;
    next if $module->{no_import};
    my @args = @{ $module->{args} };
    _command_import($module->{name}, @args);
  }
}

=head2 handles_content_type

=cut

sub _eval_ctype {
  my ($ctype, $val, $or) = @_;
  if (eval { $ctype->ref }) {
    # it's an Object::Array
    my $meth = $or ? "any" : "all";
    return $ctype->$meth(sub { _eval_ctype($_, $val, !$or) });
  }
  return 0 if (
    $ctype->{is} && $val !~ $ctype->{is} or
      $ctype->{not} && $val =~ $ctype->{not}
    );
  return 1;
}

sub handles_content_type {
  my ($self, $type) = @_;
  return _eval_ctype($self->config->{content_types}, $type);
}

=head2 set_globals

  $site->set_globals($r, $handler);

Given C<< $r >> and an HTML::Mason::ApacheHandler or
HTML::Mason::CGIHandler, install global variables into its
interpreter.

=cut

sub set_globals {
  my ($self, $r, $handler) = @_;

  my %c = CGI::Cookie->fetch($r);
  # blurgh, work around bustedness in CGIHandler
  %c or %c = CGI::Cookie->parse($ENV{COOKIE});

  for my $var (keys %{ $self->config->{globals} }) {
    my $arg = $self->config->{globals}->{$var};
    my $gclass = Scalar::Util::blessed($arg);
    if ($gclass eq 'cookie') {
      (my $cookie_name = $var) =~ s/^[\$\@%]//;
      my $cookie = $c{$cookie_name};
      if ($cookie and $cookie->value =~ /($arg->{regex})/) {
        my $val = $1;
        warn "set global $var to '$val' from cookie\n";
        $handler->interp->set_global($var => $val);
      } else {
        warn "didn't find cookie '$cookie_name'\n";
      }
      next;
    }
    if ($gclass) {
      my $method = $arg->{method} || 'new';
      my @args = @{ $arg->{args} || [] };
      my $obj = $gclass->$method(@args);
      warn "set global $var to '$obj' from $gclass->$method(@args)\n";
      $handler->interp->set_global($var => $obj);
      next;
    }

    warn "set global $var to '$arg' from site config\n";
    $handler->interp->set_global($var => $arg);
  }
}

=head2 rewrite_path

=cut

sub rewrite_path {
  my ($self, $path) = @_;
  warn "rewriting path: $path\n";
  for my $rule (@{ $self->config->{rewrite} ||= [] }) {
    my ($pattern, $result) = @$rule;
    warn "applying rewrite: $pattern => $result\n";
    if (eval "\$path =~ s,$pattern,$result,") {
      warn "path is now: $path\n";
    }
  }
  return $path;
}

=head2 pre_handle_request

=cut

sub pre_handle_request {
  my $self = shift;
  eval { $self->EVERY::pre_handle_request_hook(@_) };
  $self->aborted || die $@ if $@;
}

=head2 post_handle_request

=cut

sub post_handle_request {
  my $self = shift;
  eval { $self->EVERY::post_handle_request_hook(@_) };
  $self->aborted || die $@ if $@;
}

=head2 abort

=cut

sub abort { die $ABORT }

=head2 aborted

=cut

sub aborted {
  return unless $@;
  if ($@) {
    return 1 if $@ eq $ABORT;
    die $@;
  }
}

=head2 handle_error

=cut

# CGI::Carp qw(fatalsToBrowser) doesn't work here for some
# reason (or in Site/Server.pm, or importing into HTML::Mason::Commands)
sub handle_error {
  shift;
  print @_;
  die @_;
}

=head1 HOOKS

=head2 pre_handle_request_hook

=head2 post_handle_request_hook

=cut

=head1 AUTHOR

Hans Dieter Pearcey, C<< <hdp at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-html-mason-site at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=HTML-Mason-Site>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc HTML::Mason::Site

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/HTML-Mason-Site>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/HTML-Mason-Site>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=HTML-Mason-Site>

=item * Search CPAN

L<http://search.cpan.org/dist/HTML-Mason-Site>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2006 Hans Dieter Pearcey, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of HTML::Mason::Site
