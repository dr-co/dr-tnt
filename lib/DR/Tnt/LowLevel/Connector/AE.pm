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
            $self->fh(new AnyEvent::Handle
                fh          => $fh,
                on_read     => $self->_on_read,
                on_error    => $self->_on_error,
            );

            $cb->(OK => 'Connected');
        }
    ;

    return;
}

sub _on_read {
    my ($self) = @_;
    sub {
        my ($handle) = @_;
        return unless $handle;

        $self->rbuf($self->rbuf . $handle->rbuf);
        $handle->{rbuf} = '';
        $self->check_rbuf;
    };
}

sub _on_error {
    my ($self) = @_;

    sub {
        my ($handle, $fatal, $message) = @_;
        return unless $fatal;

        $self->socket_error($message);
    }
}

sub send_pkt {
    my ($self, $pkt, $cb) = @_;

    $self->fh->push_write($pkt);
    $cb->(OK => 'packet was queued to send');
    return;
}


__PACKAGE__->meta->make_immutable;
