use utf8;
use strict;
use warnings;

package DR::Tnt::Msgpack;
use base qw(Exporter);
our @EXPORT = qw(msgpack msgunpack msgunpack_check msgunpack_utf8);
use Scalar::Util ();
use Carp;
use feature 'state';


sub _msgunpack($$) {
    my ($str, $utf8) = @_;

    return unless defined $str and length $str;

    my $tag = unpack 'C', $str;

    # NULL
    return (undef, 1) if $tag == 0xC0;
    # fix uint
    return ($tag, 1) if $tag <= 0x7F;
    # fix negative
    return (unpack('c', $str), 1) if $tag >= 0xE0;

    state $variant = {
        (0xD0)      => sub {        # int8
            my ($str) = @_;
            return unless length($str) >= 2;
            return (unpack('x[C]c', $str), 2); 
        },
        (0xD1)      => sub {        # int16
            my ($str) = @_;
            return unless length($str) >= 3;
            return (unpack('x[C]s>', $str), 3); 
        },
        (0xD2)      => sub {        # int32
            my ($str) = @_;
            return unless length($str) >= 5;
            return (unpack('x[C]l>', $str), 5); 
        },
        (0xD3)      => sub {        # int64
            my ($str) = @_;
            return unless length($str) >= 9;
            return (unpack('x[C]q>', $str), 9); 
        },




        (0xCC)      => sub {        # uint8
            my ($str) = @_;
            return unless length($str) >= 2;
            return (unpack('x[C]C', $str), 2); 
        },
        (0xCD)      => sub {        # uint16
            my ($str) = @_;
            return unless length($str) >= 3;
            return (unpack('x[C]S>', $str), 3); 
        },
        (0xCE)      => sub {        # uint32
            my ($str) = @_;
            return unless length($str) >= 5;
            return (unpack('x[C]L>', $str), 5); 
        },
        (0xCF)      => sub {        # uint64
            my ($str) = @_;
            return unless length($str) >= 9;
            return (unpack('x[C]Q>', $str), 9); 
        },

    };

    return $variant->{$tag}($str, $utf8) if exists $variant->{$tag};
  

    warn $tag;
    return;

}

sub msgunpack($) {
    my ($str) = @_;
    my ($o, $len) = _msgunpack($str, 0);
    croak 'Input buffer does not contain valid msgpack' unless defined $len;
    return $o;
}

sub msgunpack_utf8($) {
    my ($str) = @_;
    my ($o, $len) = _msgunpack($str, 1);
    croak 'Input buffer does not contain valid msgpack' unless defined $len;
    return $o;
}

sub msgunpack_check($) {
    my ($str) = @_;
    my ($o, $len) = _msgunpack($str, 1);
    return $len // 0;
}

sub msgpack($) {
    my ($v) = @_;

    if (ref $v) {

    } else {
        # numbers
        if (Scalar::Util::looks_like_number $v) {
            if ($v == int $v) {
                if ($v >= 0) {
                    if ($v <= 0x7F) {
                        return pack 'C', $v;
                    } elsif ($v <= 0xFF) {
                        return pack 'CC', 0xCC, $v;
                    } elsif ($v <= 0xFFFF) {
                        return pack 'CS>', 0xCD, $v;
                    } elsif ($v <= 0xFFFF_FFFF) {
                        return pack 'CL>', 0xCE, $v;
                    } else {
                        return pack 'CQ>', 0xCF, $v;
                    }
                }
                if ($v >= - 0x20) {
                    return pack 'c', $v;
                } elsif ($v >= -0x7F - 1) {
                    return pack 'Cc', 0xD0, $v;
                } elsif ($v >= -0x7F_FF - 1) {
                    return pack 'Cs>', 0xD1, $v;
                } elsif ($v >= -0x7FFF_FFFF - 1) {
                    return pack 'Cl>', 0xD2, $v;
                } else {
                    return pack 'Cq>', 0xD3, $v;
                }
            } else {
                return pack 'Cd>', 0xCB, $v;
            }

        } else {
            unless (defined $v) {           # undef
                return pack 'C', 0xC0;
            }
            if (utf8::is_utf8 $v) {
                utf8::encode $v;
            }
            # strings
            if (length($v) <= 0x1F) {
                return pack 'Ca*',
                    (0xA0 | length $v),
                    $v;
            } elsif (length($v) <= 0xFF) {
                return pack 'CCa*',
                    0xD9,
                    length $v,
                    $v;
            } elsif (length($v) <= 0xFFFF) {
                return pack 'CS>a*',
                    0xDA,
                    length $v,
                    $v;
            } else {
                return pack 'CL>a*',
                    0xDB,
                    length $v,
                    $v;
            }

        }
    }
}

1;
