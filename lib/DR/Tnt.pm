use utf8;
use strict;
use warnings;

package DR::Tnt;
use base qw(Exporter);
our $VERSION = '0.01';
our @EXPORT = qw(tarantool);
use List::MoreUtils 'any';

use Carp;
$Carp::Internal{ (__PACKAGE__) }++;

sub tarantool {
    my (%opts) = @_;

    my $driver = delete($opts{driver}) || 'sync';
    
    unless (any { $driver eq $_ } 'sync', 'ae', 'async', 'coro') {
        goto usage;
    }
    goto $opts{driver};


    sync:
        require DR::Tnt::Client::Sync;
        return DR::Tnt::Client::Sync->new(%opts);

    ae:
    async:
        require DR::Tnt::Client::AE;
        return DR::Tnt::Client::AE->new(%opts);

    coro:
        require DR::Tnt::Client::Coro;
        return DR::Tnt::Client::Coro->new(%opts);


    usage:

}


=head1 NAME

DR::Tnt - driver/connector for tarantool

=head1 SYNOPSIS

    use DR::Tnt;    # exports 'tarantool'

    my $tnt = tarantool
                    host                => '1.2.3.4',
                    port                => 567,
                    user                => 'my_tnt_user',
                    password            => '#1@#$JHJH',
                    hashify_tuples      => 1,
                    driver              => 'sync',  # default
                    lua_dir             => '/path/to/my/luas',
                    reconnect_interval  => 0.5
    ;

    my $tuple = $tnt->get(space => 'index', [ 'key' ]);
    my $tuples = $tnt->select(myspace => 'myindex', [ 'key' ], $limit, $offset);

    my $updated = $tnt->update('myspace', [ 'key' ], [ [ '=', 1, 'name' ]]);
    my $inserted = $tnt->insert(myspace => [ 1, 2, 3, 4 ]);
    my $replaced = $tnt->replace(myspace => [ 1, 3, 4, 5 ]);

    my $tuples = $tnt->call_lua('box.space.myspace:select', [ 'key' ]);
    my $hashified_tuples =
        $tnt->call_lua([ 'box.space.myspace:select' => 'myspace' ], ['key' ]);


    my $removed = $tnt->delete(myspace => [ 'key' ]);
   
    my $tuples = $tnt->eval_lua('return 123');
    my $hashify_tuples = $tnt->eval_lua(['return 123' => 'myspace' ]);


=cut
1;
