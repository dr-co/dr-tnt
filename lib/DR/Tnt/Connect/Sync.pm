use utf8;
use strict;
use warnings;

package DR::Tnt::Connect::Sync;
use DR::Tnt::Proto;
use IO::Socket::INET;
use IO::Socket::UNIX;
use Carp;

sub connect {
    my ($class, %opts) = @_;

    my ($host, $port, $login, $password) = DR::Tnt::Proto::dsn(%opts);


    my $self = bless {
        host        => $host,
        port        => $port,
        login       => $login,
        password    => $password,
    }   => ref($class) || $class;
}


1;
