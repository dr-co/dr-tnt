use utf8;
use strict;
use warnings;

package DR::Tnt::Client::Coro;
use Carp;
use Coro;
use Mouse;

sub driver { 'async' }

sub request {
    my ($self, @args) = @_;

    my $cb = Coro::rouse_cb;
    
    my $m = $args[0];

    splice @args, 0, 1, 'select' if $m eq 'get';

    $self->_fcb->request(@args, $cb);
    my ($status, $message, $resp) = Coro::rouse_wait $cb;

    return $self->_response($m, $status, $message, $resp);
}

with 'DR::Tnt::Client::Role::LikeSync';

__PACKAGE__->meta->make_immutable;
