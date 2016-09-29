#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);

use Test::More tests    => 17;
use Encode qw(decode encode);


BEGIN {
    use_ok 'DR::Tnt::FullCb';
    use_ok 'DR::Tnt::Test';
    use_ok 'AE';
    tarantool_version_check(1.6);
}

my $ti = start_tarantool
    -lua    => 't/040-full/lua/easy.lua';
isa_ok $ti => DR::Tnt::Test::TntInstance::, 'tarantool';

diag $ti->log unless
    ok $ti->is_started, 'test tarantool started';

for (+note 'easy connect') {
    my $c = new DR::Tnt::FullCb
        driver          => 'sync',
        host            => 'localhost',
        port            => $ti->port,
        user            => 'testrwe',
        password        => 'test',
        connector_class => 'DR::Tnt::LowLevel::Connector::AE',
    ;
    isa_ok $c => DR::Tnt::FullCb::, 'connector created';

    $c->restart(
        sub {
            my ($code, $message, @args) = @_;
            return unless is $code, 'OK', 'connected';
            is $c->state, 'ready', 'state';
        }
    );

}
for (+note 'lua_dir is present') {
    my $c = new DR::Tnt::FullCb
        driver          => 'sync',
        host            => 'localhost',
        port            => $ti->port,
        user            => 'testrwe',
        password        => 'test',
        connector_class => 'DR::Tnt::LowLevel::Connector::AE',
        lua_dir         => 't/040-full/lua/start'
    ;
    isa_ok $c => DR::Tnt::FullCb::, 'connector created';

    $c->restart(
        sub {
            my ($code, $message, @args) = @_;
            return unless is $code, 'OK', 'connected';
            is $c->state, 'ready', 'state';
        }
    );
    $c->request(call_lua => 'box.session.storage.rettest', 1, sub {
        is $_[0], 'OK', 'status';
        is_deeply $_[2], [[ test => 2 ] ], 'response';
    });
    
    $c->request(select => '_space', 'primary', 280, sub {
        is $_[0], 'OK', 'status';
        is_deeply [ @{ $_[2][0] }[0,2] ], [ 280, '_space'], 'response';
    });
    
    $c->request(select => '_space', 'primary1', 280, sub {
        is $_[0], 'ER_NOINDEX', 'status';
    });

    $c->request(select => '_spacei1', 'primary', 280, sub {
        is $_[0], 'ER_NOSPACE', 'status';
    });
}

