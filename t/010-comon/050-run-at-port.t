#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);

use Test::More tests    => 3;
use Encode qw(decode encode);


BEGIN {
    # Подготовка объекта тестирования для работы с utf8
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'DR::Tnt::Test';
    tarantool_version_check(1.6);
}


my $port = free_port;

my $t = start_tarantool -port => $port, -lua => 't/010-comon/lua/run.lua';
ok $t, 'Instance created';
like $t->log, qr{entering the event loop}, 'tarantool started';

