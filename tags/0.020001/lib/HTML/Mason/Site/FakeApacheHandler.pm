package HTML::Mason::Site::FakeApacheHandler;

use base qw(HTML::Mason::FakeApacheHandler);
use HTML::Mason::Site::Handler '-all';

# meaningless to CGI, but accept it for ease-of-use
__PACKAGE__->valid_params(
  decline_dirs => { default => 1 },
);

=head1 NAME

HTML::Mason::Site::FakeApacheHandler

=head1 DESCRIPTION

Child of HTML::Mason::FakeApacheHandler with HTML::Mason::Site::Handler mixed in.

=cut

1;
