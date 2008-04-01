#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'HTML::Mason::Site' );
}

diag( "Testing HTML::Mason::Site $HTML::Mason::Site::VERSION, Perl $], $^X" );
