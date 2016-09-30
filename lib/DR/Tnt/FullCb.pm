use utf8;
use strict;
use warnings;

package DR::Tnt::FullCb;
use Mouse;

require DR::Tnt::LowLevel;
use File::Spec::Functions 'catfile', 'rel2abs';
use Carp;
use DR::Tnt::Dumper;
with 'DR::Tnt::Role::Logging';
use Scalar::Util;
use feature 'state';



use Mouse::Util::TypeConstraints;

enum DriverType     => [ 'sync', 'async' ];
enum FullCbState    => [ 'init', 'connecting', 'schema', 'ready', 'pause' ];

subtype FilePath    =>
    as 'Str',
    where { -d $_ },
    message { "$_ is not a directory" };

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

has logger      => is => 'ro', isa => 'Maybe[CodeRef]';
has host        => is => 'ro', isa => 'Str', required => 1;
has port        => is => 'ro', isa => 'Str', required => 1;
has user        => is => 'ro', isa => 'Maybe[Str]';
has password    => is => 'ro', isa => 'Maybe[Str]';
has driver      => is => 'ro', isa => 'DriverType', required => 1;

has lua_dir     => is => 'ro', isa => 'Maybe[FilePath]', writer => '_set_lua_dir';

has last_error  => is => 'ro', isa => 'Maybe[ArrayRef]', writer => '_set_last_error';

has state =>
    is          => 'ro',
    isa         => 'FullCbState',
    default     => 'init',
    writer      => '_set_state',
    trigger     => sub {
        $_[0]->_log(info => 'Connector is in state: %s',  $_[0]->state)
    };
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

    $self->_log(info => 'Starting connection to %s:%s (driver: %s)',
        $self->host, $self->port, $self->driver);

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

    $self->_log(debug => 'Eval "%s" after connection', $lua); 

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


has _sch            => is => 'rw', isa => 'HashRef';
has _spaces         => is => 'rw', isa => 'ArrayRef', default => sub {[]};
has _indexes        => is => 'rw', isa => 'ArrayRef', default => sub {[]};

has _wait_schema    => is => 'rw', isa => 'ArrayRef', default => sub { [] };

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
            $self->_log(debug => 'Loading spaces');
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

                $self->_log(debug => 'Loading indexes');
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
                        unless ($state eq 'OK') {
                            $self->_set_last_error([ $state, $message ]);
                            $self->_set_state('pause');
                            $cb->($state => $message);
                            return;
                        }
                        $self->_indexes($resp->{DATA});

                        $self->_set_schema($resp->{SCHEMA_ID});
                        $self->_set_state('ready');

                        my $list = $self->_wait_schema;
                        $self->_wait_schema([]);
                        $cb->('OK', 'Connected, schema loaded');
                        $self->request(@$_) for @$list;
                    });
                });
            });
        });

}

sub _set_schema {
    my ($self, $schema_id) = @_;

    my %sch;

    for (@{ $self->_spaces }) {
        my $space = $sch{ $_->[0] } = $sch{ $_->[2] } = {
            id      => $_->[0],
            name    => $_->[2],
            engine  => $_->[3],
            flags   => $_->[5],
            fields  => $_->[6],
            indexes => {  }
        };

        for (@{ $self->_indexes }) {
            next unless $_->[0] == $space->{id};

            $space->{indexes}{ $_->[2] } = 
            $space->{indexes}{ $_->[1] } = {
                id      => $_->[1],
                name    => $_->[2],
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

sub _tuples {
    my ($self, $resp, $space, $cb) = @_;


    unless (defined $space) {
        $cb->(OK => 'Response received', $resp->{DATA} // []);
        return;
    }

    unless (exists $self->_sch->{ $space }) {
        $cb->(OK => "Space $space not exists in schema", $resp->{DATA} // []);
        return;
    }

    my $res = $resp->{DATA} // [];
    $space = $self->_sch->{ $space };

    goto skip;

    for my $tuple (@$res) {
        next unless 'ARRAY' eq ref $tuple;
        my %t;

        for (0 .. $#{ $space->{fields} }) {
            my $fname = $space->{fields}[$_]{name} // sprintf "field:%02X", $_;
            $t{$fname} = $tuple->[$_];
        }

        $t{tail} = [ splice @$tuple, scalar @{ $space->{fields} } ];

        $tuple = \%t;
    }

    skip:

        $cb->(OK => 'Response received', $res);
}



sub request {
    my $cb = pop;
    my ($self, $name, @args) = @_;

    my $request = [ $name, @args, $cb ];
    
   
    # all states waits ready
    goto $self->state;
    init:
    pause:
    schema:
    connecting:
        push @{ $self->_wait_schema } => $request;
        return;


    ready:

    croak 'Usage $tnt->request(method => args ... sub { .. })'
        unless 'CODE' eq ref $cb;


    my ($space, $index);
    state $space_pos = {
        select      => 'index',
        update      => 'normal',
        insert      => 'normal',
        replace     => 'normal',
        delele      => 'normal',
        call_lua    => 'mayberef',
        eval_lua    => 'mayberef',
        ping        => 'none',
        auth        => 'none',
    };

    croak "unknown method $name" unless exists $space_pos->{$name};

    goto $space_pos->{$name};

    index:
        $space = $args[0];
        unless (exists $self->_sch->{ $space }) {
            $cb->(ER_NOSPACE => "Space $space not found");
            return;
        }
        $args[0] = $self->_sch->{ $space }{id};
        
        $index = $args[1];
        unless (exists $self->_sch->{ $space }{indexes}{ $index }) {
            $cb->(ER_NOINDEX => "Index space[$space].$index not found");
            return;
        }

        $index = $args[1] = $self->_sch->{$space}{indexes}{ $index }{id};
        goto do_request;

    normal:
        $space = $args[0];
        unless (exists $self->_sch->{ $space }) {
            $cb->(ER_NOSPACE => "Space $space not found");
            return;
        }
        $space = $args[0] = $self->_sch->{ $space }{id};
        goto do_request;

    mayberef:
        if ('ARRAY' eq ref $args[0]) {
            ($args[0], $space) = @{ $args[0] };
        }
        goto do_request unless defined $space;
        unless (exists $self->_sch->{ $space }) {
            $cb->(ER_NOSPACE => "Space $space not found");
            return;
        }
        $space = $self->_sch->{ $space }{id};


    none:

    do_request:

    $self->_ll->send_request($name, $self->last_schema, @args, sub {
        my ($state, $message, $sync) = @_;
        unless ($state eq 'OK') {
            $self->_set_last_error([ $state => $message ]);
            $self->_set_state('pause');
            $cb->(@{ $self->last_error });
            return;
        }

        $self->_ll->wait_response($sync, sub {
            my ($state, $message, $resp) = @_;
            unless ($state eq 'OK') {
                $self->_set_last_error([ $state => $message ]);
                $self->_set_state('pause');
                $cb->(@{ $self->last_error });
                return;
            }

            # schema collision
            if ($resp->{CODE} == 0x806D) {
                push @{ $self->_wait_schema } => $request;
                $self->_invalid_schema(sub {}) if $self->state eq 'ready';
                return;
            }

            unless ($resp->{CODE} == 0) {
                $cb->(ER_REQUEST => $resp->{ERROR}, $resp->{CODE});
                return;
            }
            $self->_tuples($resp, $space, $cb);
        });
    });

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

