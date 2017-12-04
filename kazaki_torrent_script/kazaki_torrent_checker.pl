#!/usr/bin/perl
use strict;
use warnings;

use v5.10;

use encoding 'utf-8';
use autouse 'Data::Dumper' => qw( Dumper );
use Array::Utils qw( array_minus );
use Log::Log4perl;

use LWP::Simple;
use Cwd qw( abs_path getcwd );
use File::Basename qw( dirname );
use File::Slurp qw( read_file write_file );

my $currentPath = dirname(abs_path($0));
unless ( chdir($currentPath) )
{
    warn("Cannot change working dir from '".getcwd()."' to '$currentPath'");
    exit 1;
}

Log::Log4perl::init("$currentPath/log4perl.conf");
my $log = Log::Log4perl->get_logger("Checker");

$log->info("Start checker");
$log->error_die('Нет больше торрентов на этой странице');

# Качаем ссылки
my $baseUrl = 'http://hotkit.ru';
my @allTorrentsLinks = ();

my $content = get ($baseUrl . '/seriali-russkie/poka-stanitsa-spit-serial-2014-skachat-torrent');
$log->error_die("Torrents page getting error") if ( not defined $content );
$log->trace('Content was loaded');

while ($content =~ /(\/download\/\w+-poka\.stanica\.spit\.\d{3}\.satrip\.\.avi\.\.torrent)/g)
{
    push (@allTorrentsLinks, $baseUrl.$1);
}

$log->error_die("There are no torrent the page!")
    if not scalar @allTorrentsLinks;

# Смотрим уже добавленные
my $downloadDir = "/home/pavel/Загрузки/";
my $loadedTorrentsFileName = $currentPath . '/loaded_torrents';
my @loadedTorrentsLinks = ();

if ( -e $loadedTorrentsFileName )
{
    @loadedTorrentsLinks = read_file($loadedTorrentsFileName);
    chomp @loadedTorrentsLinks;
    $log->trace('Loaded torrents was read from file');
}

# Вычисляем новые из разницы всех и загруженных
my @newTorrentsLins = array_minus(@allTorrentsLinks, @loadedTorrentsLinks);

# Метка времени последнего, загруженного
my $lastLoadedDateFileName = $currentPath . '/last_loaded_date';

# Качаем разницу
foreach my $url (@newTorrentsLins)
{
    if ( not $url =~ /([^\/]*\.torrent)$/ )
    {
        $log->error_warn ("Cannot extract filename from url: $url");
        next;
    }    
    $log->info("Новый торрент: $1");
    
    my $fileName = $downloadDir . $1;
    $log->debug("Url: $url");
    $log->debug("Filename: $fileName");

    if ( getstore($url, $fileName) != 200 )
    {
        $log->error_warn ("Http status is not OK: $url");
        next;
    }
    $log->trace("Torrent file was downloaded");
    
    if ( not -e $fileName)
    {
        $log->error_warn ("Torrent was loaded but not exist: '$fileName'. Error: $!");
        next;
    }
    $log->trace("Torrent file was saved");
    
    # Ставим метку времени
    write_file($lastLoadedDateFileName, time)
        or $log->error_warn ("Cannot write datetime of last download: '$lastLoadedDateFileName'");
        
    push ( @loadedTorrentsLinks, $url );
    $log->trace("New torrent link was added to loaded torrents");
}

# Сохраняем загруженные
write_file( $loadedTorrentsFileName, map { "$_\n" } @loadedTorrentsLinks )
    or $log->error_warn ("Cannot write file '$loadedTorrentsFileName'");

$log->trace("End checker");
exit 0;

__DATA__

curl 'http://hotkit.ru/seriali-russkie/poka-stanitsa-spit-serial-2014-skachat-torrent' -H 'Accept-Encoding: gzip,deflate,sdch' -H 'Accept-Language: ru-RU,ru;q=0.8,en-US;q=0.6,en;q=0.4' -H 'User-Agent: Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/34.0.1847.116 Chrome/34.0.1847.116 Safari/537.36' -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8' -H 'Cache-Control: max-age=0' -H 'Cookie: defe557dd465cb20e49612e8f01ca48b=eec903f6470efc0fed8ebfa7b765b6b7' -H 'Connection: keep-alive' --compressed