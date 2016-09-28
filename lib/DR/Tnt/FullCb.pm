use utf8;
use strict;
use warnings;

package DR::Tnt::FullCb;
use Mouse;

require DR::Tnt::LowLevel;
use File::Spec::Functions 'catfile', 'rel2abs';
use Carp;
use DR::Tnt::Dumper;
use Mouse::Util::TypeConstraints;

enum DriverType     => [ 'sync', 'async' ];
enum FullCbState    => [ 'init', 'connecting', 'schema', 'ready', 'pause' ];

no Mouse::Util::TypeConstraints;


# internal lua
our %INT_LUA;

{
    my $k;
    while (<DATA>) {
        if (/^\@\@\s*(\S+)\s*$/m) {
            $k = $1;
            $INT_LUA{$k} = '';
            next;
        }

        next unless $k;
        $INT_LUA{$k} .= $_;
    }
}


has host        => is => 'ro', isa => 'Str', required => 1;
has port        => is => 'ro', isa => 'Str', required => 1;
has user        => is => 'ro', isa => 'Maybe[Str]';
has password    => is => 'ro', isa => 'Maybe[Str]';
has driver      => is => 'ro', isa => 'DriverType', required => 1;

has lua_dir     => is => 'ro', isa => 'Maybe[Str]', writer => '_set_lua_dir';

has last_error  => is => 'ro', isa => 'Maybe[ArrayRef]', writer => '_set_last_error';

has state =>
    is          => 'ro',
    isa         => 'FullCbState',
    default     => 'init',
    writer      => '_set_state',
;

has last_schema => is => 'rw', isa => 'Int', default => 0;




has _ll  =>
    is          => 'ro',
    isa         => 'DR::Tnt::LowLevel',
    lazy        => 1,
    builder     => sub {
        my ($self) = @_;
        goto $self->driver;


        my $connector_class;

        async:
            require DR::Tnt::LowLevel::Connector::AE;
            $connector_class = 'DR::Tnt::LowLevel::Connector::AE';
            goto build;

        sync:
            require DR::Tnt::LowLevel::Connector::Sync;
            $connector_class = 'DR::Tnt::LowLevel::Connector::Sync';
            goto build;

        build:
            DR::Tnt::LowLevel->new(
                host            => $self->host,
                port            => $self->port,
                user            => $self->user,
                password        => $self->password,
                connector_class => $connector_class,
            );
    };

sub restart {
    my ($self, $cb) = @_;

    goto $self->state;


    init:
    connecting:
    schema:
    pause:
    ready:
        $self->_set_state('connecting');
        $self->_ll->connect(sub {
            my ($state, $message) = @_;
            unless ($state eq 'OK') {
                $self->_set_last_error([ $state, $message ]);
                $self->_set_state('pause');
                $cb->($state => $message);
                return;
            }

            $self->_ll->handshake(sub {
                my ($state, $message) = @_;
                unless ($state eq 'OK') {
                    $self->_set_last_error([ $state, $message ]);
                    $self->_set_state('pause');
                    $cb->($state => $message);
                    return;
                }



                unless ($self->user and $self->password) {
                    return $self->_preeval_lua($cb);
                }

                $self->_ll->send_request(auth => undef, sub {
                    my ($state, $message, $sync) = @_;
                    unless ($state eq 'OK') {
                        $self->_set_last_error([ $state, $message ]);
                        $self->_set_state('pause');
                        $cb->($state => $message);
                        return;
                    }

                    $self->_ll->wait_response($sync, sub {
                        my ($state, $message, $resp) = @_;
                        unless ($state eq 'OK') {
                            $self->_set_last_error([ $state, $message ]);
                            $self->_set_state('pause');
                            $cb->($state => $message);
                            return;
                        }

                        unless ($resp->{CODE} == 0) {
                            $self->_set_last_error([ ER_BROKEN_PASSWORD =>
                                $resp->{ERROR} // 'Wrong password']
                            );
                            $self->_set_state('pause');
                            $cb->(@{ $self->last_error });
                            return;
                        }
                        $self->_preeval_lua($cb);
                    });
                });
            });
        });
}

has _unsent_lua     => is => 'rw', isa => 'ArrayRef', default => sub {[]};

sub _preeval_lua {
    my ($self, $cb) = @_;

    $self->_unsent_lua([]);

    if ($self->lua_dir) {
        my @lua = sort glob catfile $self->lua_dir, '*.lua';
        $self->_unsent_lua(\@lua);
    }


    $self->_preeval_unsent_lua($cb);
    return;
}

sub _preeval_unsent_lua {
    my ($self, $cb) = @_;

    unless (@{ $self->_unsent_lua  }) {
        $self->_invalid_schema($cb);
        return;
    }
    

    my $lua = shift @{ $self->_unsent_lua };

    if (open my $fh, '<:raw', $lua) {
        local $/;
        my $body = <$fh>;
        $self->_ll->send_request(eval_lua => undef, $body, sub {
            my ($state, $message, $sync) = @_;
            unless ($state eq 'OK') {
                $self->_set_last_error([ $state, $message ]);
                $self->_set_state('pause');
                $cb->($state => $message);
                return;
            }

            $self->_ll->wait_response($sync, sub {
                my ($state, $message, $resp) = @_;
                unless ($state eq 'OK') {
                    $self->_set_last_error([ $state, $message ]);
                    $self->_set_state('pause');
                    $cb->($state => $message);
                    return;
                }
                unless ($resp->{CODE} == 0) {
                    $cb->(ER_INIT_LUA =>
                        sprintf "lua (%s) error: %s",
                        $lua, $resp->{ERROR} // 'Unknown error'
                    );
                    return;
                }
                $self->_preeval_unsent_lua($cb);
            });
        });

    } else {
        $self->_set_last_error(ER_OPEN_FILE => "$lua: $!");
        $self->_set_state('pause');
        $cb->(@{ $self->last_error });
        return;
    }
}


has _sch        => is => 'rw', isa => 'HashRef';
has _spaces     => is => 'rw', isa => 'ArrayRef', default => sub {[]};
has _indexes    => is => 'rw', isa => 'ArrayRef', default => sub {[]};

sub _invalid_schema {
    my ($self, $cb) = @_;
    goto $self->state;


    init:
    pause:
    schema:
        confess "Internal error: _invalid_schema in state " . $self->state;

    connecting:
    ready:
        $self->_set_state('schema');
        $self->_ll->send_request(select => undef, 280, 0, [], undef, undef, 'ALL', sub {
            my ($state, $message, $sync) = @_;
            unless ($state eq 'OK') {
                $self->_set_last_error([ $state, $message ]);
                $self->_set_state('pause');
                $cb->($state => $message);
                return;
            }

            $self->_ll->wait_response($sync, sub {
                my ($state, $message, $resp) = @_;
                unless ($state eq 'OK') {
                        warn $message;
                    $self->_set_last_error([ $state, $message ]);
                    $self->_set_state('pause');
                    $cb->($state => $message);
                    return;
                }



                $self->_spaces($resp->{DATA});
                # TODO: $resp->{CODE}

                $self->_ll->send_request(select => $resp->{SCHEMA_ID},
                                    288, 0, [], undef, undef, 'ALL', sub { 

                    my ($state, $message, $sync) = @_;
                    unless ($state eq 'OK') {
                        $self->_set_last_error([ $state, $message ]);
                        $self->_set_state('pause');
                        $cb->($state => $message);
                        return;
                    }

                    # TODO: $resp->{CODE}
                    $self->_ll->wait_response($sync, sub {
                        my ($state, $message, $resp) = @_;
                        warn $message;
                        unless ($state eq 'OK') {
                            $self->_set_last_error([ $state, $message ]);
                            $self->_set_state('pause');
                            $cb->($state => $message);
                            return;
                        }
                        $self->_indexes($resp->{DATA});

                        $self->_set_schema($resp->{SCHEMA_ID});
                        $self->_set_state('ready');
                        $cb->('OK');
                    });
                });


            });
        });

}

sub _set_schema {
    my ($self, $schema_id) = @_;

    my %sch;

    for (@{ $self->_spaces }) {
        my $space = $sch{ $_->[2] } = {
            id      => $_->[0],
            engine  => $_->[3],
            flags   => $_->[5],
            fields  => $_->[6],
            indexes => {  }
        };

        for (@{ $self->_indexes }) {
            next unless $_->[0] == $space->{id};

            $space->{indexes}{ $_->[2] } = {
                id      => $_->[1],
                type    => $_->[3],
                flags   => $_->[4],
                fields  => [
                    map { { type => $_->[1], no => $_->[0] } } @{ $_->[5] }
                ]
            }
        }
    }
     
    $self->last_schema($schema_id);
    $self->_sch(\%sch);
    $self->_indexes([]);
    $self->_spaces([]);
}

sub tuples {
    my ($self, $resp, $space) = @_;
    $resp;
}

sub call_lua {
    my $cb = pop;
    my ($self, $proc, @args) = @_;

    my $space;
    ($proc, $space) = @$proc if ref $proc;

    $self->_ll->send_request(call_lua => undef, $proc, @args,  sub {
        my ($state, $message, $sync) = @_;

        unless ($state eq 'OK') {
            $self->_set_last_error([ $state, $message ]);
            $self->_set_state('pause');
            $cb->($state => $message);
            return;
        }

        $self->_ll->wait_response($sync, sub {
            my ($state, $message, $resp) = @_;
            unless ($state eq 'OK') {
                $self->_set_last_error([ $state, $message ]);
                $self->_set_state('pause');
                $cb->($state => $message);
                return;
            }
            $cb->(OK => $self->tuples($resp, $space));
        });
    });
}

sub BUILD {
    my ($self) = @_;
    if ($self->lua_dir) {
        croak(sprintf '%s is not a directory', $self->lua_dir)
            unless -d $self->lua_dir;
        $self->_set_lua_dir(rel2abs $self->lua_dir);
    }
}



__PACKAGE__->meta->make_immutable;

__DATA__
@@ perl-driver.schema.lua

local res = {}
for _, ispace in box.space._space:pairs() do
    local space = {
        id          = ispace[1],
        name        = ispace[3],
        engine      = ispace[4],
        flags       = ispace[6],
        format      = ispace[7],
        index       = {}
    }

    for _, iindex in box.space._index:pairs() do
        if iindex[1] == space.id then
            local fields = {}

            for idx, tp in pairs(iindex[6]) do
                fields[ tp[1] ] = tp[2]

            end
            table.insert(space.index, {
                name    = iindex[3],
                type    = iindex[4],
                flags   = iindex[5],
                fields  = fields
            })
        end
    end
    
    table.insert(res, space)
end
return res

