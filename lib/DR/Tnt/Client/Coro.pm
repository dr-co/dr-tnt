use utf8;
use strict;
use warnings;

package DR::Tnt::Client::Coro;
use Coro;
use Carp;
use Mouse;
use DR::Tnt::FullCb;
use List::MoreUtils 'any';

with 'DR::Tnt::Role::Logging';

has host                => is => 'ro', isa => 'Str', required => 1;
has port                => is => 'ro', isa => 'Str', required => 1;
has user                => is => 'ro', isa => 'Maybe[Str]';
has password            => is => 'ro', isa => 'Maybe[Str]';
has reconnect_interval  => is => 'ro', isa => 'Maybe[Num]';
has hashify_tuples      => is => 'ro', isa => 'Bool', default => 0;
has lua_dir             => is => 'ro', isa => 'Maybe[Str]';

has raise_error         => is => 'ro', isa => 'Bool', default => 1;

has _fcb =>
    is      => 'ro',
    isa     => 'DR::Tnt::FullCb',
    handles => [ 'last_error' ],
    builder => sub {
        my ($self) = @_;
        DR::Tnt::FullCb->new(
            logger              => $self->logger,
            host                => $self->host,
            port                => $self->port,
            user                => $self->user,
            password            => $self->password,
            reconnect_interval  => $self->reconnect_interval,
            hashify_tuples      => $self->hashify_tuples,
            lua_dir             => $self->lua_dir,
            driver              => 'async',
        )
    };

sub request {
    my ($self, @args) = @_;

    my $cb = Coro::rouse_cb;
    
    my $m = $args[0];

    splice @args, 0, 1, 'select' if $m eq 'get';

    $self->_fcb->request(@args, $cb);
    my ($status, $message, $resp) = Coro::rouse_wait $cb;

   
    unless ($status eq 'OK') {
        return 0 if $m eq 'ping';
        return undef unless $self->raise_error;
        croak $message;
    }

    goto $m;

    ping:
    auth:
        return 1;

    get:
    update:
    insert:
    replace:
    delele:
        $self->_log(error =>
            'Method %s returned more than one result (%s items)',
            $m,
            scalar @$resp
        ) if @$resp > 1;
        return $resp->[0];

    select:
    call_lua:
    eval_lua:
        return $resp;
}

my @methods = qw(
    select
    update
    insert
    replace
    delele
    call_lua
    eval_lua
    ping
    auth
    get
);

for my $m (@methods) {
    no strict 'refs';
    *{ $m } = sub {
        splice @_, 1, 0, $m; 
        goto \&request;
    }
}

__PACKAGE__->meta->make_immutable;
