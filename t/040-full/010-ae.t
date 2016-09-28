#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);

use Test::More tests    => 1;
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
        driver          => 'async',
        host            => 'localhost',
        port            => $ti->port,
        user            => 'testrwe',
        password        => 'test',
        connector_class => 'DR::Tnt::LowLevel::Connector::AE',
    ;
    isa_ok $c => DR::Tnt::FullCb::, 'connector created';

    for my $cv (AE::cv) {
        $cv->begin;
        $c->restart(
            sub {
                my ($code, $message, @args) = @_;
                return unless is $code, 'OK', 'connected';
                is $c->state, 'ready', 'state';
                $cv->end;
            }
        );

        my $timer;
        $timer = AE::timer 2, 0, sub {
            $cv->send;
            fail 'timeout is unreached';
            diag $ti->log;
        };

        $cv->recv;
        undef $timer;
    }
}

for (+note 'lua_dir is present') {
    my $c = new DR::Tnt::FullCb
        driver          => 'async',
        host            => 'localhost',
        port            => $ti->port,
        user            => 'testrwe',
        password        => 'test',
        connector_class => 'DR::Tnt::LowLevel::Connector::AE',
        lua_dir         => 't/040-full/lua/start'
    ;
    isa_ok $c => DR::Tnt::FullCb::, 'connector created';

    for my $cv (AE::cv) {
        $cv->begin;
        my $timer = AE::timer 0.5, 0, sub {
            pass 'pause done';
            $cv->end;
        };
        
        
        $cv->begin;
        $c->restart(
            sub {
                my ($code, $message, @args) = @_;
                return unless is $code, 'OK', 'connected';
                is $c->state, 'ready', 'state';
                $cv->end;
            }
        );
        $cv->recv;
    }

    for my $cv (AE::cv) {
        $cv->begin;
        $c->call_lua('box.session.storage.rettest', 1, sub {
            note explain \@_;

            $cv->end;
        });
        $cv->recv;
    }

#     note $ti->log;
}

