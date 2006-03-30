package HTML::Mason::Site::Handler;

use strict;
use warnings;

# ::Fast has no separate get/set, and thus is easily exportable
use base qw(Class::Accessor::Fast);

my @HANDLERS;
BEGIN { @HANDLERS = qw(handle_request handle_comp handle_cgi_object) }
BEGIN { __PACKAGE__->mk_accessors('site') }
BEGIN {
  for my $handler (@HANDLERS) {
    no strict 'refs';
    *$handler = sub {
      my $self = shift;
      unless ($self->site) {
        require Carp;
        Carp::croak("$handler called with no site defined");
      }
      return $self->__NEXT__($handler => @_);
    };
  }
}

use Sub::Exporter -setup => {
  exports => [ qw(site request_args __NEXT__), @HANDLERS ],
};

# NEXT.pm has problems here for reasons I can't figure out
# right now, and I can't use SUPER:: because it's a mixin
sub __NEXT__ {
  my $self = shift;
  no strict 'refs';
  my $next = ${ (ref($self) || $self) . "::ISA" }[0];
  my $meth = $next . "::" . shift;
  return $self->$meth(@_);
}

=head1 NAME

HTML::Mason::Site::Handler

=head1 DESCRIPTION

Mixin for HTML::Mason::ApacheHandler and ::CGIHandler.

=head2 handle_request

=head2 handle_comp

=head2 handle_cgi_object

Overridden to check for C<< site >>.

=head2 request_args

Overridden to call L<set_globals|HTML::Mason::Site/set_globals>.

=cut

# XXX this might happen more than once; should we move
# set_globals elsewhere?

sub request_args {
  my ($self, $r) = @_;

  $self->site->set_globals($r, $self);

  return $self->__NEXT__(request_args => $r);
}

package HTML::Mason::Site::CGIHandler;

use base qw(HTML::Mason::CGIHandler);
use HTML::Mason::Site::Handler '-all';

package HTML::Mason::Site::ApacheHandler;

use base qw(HTML::Mason::ApacheHandler);
use HTML::Mason::Site::Handler '-all';

1;
