use utf8;
use strict;
use warnings;

package DR::Tnt::Connect::Sync;
use Mouse;
use IO::Socket::INET;
use IO::Socket::UNIX;
use Carp;

with 'DR::Tnt::Proto';

sub connect {
    my ($class, %opts) = @_;

    my ($host, $port, $login, $password) = $class->_dsn(%opts);

    my $self = $class->new({
        host        => $host,
        port        => $port,
        login       => $login,
        password    => $password,
    });

    $self;
}




sub _connect_reconnect {
    my ($self) = @_;
    my $fh;

    if ($self->host eq 'unix/') {
        $fh = IO::Socket::UNIX->new(

        );
    } else {
        $fh = IO::Socket::INET->new(
            PeerHost => $self->host,
            PeerPort => $self->port,
            Proto    => 'tcp',
            (($^O eq 'MSWin32') ? () : (ReuseAddr => 1)),
        );
    }
    $self->{fh} = $fh;
}

sub fh {
    my ($self) = @_;
    $self->_connect_reconnect unless $self->{fh};
    $self->{fh};
}




1;
