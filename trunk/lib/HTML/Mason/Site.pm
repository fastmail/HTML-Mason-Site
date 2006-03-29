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

sub _canonical_config {
  my ($self, $arg) = @_;

  $arg->{modules}       ||= [];
  $arg->{content_types} ||= [];

  for my $module (@{ $arg->{modules} }) {
    if (ref $module eq 'HASH') {
      $module->{args} ||= [];
    } else {
      $module = { name => $module, args => [] };
    }
  }

  for my $ctype (@{ $arg->{content_types} }) {
    if (ref $ctype eq 'HASH') {
      $ctype = { not => qr/$ctype->{not}/i };
    } else {
      $ctype = { is => qr/$ctype/i };
    }
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

=head2 comp_root

=cut

sub comp_root {
  my $self = shift;
  my $root = $self->mason_config->{comp_root};
  $root = ref $root eq 'ARRAY' ? $root : [ $root ];
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

sub handles_content_type {
  my ($self, $type) = @_;
  for my $ctype (@STD_CTYPES, @{ $self->config->{content_types} }) {
    return 0 if $ctype->{is}  && $type !~ $ctype->{is};
    return 0 if $ctype->{not} && $type =~ $ctype->{not};
  }
  # default allow, since the default is fairly restrictive
  return 1;
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
