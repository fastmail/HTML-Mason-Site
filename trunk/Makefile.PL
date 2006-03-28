#!perl

use strict;
use warnings;
use inc::Module::Install;

name 'HTML-Mason-Site';
author 'Hans Dieter Pearcey <hdp@cpan.org>';
all_from;

build_requires 'Test::More' => 0;

requires 'HTML::Mason'                 => 0;
requires 'YAML::Syck'                  => 0;
requires 'Getopt::Long::Descriptive'   => 0;
requires 'HTTP::Server::Simple::Mason' => '0.09';

auto_install;
WriteAll;
