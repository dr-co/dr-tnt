use utf8;
use strict;
use warnings;

package DR::Tnt::Proto;
use Carp;
use MIME::Base64;

use constant TNT_CODE               => 0x00;
use constant TNT_SYNC               => 0x01;
use constant TNT_SCHEMA_ID          => 0x05;
use constant TNT_SPACE_ID           => 0x10;
use constant TNT_INDEX_ID           => 0x11;
use constant TNT_LIMIT              => 0x12;
use constant TNT_OFFSET             => 0x13;
use constant TNT_ITERATOR           => 0x14;
use constant TNT_KEY                => 0x20;
use constant TNT_TUPLE              => 0x21;
use constant TNT_FUNCTION           => 0x22;
use constant TNT_USERNAME           => 0x23;
use constant TNT_EXPRESSION         => 0x27;
use constant TNT_OPS                => 0x28;
use constant TNT_DATA               => 0x30;
use constant TNT_ERROR              => 0x31;
use constant TNT_CODE_SELECT        => 0x01;
use constant TNT_CODE_INSERT        => 0x02;
use constant TNT_CODE_REPLACE       => 0x03;
use constant TNT_CODE_UPDATE        => 0x04;
use constant TNT_CODE_DELETE        => 0x05;
use constant TNT_CODE_CALL          => 0x06;
use constant TNT_CODE_AUTH          => 0x07;
use constant TNT_CODE_EVAL          => 0x08;
use constant TNT_CODE_UPSERT        => 0x09;
use constant TNT_CODE_PING          => 0x40;
use constant TNT_RES_OK             => 0x00;
use constant TNT_RES_ERROR          => 0x8000;




sub parse_greeting {
    my ($str) = @_;
    croak "strlen is not 128 bytes" unless $str and 128 == length $str;

    my $salt = decode_base64(substr $str, 64, 44);
    my $grstr = substr $str, 0, 64;

    my ($title, $v, $pt, $uid) = split /\s+/, $grstr, 5;

    return {
        salt    => $salt,
        gr      => $grstr,
        title   => $title,
        version => $v,
        uuid    => $uid,
        proto   => $pt,
    }
}
1;
