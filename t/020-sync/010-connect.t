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

    use_ok 'DR::Tnt::Connect::Sync';
    use_ok 'DR::Tnt::Test';
    tarantool_version_check(1.6);
}

my $tnt = start_tarantool
    port => free_port,
    -lua => 't/020-sync/lua/server.lua';
diag $tnt->log unless ok $tnt->is_started, 'started';


