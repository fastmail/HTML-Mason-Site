#!perl

use strict;
use warnings;
use Object::Array qw(Array);
use HTML::Mason::Site;

use Test::More 'no_plan';

my $e = \&HTML::Mason::Site::_eval_ctype;

my $simple = Array([
  { is => qr<^text/> },
  { not => qr<^text/css$> },
]);

my $nested = Array([
  Array([
    { is => qr<^text/> },
    { is => qr<directory$> },
  ])
]);

is($e->($simple, 'text/html'), 1, "simple match");
is($e->($simple, 'text/css'), '', "simple no-match");

is($e->($nested, 'text/html'), 1, "nested case 1");
is($e->($nested, 'foo/directory'), 1, "nested case 2");
is($e->($nested, 'foo/bar'), '', 'nested no-match');
