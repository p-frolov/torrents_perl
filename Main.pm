package Main;

use strict;
use warnings;

use v5.10;
use feature 'say';

use Log::Log4perl;
use autouse 'Data::Dumper' => qw(Dumper);

use EV;
use AnyEvent;
use AnyEvent::Process;
use Linux::Inotify2;

use Message;
use Locker;
use RequestHandler;
use ResponseHandler;

my $log;

sub new
{
    my ($self, %params) = @_;
    my $this = bless {
        currentPath => $params{currentPath},
        watchingFolder => undef,
        guiProcess => undef,
    }, $self;

    unless ( chdir($this->{currentPath}) ) {
        warn("Cannot change working dir from '".getcwd()."' to '".$this->{currentPath});
        exit 1;
    }

    Log::Log4perl::init_and_watch( $this->{currentPath}.'/log4perl.conf', 60*30 );
    $log = Log::Log4perl->get_logger("Watcher");
    $this->{log} = $log;
    $log->info("Start watcher");

    $this->{locker} = Locker->new( path => $this->{currentPath}, name => 'main', log => $log );
    $this->{guiLocker} = Locker->new( path => $this->{currentPath}, name => 'gui', log => $log );

    return $this;
}

sub lock
{
    my $this = shift;
    if ( $this->{locker}->isLock ) {
        # todo: checking pid and ping process
        return 0;
    }
    $this->{locker}->lock();
    return 1;
}

sub exitWatchers
{
  my $this = shift;
  return (
    AnyEvent->signal(signal => "INT",  cb => sub { $this->exitHandler('^C') }),
    AnyEvent->signal(signal => "TSTP", cb => sub { $this->exitHandler('^Z') }),
    AnyEvent->signal(signal => "HUP",  cb => sub { $this->exitHandler('Terminal closed') }),
    AnyEvent->signal(signal => "TERM", cb => sub { $this->exitHandler('Killed') }),
    AnyEvent->signal(signal => "USR1", cb => sub { $this->exitHandler('Normal shutdown') }),
  );
}

sub exitHandler
{
  my $this = shift;
  $log->trace('Exit by signal: '.shift);
  $this->{locker}->unlock();
  $this->{guiLocker}->unlock() if $this->{guiLocker}->isLock;
  exit 1;
}

sub forlderWatcher
{
  my ($this, $folder) = @_;

  # создаем объект Linux::Inotify2
  my $inotify = Linux::Inotify2->new() 
      or $log->error_die("Can't create Linux::Inotify2 object: $!");

  $inotify->watch(
      $folder, IN_CREATE | IN_MOVED_TO,
      # $folder, IN_CREATE, # IN_CREATE IN_MOVED_TO
      sub { $this->torrentAddedCallback(@_) }
  );
  $log->trace('Inotify2 watcher was created');

  my $watcher = AnyEvent->io (
      fh => $inotify->fileno, poll => 'r', cb => sub { $inotify->poll }
  );
  $log->trace('AnyEvent: watcher was added');
  $this->{watchingFolder} = $folder;
  return $watcher;
}

sub getTorrents
{
    my $this = shift;
    my @files = glob ( $this->{watchingFolder} . '/*.torrent' );
    return @files;
}

sub firstCheckWatcher
{
    my $this = shift;
    $log->trace('First check');

    return AnyEvent->timer ( after => 2, cb => sub
    {
        my @files = $this->getTorrents();
        if (scalar @files)
        {
            $log->trace('Torrents manager startup checking event');
            $this->runProcessor();
        }
    });
}

# процедура, которая будет вызвана при изменении файла
sub torrentAddedCallback
{
  my $this = shift;
  $log->trace('Some file was added to download folder');
  # получаем информацию об измененном объекте
  my $event = shift;
  my $fileName = $event->fullname();
  return if not -f $fileName;
  return if $fileName !~ /.torrent$/;
  $log->info("Torrent was added: '$fileName'");

  if ( $this->{guiLocker}->isLock() ) {
    my $responseJson = Message->createEvent('newTorrent')->toString();
    $log->trace('send: ' . $responseJson);
    say TO_GUI $responseJson or $log->warn('Cannot print to process pipe');
  }
  else {
    $this->runProcessor();
  }
}

sub createProcessor
{
    my ($this, %params) = @_;

    my $proc = new AnyEvent::Process(
        fh_table => [
            \*STDIN  => ['pipe', '<', \*TO_GUI],
            \*STDOUT => ['pipe', '>', handle => [on_read => sub{
                chomp( my $line = $_[0]->rbuf );
                $_[0]->rbuf = "";
                $this->receiveHandler($line);
            }]],
            # \*STDERR => ['pipe', '>', \*ERR_GUI]
        ],
        code => sub { exec 'java -jar '.$this->{currentPath}.'/TorrentsGui.jar' },
        on_completion => sub {
            $log->trace('Gui closed');
            $this->{guiLocker}->unlock();
        },
    );
    $this->{guiProcess} = $proc;
    return $proc;
}

sub runProcessor
{
    my $this = shift;
    return if $this->{guiLocker}->isLock();
    $this->{guiProcess}->run();
    $this->{guiLocker}->lock();
    $log->trace('Gui started');
    select((select(TO_GUI), $| = 1)[0]);
    return 1;
}

sub receiveHandler
{
    my ($this, $message_string) = @_;
    $log->trace('receive: ' . $message_string);

    my $message = undef;
    eval {
        $message = Message->fromJson( $message_string );
    };
    if ( $@ ) {
        $log->error("parse message error: @_\nmessage: $message_string");
        return;
    }

    if ( $message->isRequest ) {
        my $command = $message->{command};
        unless ( RequestHandler->can($command) ) {
            $log->error('Unknown request: ' . Dumper($message));
            return;
        }
        my $responseMessage;
        eval {
            $responseMessage = RequestHandler->new($this)->$command($message);
            die "Returned not Message instance: " . Dumper($responseMessage) if ref($responseMessage) ne "Message";
        };
        if ($@) {
            $log->error($@);
            return;
        }
        my $responseJson = $responseMessage->toString();
        $log->trace('send: ' . $responseJson);
        say TO_GUI $responseJson or $log->warn('Cannot print to process pipe');
    }
    elsif ( $message->isResponse ) {

    }
    else {
        $log->warn('Unknown type message: ' . $message->{type});
    }
}

# sub pingWatcher
# {
#   my $this = shift;
#   return AnyEvent->timer ( after => 10, interval => 20, cb => sub {
#       my $message = Message->createRequest('ping')->toString();
#       $log->trace('send: ' . $message);
#       say TO_GUI $message or $log->warn('Cannot print to process pipe');
#   });
# }

1;