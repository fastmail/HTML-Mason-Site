package HTML::Mason::Site::CGIHandler;

use base qw(HTML::Mason::CGIHandler);
use HTML::Mason::Site::Handler '-all';

# meaningless to CGI, but accept it for ease-of-use
__PACKAGE__->valid_params(
  decline_dirs => { default => 1 },
);

=head1 NAME

HTML::Mason::Site::CGIHandler

=head1 DESCRIPTION

Child of HTML::Mason::CGIHandler with HTML::Mason::Site::Handler mixed in.

=cut

1;
