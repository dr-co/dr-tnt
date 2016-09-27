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


sub send_pkt {
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

sub _wait_something {
    my ($self) = @_;

    return unless $self->fh;

    do {
        my $blob = '';
        my $done = sysread $self->fh, $blob, 4096;
        unless (defined $done) {
            # TODO: errors
        }
        $self->rbuf($self->rbuf . $blob);

    } until $self->check_rbuf;
}


after handshake => sub {
    my ($self) = @_;
    $self->_wait_something;
};

after wait_response => sub {
    my ($self) = @_;
    $self->_wait_something;
};


__PACKAGE__->meta->make_immutable;
