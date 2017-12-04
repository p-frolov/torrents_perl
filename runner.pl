#!/usr/bin/perl
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

use Cwd qw( abs_path getcwd );
use File::Basename qw( dirname );

my $currentPath;
BEGIN
{
    $currentPath = dirname(abs_path($0));
    unshift @INC, $currentPath;
}

require Main;
my $main = Main->new( currentPath => $currentPath );
exit 0 unless $main->lock();
my $log = $main->{log};

my ( $intSig, $tstpSig, $hupSig, $termSig, $quitSig ) = $main->exitWatchers();
my $downloadWatcher = $main->forlderWatcher( "/home/pavel/Downloads" );
my $downloadWatcherTimer = $main->firstCheckWatcher();
my $proc = $main->createProcessor();
# my $pingWatcher = $main->pingWatcher();

$main->{log}->trace('EV::loop ...');
EV::loop;
