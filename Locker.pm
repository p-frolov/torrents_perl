package Locker;

use strict;
use warnings;

use File::Slurp qw(read_file write_file);

my $log;

sub new
{
  my ($self,%params) = @_;
  die "No path" unless $params{path};
  $log = $params{log};
  return bless {
    path => $params{path},
    name => $params{name} || 'lock',
    pidFileName => $params{path}.'/'.$params{name}
  }, $self;
}

sub lock
{
  my $this = shift;
  if ( -e $this->{pidFileName} )
  {
      # todo: error handle
      $log->error_warn('Watcher already started. Killing it...');
      my $pid = read_file($this->{pidFileName});
      $log->debug("Pid: $pid");
      $log->error_warn('Cannot read file: ' . $this->{pidFileName}) if not defined $pid;
      kill 'TERM', $pid
          or $log->error_warn('Cannot kill it.');
      sleep 1;
      unlink $this->{pidFileName};
  }

  write_file($this->{pidFileName}, $$)
      or $log->error_die('Cannot save pid file: ' . $this->{pidFileName});
}

sub unlock
{
  my $this = shift;
  unlink ($this->{pidFileName})
      or $log->error_warn('Cannot delete pid file: ' . $this->{pidFileName});
}

sub isLock
{
  my $this = shift;
  return -e $this->{pidFileName};
}

1;