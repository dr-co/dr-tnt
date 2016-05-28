use utf8;
use strict;
use warnings;

package DR::Tnt::Test::TntInstance;
use File::Temp;
use File::Spec::Functions 'rel2abs', 'catfile';
use Time::HiRes ();
use POSIX;

my @started;

sub new {
    my ($class, %opts) = @_;

    die "-lua options is not defined" unless $opts{-lua};
    $opts{-lua} = rel2abs $opts{-lua};
    my $self = bless \%opts => ref($class) || $class;


    if ($self->{-dir}) {
        die "$self->{-dir} not found" unless -d $self->{-dir};
    } else {
        $self->{-dir} = File::Temp::tempdir;
        $self->{-clean} = [ $self->{-dir} ];
    }

    $self->{-log} = rel2abs catfile $self->{-dir}, 'tarantool.log';
    $self->{-log_seek} = 0;
    if (-r $self->{-log}) {
        open my $fh, '<', $self->{-log};
        seek $fh, 0, 2;
        $self->{-log_seek} = tell $fh;
        close $fh;
    }

    if ($self->{pid} = fork) {
        push @started => $self;
        Time::HiRes::sleep .1;
        return $self;
    }

    open my $fh, '>>', $self->{-log};
    POSIX::dup2(fileno($fh), fileno(STDOUT));
    POSIX::dup2(fileno($fh), fileno(STDERR));
    close $fh;

    chdir $self->{-dir};
    if ($opts{-port}) {
        $ENV{PRIMARY_PORT} = $opts{-port};
    }
    $ENV{WORK_DIR} = $opts{-dir};
    exec tarantool => $opts{-lua};
    die "Can't start tarantool";
}

sub log {
    my ($self) = @_;
    return '' unless -r $self->{-log};
    open my $fh, '<', $self->{-log};
    seek $fh, 0, $self->{-log_seek};
    local $/;
    my $data = <$fh>;
    return $data;
}

sub clean {
    my ($self) = @_;
    return unless $self->{-clean};
    for (@{ $self->{-clean} }) {
        system "rm -fr $_";
    }
}

sub pid { $_[0]->{pid} };

sub kill {
    my ($self, $sig) = @_;
    return unless $self->pid;
    $sig ||= '-TERM';
    kill $sig, $self->pid;
    delete $self->{pid};
}

sub DESTROY {
    my ($self) = @_;
    $self->kill('-KILL');
    $self->clean;
}

END {
    $_->kill('-KILL') for @started;
}

1;
