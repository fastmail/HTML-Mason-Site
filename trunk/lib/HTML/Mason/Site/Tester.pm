package HTML::Mason::Site::Tester;

use strict;
use warnings;
use base qw(Class::Accessor::Fast);
use HTML::Mason::Site;
use HTML::Mason::Site::CGIHandler;

use HTTP::Request;
use HTTP::Request::AsCGI;

__PACKAGE__->mk_accessors(qw(site));

=head1 NAME

HTML::Mason::Site::Tester

=head1 SYNOPSIS

  use HTML::Mason::Site::Tester;
  my $tester = HTML::Mason::Site::Tester->new(...);
  my $response = $tester->request("/foo");

=head1 DESCRIPTION

HTML::Mason::Site::Tester objects make it easier to test Mason
applications.  Each tester object is tied to a
HTML::Mason::Site object, and makes requests to it without
needing an external webserver.

=head1 METHODS

=head2 new

  my $tester = HTML::Mason::Site::Tester->new(...);

Create a new tester object associated with a particular site.

The first (mandatory) argument is a hashref which is passed
into HTML::Mason::Site-E<gt>new.

=head2 request

  my $response = $tester->request('/foo?bar=1');

Make a request for the given path.  Returns a HTTP::Response object.

=head2 get

  my $content = $tester->get('/foo?bar=1');

Make a request for the given path, and return the content.

=cut

sub new {
  my $class = shift;
  my $site_config = shift;
  my $site = HTML::Mason::Site->new($site_config);
  $site->set_handler('HTML::Mason::Site::CGIHandler');
  $site->require_modules;

  return bless {
    site    => $site,
  } => $class;
}

sub _request_from_url {
  my ($self, $url) = @_;
  $url = "http://localhost.localdomain$url" if $url =~ m!^/!;
  return HTTP::Request->new( GET => $url );
}

sub request {
  my ($self, $request) = @_;
  $request = $self->_request_from_url($request)
    unless eval { $request->isa('HTTP::Request') };

  my $c = HTTP::Request::AsCGI->new( $request )->setup;
  $self->{site}->handler->handle_request;
  $c->restore;

  my $response = $c->response;
  
  $response->header('Content-Base' => $request->uri);

  return $response;
}

1;
