use utf8;
use strict;
use warnings;

package DR::Tnt::Proto;
use Carp;

sub dsn {
    my %opts = @_;
    my $host        = $opts{-host};
    my $port        = $opts{-port};


    if ($port) {
        if (!$host) {
            if ($port =~ /^\d+$/) {
                $host = '127.0.0.1';
            } else {
                $host = 'unix/';
            }
        }
    } else {
        croak "port is not defined";
    }


    my $login       = $opts{-login}     || $opts{-user};
    my $password    = $opts{-passwd}    || $opts{-password};

    croak "login is not defined"    if $password    and !defined $login;
    croak "password is not defined" if $login       and !defined $password;
    return ($host, $port, $login, $password);
}
1;
