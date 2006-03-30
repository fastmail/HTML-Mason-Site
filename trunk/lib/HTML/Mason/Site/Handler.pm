package HTML::Mason::Site::Handler;

use strict;
use warnings;

use base qw(Class::Accessor);

use NEXT;

__PACKAGE__->mk_accessors(
  qw(site handler_type),
);

for my $handler (qw(handle_request handle_comp handle_cgi_object)) {
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

sub new {
  my $class = shift;
  no strict 'refs';
  my ($next_class) = grep { $_ ne __PACKAGE__ } @{$class . "::ISA"};
  my $meth = $next_class . "::new";
  return $class->$meth(@_);
}

sub request_args {
  my ($self, $r) = @_;

  $self->site->set_globals($r, $self);

  return $self->NEXT::request_args($r);
}

sub handler_type {
  my $self = shift;
  if (@_) {
    my $type = shift;
    my $class = "HTML::Mason::Site::${type}Handler";
    no strict 'refs';
    die "no such site handler class: $class" unless @{ $class . "::ISA" };
    bless $self => $class;
    return $self->_handler_type_accessor($type);
  }
  return $self->_handler_type_accessor;
}

package HTML::Mason::Site::CGIHandler;

use base qw(HTML::Mason::Site::Handler
            HTML::Mason::CGIHandler);

package HTML::Mason::Site::ApacheHandler;

use base qw(HTML::Mason::Site::Handler
            HTML::Mason::ApacheHandler);

1;
