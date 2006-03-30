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
      my ($next_class) = grep { $_ ne __PACKAGE__ } @{ref($self) . "::ISA"};
      my $meth = $next_class . "::$handler";
      return $self->$meth(@_);
    };
  }
}

use Sub::Exporter -setup => {
  exports => [ qw(site request_args), @HANDLERS ],
};

use NEXT;

=head1 NAME

HTML::Mason::Site::Handler

=head1 DESCRIPTION

Mixin for HTML::Mason::ApacheHandler and ::CGIHandler.

Methods are overridden to call
L<set_globals|HTML::Mason::Site/set_globals> and to check
for the presence of a site.

=cut

sub request_args {
  my ($self, $r) = @_;

  $self->site->set_globals($r, $self);

  return $self->NEXT::request_args($r);
}

package HTML::Mason::Site::CGIHandler;

use base qw(HTML::Mason::CGIHandler);
use HTML::Mason::Site::Handler '-all';

package HTML::Mason::Site::ApacheHandler;

use base qw(HTML::Mason::ApacheHandler);
use HTML::Mason::Site::Handler '-all';

1;
