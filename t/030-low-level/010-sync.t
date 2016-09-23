#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);

use Test::More tests    => 36;
use Encode qw(decode encode);


BEGIN {
    use_ok 'DR::Tnt::LowLevel';
    use_ok 'DR::Tnt::LowLevel::Connector::Sync';

    use_ok 'DR::Tnt::Test';
    tarantool_version_check(1.6);
}

my $ti = start_tarantool
    -lua    => 't/030-low-level/lua/easy.lua';
isa_ok $ti => DR::Tnt::Test::TntInstance::, 'tarantool';
ok $ti->is_started, 'test tarantool started';

my $c = new DR::Tnt::LowLevel
    host            => 'localhost',
    port            => $ti->port,
    user            => 'bla',
    password        => 'ble',
    connector_class => 'DR::Tnt::LowLevel::Connector::Sync',
;
isa_ok $c => DR::Tnt::LowLevel::, 'Low level connector';
is $c->connector_class, 'DR::Tnt::LowLevel::Connector::Sync', 'connector_class';
is $c->reconnect_period, undef, 'reconnect_period is undefined';
ok !$c->reconnect_always, 'do not reconnect_always';
isa_ok $c->connector, DR::Tnt::LowLevel::Connector::Sync::, 'connector';

$c->connect(
    sub {
        my ($code, $message, @args) = @_;
        return unless is $code, 'OK', 'connected';
        is $c->connector->state, 'connected', 'state';
        ok $c->connector->fh, 'fh';
    }
);

$c->handshake(
    sub {
        my ($code, $message, @args) = @_;
        return unless is $code, 'OK', 'handshake is read';
        is $c->connector->state, 'ready', 'state';
        ok $c->connector->fh, 'fh';
    }
);

$c->send_request(ping => sub {
   my ($code, $message, $sync) = @_;
   is $code, 'OK', 'ping was send';
   is $c->connector->state, 'ready', 'state';
   is $sync, 1, 'first request has sync = 1';
   ok exists $c->connector->_active_sync->{$sync}, 'active sync';
});

$c->wait_response(1, sub {
    my ($code, $message, $resp) = @_;
    is $code => 'OK', 'ping response';
    isa_ok $resp => 'HASH';
    is $resp->{SYNC}, 1, 'sync';
    is $resp->{CODE}, 0, 'code';
    like $resp->{SCHEMA_ID}, qr{^\d+$}, 'schema_id';
});

note 'schema collision';
$c->send_request(ping => 7000, sub {
   my ($code, $message, $sync) = @_;
   is $code, 'OK', 'ping was send';
   is $c->connector->state, 'ready', 'state';
   isnt $sync, 1, 'next_sync';
   ok exists $c->connector->_active_sync->{$sync}, 'active sync';
    
    $c->wait_response($sync, sub {
        my ($code, $message, $resp) = @_;
        is $code => 'OK', 'ping response';

        isa_ok $resp => 'HASH';
        is $resp->{SYNC}, $sync, 'sync';
        
        ok $resp->{CODE} & 0x8000 , 'code (schema error)';
        like $resp->{ERROR}, qr{Wrong schema version}, 'error text';
        like $resp->{SCHEMA_ID}, qr{^\d+$}, 'schema_id';
        isnt $resp->{SCHEMA_ID}, 7000, 'schema id';
    });
});

