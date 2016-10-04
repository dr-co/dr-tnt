use utf8;
use strict;
use warnings;

package DR::Tnt::Msgpack::Types;
use base 'Exporter';

use DR::Tnt::Msgpack::Types::Int;
use DR::Tnt::Msgpack::Types::Str;
use DR::Tnt::Msgpack::Types::Blob;
use DR::Tnt::Msgpack::Types::Bool;

our %EXPORT_TAGS = (
    'all'     => [
        'mp_int',
        'mp_bool',
        'mp_string',
        'mp_blob',

        'mp_true',
        'mp_false',
    ]
);

our @EXPORT_OK = @{ $EXPORT_TAGS{all} };


sub mp_int($) {
    DR::Tnt::Msgpack::Types::Int->new($_[0]);
}
sub mp_string($) {
    DR::Tnt::Msgpack::Types::Str->new($_[0]);
}
sub mp_blob($) {
    DR::Tnt::Msgpack::Types::Blob->new($_[0]);
}

sub mp_bool($) {
    DR::Tnt::Msgpack::Types::Bool->new($_[0]);
}
sub mp_true() {
    DR::Tnt::Msgpack::Types::Bool->new(1);
}
sub mp_false() {
    DR::Tnt::Msgpack::Types::Bool->new(0);
}

1;
