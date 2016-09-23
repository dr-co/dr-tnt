use utf8;
use strict;
use warnings;

package DR::Tnt::LowLevel::Connector::AE;

use Mouse;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

extends 'DR::Tnt::LowLevel::Connector';

sub _connect {
    my ($self, $cb) = @_;


    tcp_connect
        $self->ll->host,
        $self->ll->port,
        sub {
            my ($fh) = @_;
            unless ($fh) {
                $cb->(ER_CONNECT => $!);
                return;
            }
            $self->fh(AnyEvent::Handle->new(fh => $fh));
            $cb->(OK => 'Connected');
        }
    ;

    return;
}

sub _handshake {
    my ($self, $cb) = @_;

    $self->fh->push_read(chunk => 128, sub {

        my ($fh, $chunk) = @_;
        unless ($fh) {
            $cb->(ER_HANDSHAKE => $!);
            return;
        }

        $cb->(OK => 'handshake was read', $chunk);
        undef $cb;
        $self->fh->on_read(sub {
            my ($handle) = @_;
            return unless $handle;

            warn sprintf 'read %s bytes', length $handle->rbuf;
            $self->rbuf($self->rbuf . $handle->rbuf);
            $handle->{rbuf} = '';
            $self->check_rbuf;
        });
    });
}


sub _swrite {
    my ($self, $pkt, $cb) = @_;

    $self->fh->push_write($pkt);
    $cb->(OK => 'packet was queued to send');
    return;
}


__PACKAGE__->meta->make_immutable;
