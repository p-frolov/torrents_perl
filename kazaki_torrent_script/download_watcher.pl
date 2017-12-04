#!/usr/bin/perl
use strict;
use warnings;

use v5.10;

use Log::Log4perl;
use autouse 'Data::Dumper' => qw(Dumper);

use EV;
use AnyEvent;
use Linux::Inotify2;

use File::Slurp qw(read_file write_file);

use Cwd qw( abs_path getcwd );
use File::Basename qw( dirname );

my $currentPath = dirname(abs_path($0));
unless ( chdir($currentPath) )
{
    warn("Cannot change working dir from '".getcwd()."' to '$currentPath'");
    exit 1;
}

Log::Log4perl::init_and_watch( "$currentPath/log4perl.conf", 60*30 );
my $log = Log::Log4perl->get_logger("Watcher");

$log->info("Start watcher");

my $pidFileName = $currentPath.'/lock';
if ( -e $pidFileName )
{
    # todo: error handle
    $log->error_warn('Watcher already started. Killing it...');
    my $pid = read_file($pidFileName);
    $log->debug("Pid: $pid");
    $log->error_warn("Cannot read file: $pidFileName") if not defined $pid;
    kill 'TERM', $pid
        or $log->error_warn('Cannot kill it.');
    sleep 1;
    unlink $pidFileName;
}

write_file($pidFileName, $$)
    or $log->error_die("Cannot save pid file: $pidFileName");

my $intSig  = AnyEvent->signal(signal => "INT",  cb => sub { exitHandler('^C') });
my $tstpSig = AnyEvent->signal(signal => "TSTP", cb => sub { exitHandler('^Z') });
my $hupSig  = AnyEvent->signal(signal => "HUP",  cb => sub { exitHandler('Terminal closed') });
my $termSig = AnyEvent->signal(signal => "TERM", cb => sub { exitHandler('Killed') });
my $quitSig = AnyEvent->signal(signal => "USR1", cb => sub { exitHandler('Normal shutdown') });

sub exitHandler
{
    $log->trace('Exit by signal: '.shift);
    unlink ($pidFileName)
        or $log->error_warn("Cannot delete pid file: $pidFileName");
    exit 1;
}


# выбираем для мониторинга папку, в которой лежит скрипт
my $downloadDir = "/home/pavel/Загрузки";
 
# создаем объект Linux::Inotify2
my $inotify = Linux::Inotify2->new() 
    or $log->error_die("Can't create Linux::Inotify2 object: $!");

$inotify->watch(
    $downloadDir, IN_CREATE, # IN_CREATE IN_MOVED_TO
    \&torrent_added_callback
);
$log->trace('Inotify2 watcher was created');

my $watcher = AnyEvent->io (
    fh => $inotify->fileno, poll => 'r', cb => sub { $inotify->poll }
);
$log->trace('AnyEvent: watcher was added');



my $downloadWatcherTimer = AnyEvent->timer ( after => 2, cb => sub
{
    $log->trace('Torrents manager startup checking event');
    # todo: check result
    system("$currentPath/torrents_manager.pl &");
});
$log->trace('AnyEvent: first check of manager timer was added');



# Пишется проверкой казаков
my $lastLoadedDateFileName = $currentPath.'/last_loaded_date';

my $kazakiCheckingTimer = AnyEvent->timer ( after => 10, interval => 60*30, cb => sub
{
    $log->trace('Kazaki-checker event');

    my ($hour,$mday,$wday) = (localtime)[2,3,6];
    $log->debug("Hour: $hour");
    $log->debug("Day: $mday");
    $log->debug("Week day: $wday");

    # Не проверяем в выходные
    if ($wday == 0 or $wday == 6)
    {
        $log->trace('Do not checking on weekend');
        return;
    }

    # Проверяем с 12 до 18
    unless ($hour >= 12 and $hour <= 18)
    {
        $log->trace('Checking out of time (12-18)');
        return;
    }
    
    # Серия один раз в день, если уже скачали - не проверяем
    if ( -e $lastLoadedDateFileName)
    {
        $log->trace('Last loaded date file exists');
        # todo or warn ("Cannot read file: $!");
        my $lastLoadedDate = read_file($lastLoadedDateFileName);
        $log->debug( 'Date of month of last loading: '.(localtime($lastLoadedDate))[3] );
        if ( (localtime($lastLoadedDate))[3] == $mday )
        {
            $log->trace('Already loaded today. Do not check.');
            return;
        }
    }
    
    $log->trace('Kazaki-checker command running');
    # todo: check result
    system("$currentPath/kazaki_torrent_checker.pl &");
});
$log->trace('AnyEvent: timer of kazaki-checker was added');

$log->trace('EV::loop ...');
EV::loop;

# процедура, которая будет вызвана при изменении файла
sub torrent_added_callback
{
    $log->trace('Some file was added to download folder');
    # получаем информацию об измененном объекте
    my $event = shift;
    my $fileName = $event->fullname();
    return if not -f $fileName;
    return if $fileName !~ /.torrent$/;
    $log->info("Torrent was added: '$fileName'");
    # todo: error handle
    # todo: check result
    $log->trace('Torrents manager command running');
    system("$currentPath/torrents_manager.pl &");
}