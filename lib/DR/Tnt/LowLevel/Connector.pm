use utf8;
use strict;
use warnings;

package DR::Tnt::LowLevel::Connector;
use Mouse;
use DR::Tnt::Proto;
use List::MoreUtils 'any';
use feature 'state';
use Carp;
use Data::Dumper;

has fh  =>
    is      => 'rw',
    isa     => 'Maybe[Object]',
    trigger => sub {
        my ($self) = @_;
        $self->_active_sync({});
        my $list = $self->_watcher;
        $self->_watcher({});
        for my $sync (keys %$list) {
            for my $cb (@{ $list->{$sync} }) {
                $cb->(ER_LOST_CONNECTION => 'Connection lost', $sync);
                return;
            }
        }
    };

has ll  => is => 'ro', isa => 'DR::Tnt::LowLevel', weak_ref => 1, required => 1;

has greeting        => is => 'rw', isa => 'Maybe[HashRef]';
has state           => is => 'rw', isa => 'Str', default => 'init';
has rbuf            => is => 'rw', isa => 'Str', default => '';
has _last_sync      => is => 'rw', isa => 'Int', default => 0;
has _active_sync    => is => 'rw', isa => 'HashRef', default => sub {{}};
has _watcher        => is => 'rw', isa => 'HashRef', default => sub {{}};

sub next_sync {
    my ($self) = @_;

    for (my $sync = $self->_last_sync + 1;; $sync++) {
        $sync = 1 if $sync > 0x7FFF_FFFF;
        next if exists $self->_active_sync->{ $sync };
        $self->_last_sync($sync);
        $self->_active_sync->{ $sync } = 1;
        return $sync;
    }
}

sub connect {
    my ($self, $cb) = @_;

    if (any { $_ eq $self->state } 'init') {
        $self->fh(undef);
        $self->state('connecting');
        $self->_connect(sub {
            my ($state) = @_;
            if ($state eq 'OK') {
                $self->state('connected');
            } else {
                $self->state('pause');
                $self->fh(undef);
            }
            goto &$cb;
        });
        return;
    }
    $cb->(fatal => 'can not connect in state: ' . $self->state);
    return;
}

sub handshake {
    my ($self, $cb) = @_;

    unless ($self->state eq 'connected') {
        $self->state('fatal');
        $self->fh(undef);
        $cb->(fatal => 'can not read handshake in state: ' . $self->state);
        return;
    }

    $self->state('handshake');
    $self->greeting(undef);

    $self->sread(128, sub {
        my ($state, $message, $hs) = @_;
        unless ($state eq 'OK') {
            pop;
            goto \&$cb;
        }
        my $greeting = DR::Tnt::Proto::parse_greeting($hs);
        if ($greeting and $greeting->{salt}) {
            $self->greeting($greeting);
            $self->state('ready');
            $cb->(OK => 'handshake was read and parsed');
            return;
        }
        $self->state('pause');
        $cb->(error => 'wrong tarantool handshake');
    });
}

sub send_request {
    my $cb = pop;
    my ($self, $name, @args) = @_;


    if ($self->state eq 'fatal') {
        $cb->(ER_FATAL => 'Can not make new request after fatal error');
        return;
    }

    my $sync = $self->next_sync;
 
    state $r = {
        select      => \&DR::Tnt::Proto::select,
        update      => \&DR::Tnt::Proto::update,
        insert      => \&DR::Tnt::Proto::insert,
        replace     => \&DR::Tnt::Proto::replace,
        delele      => \&DR::Tnt::Proto::del,
        call_lua    => \&DR::Tnt::Proto::call_lua,
        ping        => \&DR::Tnt::Proto::ping,
        auth        => \&DR::Tnt::Proto::auth,
    };

    croak "unknown method $name" unless exists $r->{$name};


    state $ra = {
        auth    => sub {
            my $self = shift;
            return (
                @_,
                $self->ll->user,
                $self->ll->password,
                $self->greeting->{salt},
            );
        }
    };
    
    @args = $ra->{$name}->($self, @args) if exists $ra->{$name};
    
    my $pkt = $r->{$name}->($sync, @args);

    $self->swrite($pkt, sub {
        my ($state) = @_;
        unless ($state eq 'OK') {
            $self->state('pause');
            $self->fh(undef);
            goto \&cb;
        }
        $cb->(OK => 'OK', $sync);
    });
}

sub wait_response {
    my ($self, $sync, $cb) = @_;
    unless (exists $self->_active_sync->{$sync}) {
        $cb->(ER_FATAL => "Request $sync was not sent");
        return;
    }
    if (ref $self->_active_sync->{$sync}) {
        my $resp = delete $self->_active_sync->{$sync};
        $cb->(OK => 'Request was read', $resp);
        return;
    }
    push @{ $self->_watcher->{$sync} } => $cb;
    return;
}

sub swrite {
    my ($self, $pkt, $cb) = @_;
    unless ($self->state eq 'ready') {
        $cb->(ER_NOT_READY => 'Connector is not ready to send requests');
        return;
    }
    unless ($self->fh) {
        $cb->(ER_CONNECTION_ESTABLISH => 'Connection is not established');
        return;
    }
    $self->_swrite($pkt, $cb);
    return;
}
sub sread {
    my ($self, $len, $cb) = @_;
    unless ($self->fh) {
        $cb->(ER_CONNECTION_ESTABLISH => 'Connection is not established');
        return;
    }
    $self->_sread($len, $cb);
    return;
}

sub check_rbuf {
    my ($self) = @_;
    my ($res, $tail) = DR::Tnt::Proto::response($self->rbuf);
    return unless defined $res;
    $self->rbuf($tail);

    my $sync = $res->{SYNC};
    if (exists $self->_watcher->{$sync}) {
        my $list = delete $self->_watcher->{$sync};
        delete $self->_active_sync->{$sync};
        for my $cb (@$list) {
            $cb->(OK => 'Response received', $res);
        }
    }
    return;
}
__PACKAGE__->meta->make_immutable;
