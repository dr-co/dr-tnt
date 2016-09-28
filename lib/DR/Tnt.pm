use utf8;
use strict;
use warnings;

package DR::Tnt;
use Mouse;

require DR::Tnt::LowLevel;

use Mouse::Util::TypeConstraints;

enum TntDrivers => [ 'sync', 'ae', 'coro' ];

has driver      => is => 'ro', 



__PACKAGE__->meta->make_immutable;
