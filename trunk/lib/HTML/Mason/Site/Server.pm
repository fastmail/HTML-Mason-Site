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

use URI::Escape;
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
  return $m;
}

=head2 handle_request

See L<HTTP::Server::Simple::Mason/handle_request>.  Hands
off to a CGIHandler configured per C<<
$server->site->mason_config >>, unless the site declines
based on content-type, in which case content is served
statically.

=cut

sub handle_request {
  my $self = shift;
  my ($cgi) = @_;

  $self->content_type(undef);
  
  my $path = File::Spec->canonpath(
    uri_unescape($cgi->url(-absolute => 1, -path_info => 1)),
  );

  my $content_type;

 CONTENT_TYPE: {
    for my $dir ($self->site->comp_root) {
      next unless -f "$dir$path";
      $content_type = eval { $Mime->mimeTypeOf($path)->type }
        || $Magic->checktype_filename($path);
#      warn "considering $dir$path: $content_type\n";

#      if ($content_type eq 'text/directory') {
#        $path .= (grep { -f "$dir$path/$_" } qw(index.mhtml index.html index))[0];
#        redo CONTENT_TYPE;
#      }
      
      unless ($self->site->handles_content_type($content_type)) {
        warn "static: $dir$path\n";
        my $content = io("$dir$path")->all;
        print "HTTP/1.1 200 OK\n";
        print "Content-type: $content_type\n";
        print "Content-length: " . length($content) . "\n\n";
        print $content;
        return;
      }
      last;
    }
  }

  if ($content_type) {
    warn "dynamic: $path; content_type: $content_type\n";
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
  my @dirs = ($self->site->comp_root, qw(conf lib perl-lib));
  return if fork;
  close STDIN;
  open STDIN, '</dev/null';
  close STDOUT;
  open STDOUT, '>/dev/null';
  my $watcher = File::Modified->new;
  my %added;
  while (1) {
    exit if getppid == 1;
    if (my @changed = $watcher->changed) {
      $watcher->update;
      warn "changed files:\n";
      warn "  $_\n" for @changed;
      warn "reloading.\n";
      kill 1 => $ppid;
    }
    if (my @files = grep { !$added{$_}++ }
          File::Find::Rule
              ->file->name($arg->{regex})
                ->in(@dirs)) {
      warn "adding files: @files\n";
      $watcher->addfile(@files);
    }
    sleep 1;
  }
}

1;
