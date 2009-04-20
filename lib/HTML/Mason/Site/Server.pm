package HTML::Mason::Site::Server;

use strict;
use warnings;

use base qw(HTTP::Server::Simple::Mason
            Class::Accessor
          );
# for some reason, without this require,
# HTTP::Server::Simple does not fully load (?!)
require HTTP::Server::Simple;

use IO::All;

use File::Modified;
use File::Find::Rule;

use File::Spec;
use File::MMagic;
use MIME::Types;
my $Mime  = MIME::Types->new;
my $Magic = File::MMagic->new;

BEGIN {
  __PACKAGE__->mk_accessors(
    qw(site content_type),
  );
}

sub new {
  my ($class, $port, $arg) = @_;
  my $self = $class->SUPER::new($port);

  # $self->{__PACKAGE__}{alarm} = $arg->{alarm} || 0;
  # alarm $self->{__PACKAGE__}{alarm};

  return $self;
}

=head1 NAME

HTML::Mason::Site::Server

=head1 DESCRIPTION

Helper class for msite(1).

=head1 METHODS

=head2 site

Accessor for the associated HTML::Mason::Site object.

=head2 net_server

See L<HTTP::Server::Simple::Mason/net_server>.  Overridden to fork for
each request (because of Apache::Session locking issues).

=head2 mason_config

See L<HTML::Mason::Site/mason_config>.

=cut

use HTML::Mason::Site::Server::NetServer;
sub net_server { __PACKAGE__ . "::NetServer" }

sub mason_config {
  return shift->site->mason_config;
}

=head2 default_mason_config

See <HTTP::Server::Simple::Mason/default_mason_config>.
Overridden to be empty (no default escaping).

=cut

# override the default of html escaping everything
sub default_mason_config { () }

=head2 handler_class

Use HTML::Mason::Site::FakeApacheHandler.

=cut

use HTML::Mason::Site::Handler;
sub handler_class { 'HTML::Mason::Site::FakeApacheHandler' }

# this unfortunateness is to make MasonX::Request::WithApacheSession choose
# the right superclass
$HTML::Mason::ApacheHandler::VERSION
  = 0;
$HTML::Mason::CGIHandler::VERSION
  = 1;

=head2 new_handler

See L<HTTP::Server::Simple::Mason/new_handler>.  Overridden
to be smarter about content_type detection and output.

=cut

sub new_handler {
  my $self = shift;
  my $m = $self->SUPER::new_handler(@_);
  my $output = { $m->interp->delayed_object_params('request') }->{out_method};
  $m->interp->delayed_object_params(
    'request', out_method => sub {
      if ($self->content_type) {
        my $r = HTML::Mason::Request->instance->cgi_request;
        $r->content_type || $r->content_type($self->content_type);
      }
      $output->(@_);
    },
  );
  $m->site($self->site);
  return $m;
}

=head2 handle_request

See L<HTTP::Server::Simple::Mason/handle_request>.  Hands
off to a CGIHandler configured per C<<
$server->site->mason_config >>, unless the site declines
based on content-type, in which case content is served
statically.

=cut

sub _handle_static {
  my ($self, $filename, $content_type) = @_;
  #print STDERR "static: $filename\n";
  my $content = io("$filename")->all;
  print "HTTP/1.1 200 OK\n";
  print "Content-type: $content_type\n";
  print "Content-length: " . length($content) . "\n\n";
  print $content;
}

sub _content_type_of {
  my ($self, $filename) = @_;
  return eval { $Mime->mimeTypeOf($filename)->type }
    || $Magic->checktype_filename($filename);
}

sub handle_request {
  my $self = shift;
  my ($cgi) = @_;

  # alarm 0;

  $self->content_type(undef);
  # this should probably be done by HTTP::Server::Simple, but... workaround for
  # now
  $cgi->path_info(URI::Escape::uri_unescape($cgi->path_info));
  
  my $path = $self->site->rewrite_path($cgi->path_info);
  $cgi->path_info($path);

  my $index_name = $self->site->config->{index_name} || 'index.mhtml';

  my $interp = $self->mason_handler->interp;

  # stolen from HTTP::Server::Simple::Mason and modifieda
  if (! $interp->comp_exists($path)
        && $interp->comp_exists("$path/$index_name")) {
    $path .= "/$index_name";
    $cgi->path_info($path);
  }
  $ENV{PATH_INFO} = $cgi->path_info;

  my $content_type;
  
  for my $root (
    (map { [ $_, sub { 1 } ] }
      @{ $self->site->config->{static_roots} || [] }),
    (map { [ $_, sub { !$self->site->handles_content_type(shift) } ] }
      $self->site->comp_roots),
  ) {
    my ($dir, $static_ok) = @$root;
    my $filename = File::Spec->catfile($dir, $path);
    next unless -f $filename;
    $content_type = $self->_content_type_of($filename);
    
    if ($static_ok->($content_type)) {
      $self->_handle_static($filename, $content_type);
      # alarm($self->{'HTML::Mason::Site::Server'}{alarm} || 0);
      return;
    }
    last;
  }

  # lame
  $content_type = 'text/html' if $path =~ /\.mhtml$/;

  if ($content_type) {
    print STDERR "dynamic: $path; content_type: $content_type\n";
    $self->content_type($content_type);
  }

  {
    $self->site->pre_handle_request(@_);
    last if $self->site->aborted;

    $self->SUPER::handle_request(@_);

    $self->site->post_handle_request(@_);
    last if $self->site->aborted;
  }

  # $self->cleanup
  # return values are not meaningful
  # alarm($self->{'HTML::Mason::Site::Server'}{alarm} || 0);
}

=head2 handle_error

See L<HTTP::Server::Simple::Mason>.  Hands off to C<site>.

=cut

sub handle_error {
  return shift->site->handle_error(@_);
}

=head2 start_restarter

=cut

sub start_restarter {
  my ($self, $arg) = @_;
  my $ppid = $$;
  # XXX formalize this
  my @dirs = (
#    $self->site->comp_roots,
    qw(conf etc lib perl-lib),
  );
  return if fork;
  close STDIN;
  open STDIN, '</dev/null';
  close STDOUT;
  open STDOUT, '>/dev/null';
  my $watcher = File::Modified->new(
    Files => $arg->{watch} || [],
  );
  my %added;
  while (1) {
    exit if getppid == 1;
    if (my @changed = $watcher->changed) {
      $watcher->update;
      warn "changed files:\n";
      warn "  $_\n" for @changed;
      warn "reloading.\n";
      kill 1 => $ppid;
      next;
    }
    if (my @files = grep {
      !$added{$_}++
    } File::Find::Rule->or(
        File::Find::Rule->directory->name('.svn')->prune->discard,
        File::Find::Rule->file->name($arg->{regex})
      )->in(@dirs)) {
      warn "adding files: @files\n";
      $watcher->addfile(@files);
      next;
    }
    sleep 2;
  }
}

1;
