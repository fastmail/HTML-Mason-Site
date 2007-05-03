#!perl

use strict;
use warnings;

use Test::More 'no_plan';
use HTML::Mason::Site;
use HTML::Mason::Site::FakeApacheHandler;
use CGI;
use HTTP::Request;
use HTTP::Request::AsCGI;
use File::Spec;
use File::Temp;
use File::Path;

my $site = HTML::Mason::Site->new({
  config => './t/site/test.yml',
});
isa_ok $site, 'HTML::Mason::Site';
$site->require_modules;

my $handler = HTML::Mason::Site::FakeApacheHandler->new($site->mason_config);
isa_ok $handler, 'HTML::Mason::Site::FakeApacheHandler';
isa_ok $handler, 'HTML::Mason::CGIHandler';
$handler->site($site);
$site->set_handler($handler);

my $req = HTTP::Request->new(GET => 'http://test.com/index.html?text=hello');
my $stdout;
{
  my $c = HTTP::Request::AsCGI->new($req)->setup;
  my $q = CGI->new;
  $handler->handle_cgi_object($q);
  $stdout = $c->stdout;
}

my $output = join "", $stdout->getlines;
ok $output, "non-empty";
like $output, qr/text=hello/, "got args from query string";
like $output, qr/This is a basic/, "got fixed text";
like $output, qr{Content-Type: text/html}i, "got content-type";
like $output, qr/<body>/, "got autohandler content";

File::Path::rmtree($site->config->{handler}->{data_dir});
