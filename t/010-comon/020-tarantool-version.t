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
}

SKIP: {
    my $v = eval { tarantool_version };
    ok !$@, 'no exception';
    skip "version not found", 1 unless $v;
    like $v => qr{^\d}, 'version ' . $v;
}
