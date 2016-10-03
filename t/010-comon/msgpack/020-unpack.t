#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);

use Test::More tests    => 27;
use Encode qw(decode encode);


BEGIN {
    use_ok 'DR::Tnt::Msgpack';
}

is msgunpack(msgpack(undef)), undef, 'undef';
for (0, 0x7E, 0x7F) {
    is msgunpack(msgpack($_)), $_, "num $_";
}
for (0x7F + 1, 0xFE, 0xFF) {
    is msgunpack(msgpack($_)), $_, "num $_";
}
for (0xFF + 1, 0xFFFE, 0xFFFF) {
    is msgunpack(msgpack($_)), $_, "num $_";
}
for (0xFFFF + 1, 0xFFFF_FFFE, 0xFFFF_FFFF) {
    is msgunpack(msgpack($_)), $_, "num $_";
}
for (0xFFFF_FFFF + 1, 0xFFFF_FFFF * 25) {
    is msgunpack(msgpack($_)), $_, "num $_";
}
for (-1, -0x1F, -0x20) {
    is msgunpack(msgpack($_)), $_, "num $_";
}
for (-0x21, -0x7FF, -0x7FF - 1, -0x7FFF - 2) {
    is msgunpack(msgpack($_)), $_, "num $_";
}
for (-0x7FFF - 2, -0x7FFF_FFFF, -0x7FFF_FFFF * 2, -0x7FFF_FFFF * 25) {
    is msgunpack(msgpack($_)), $_, "num $_";
}

