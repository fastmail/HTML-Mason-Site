package HTML::Mason::Site::Server::NetServer;

use strict;
use warnings;

use base qw(Net::Server::Fork
            Class::Accessor::Class
          );

BEGIN { 
  __PACKAGE__->mk_class_accessors(
    'args', 'ssl_args', 'argv',
  );
  __PACKAGE__->args({ proto => 'tcp' });
  __PACKAGE__->ssl_args({});
}

sub run {
  my $class = shift;
  my %arg     = %{ $class->args };
  my %ssl_arg = map { ("SSL_$_" => $class->ssl_args->{$_}) }
    keys %{ $class->ssl_args };

  use Data::Dumper;
  warn Dumper({ @_ }, \%arg, \%ssl_arg);
  return $class->SUPER::run(
    @_,
    %arg,
    %ssl_arg,
  );
}

sub sig_hup {
  my $self = shift;
  exec $^X, $0, @{ $self->argv || [] };
}

=head1 NAME

HTML::Mason::Site::Server::NetServer

=head1 DESCRIPTION

This module exists only to make it possible to use ssl.

You should never have to use it.

=head1 METHODS

=head2 proto

Defaults to 'tcp'.  Set to 'ssl' to use ssl instead.  See
L<Net::Server::Proto>.

=head2 ssl_args

See L<IO::Socket::SSL>.  A hashref passed to C<< run >>;
prepends 'SSL_' to all the key names, so use
e.g. 'cipher_list' instead of 'SSL_cipher_list'.

=head2 run

See L<Net::Server/run>.  Overridden to use C<< proto >> to
determine the protocol.

=cut

1;
