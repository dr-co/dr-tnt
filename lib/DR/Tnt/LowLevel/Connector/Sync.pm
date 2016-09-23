use utf8;
use strict;
use warnings;

package DR::Tnt::LowLevel::Connector::Sync;
use Mouse;
use IO::Socket::INET;
use IO::Socket::UNIX;

extends 'DR::Tnt::LowLevel::Connector';

sub _connect {
    my ($self, $cb) = @_;


    my $fh;
    
    if ($self->ll->host eq 'unix' or $self->ll->host eq 'unix/') {
        $fh = IO::Socket::UNIX->new(
        )
    } else {
        $fh = IO::Socket::INET->new(
            PeerHost        => $self->ll->host,
            PeerPort        => $self->ll->port,
            Proto           => 'tcp',
        );
    }

    if ($fh) {
        $self->fh($fh);
        $cb->(OK => 'Socket connected');
        return;
    }

    $cb->(error =>
        sprintf 'Can not connect to %s:%s', $self->ll->host, $self->ll->port);
    return;
}
    
sub _handshake {
    my ($self, $cb) = @_;
    $self->sread(128, sub {
        my ($state, $message, $hs) = @_;
        unless ($state eq 'OK') {
            pop;
            goto \&$cb;
        }
        $cb->(OK => 'handshake was read', $hs);
    });
}

sub _sread {
    my ($self, $len, $cb) = @_;

    my $blob = '';

    my $done = sysread $self->fh, $blob, $len, length $blob;
    unless (defined $done) {
        $cb->(ER_SOCKET_READ => $!);
        return;
    }

    $cb->(OK => 'sread done', $blob);
    return;
}

sub _swrite {
    my ($self, $pkt, $cb) = @_;

    while (1) {
        my $done = syswrite $self->fh, $pkt;
        unless (defined $done) {
            $cb->(ER_SOCKET_WRITE => $!);
            return;
        }
        if ($done == length $pkt) {
            $cb->(OK => 'swrite done');
            return;
        }
        substr $pkt, 0, $done, '' if $done;
    }
}

around wait_response => sub {
    my ($orig, $self, $sync, $cb) = @_;
    my $cbtouch;
    $self->$orig($sync, sub {
        $cbtouch = 1;
        goto \&$cb;
    });

    while (!$cbtouch) {
        $self->sread(4096 => sub {
            my ($state, $message, $blob) = @_;
            goto \&$cb unless $state eq 'OK';
            $self->rbuf($self->rbuf . $blob);
            $self->check_rbuf;
        });
    }
};

__PACKAGE__->meta->make_immutable;
