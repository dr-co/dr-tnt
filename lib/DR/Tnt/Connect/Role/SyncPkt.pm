use utf8;
use strict;
use warnings;

package DR::Tnt::Connect::Role::SyncPkt;

sub BUILD {
    my ($self) = @_;
    $self->{sync} = {};
    $self->{last_sync} = 0;
}

sub next_sync {
    my ($self) = @_;
    for (my $s = $self->{last_sync} + 1;; $s++) {
        next if exists $self->{sync}{$s};
        return $self->{last_sync} = $s;
    }
}

1;
