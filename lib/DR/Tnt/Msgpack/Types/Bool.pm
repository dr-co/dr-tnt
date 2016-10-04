use utf8;
use strict;
use warnings;

package DR::Tnt::Msgpack::Types::Bool;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;
use Scalar::Util ();

sub new {
    my ($class, $value) = @_;

    $value = $value ? 1 : 0;
    bless \$value => ref($class) || $class;
}

sub TO_MSGPACK {
    my ($self) = @_;
    return pack 'C', 0xC3 if $$self;
    return pack 'C', 0xC2;
}

sub TO_JSON {
    my ($self) = @_;
    return $$self ? 'true' : 'false';
}

1;
