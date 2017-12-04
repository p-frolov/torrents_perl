#!/usr/bin/perl

use v5.10;

use autouse 'Data::Dumper' => qw(Dumper);
use Log::Log4perl;

use Tk;
use Tk::BrowseEntry;

use Encode;
use MIME::Base64 qw(encode_base64);
use Cwd qw( abs_path getcwd );
use File::Basename qw( dirname );
use File::Slurp qw(read_file write_file);

my $currentPath = dirname(abs_path($0));
unless ( chdir($currentPath) )
{
    warn("Cannot change working dir from '".getcwd()."' to '$currentPath'");
    exit 1;
}

Log::Log4perl::init("$currentPath/log4perl.conf");
my $log = Log::Log4perl->get_logger("Manager");

$log->info('Start manager');
my $downloadDir = "/home/pavel/Загрузки";
my @torrents = glob ($downloadDir . '/*.torrent');

if ( not scalar @torrents )
{
    $log->trace('There are no torrents');
    exit 0;
}

my $torrentsOptions = {};

my $mw = new MainWindow;
$mw->title( 'New torrents!' );

$log->trace('Main window object was created');

foreach (@torrents)
{
    $log->debug("Torrent: $_");
	if ( exists $torrentsOptions->{$_} )
    {
        $log->error_warn('Duplicate torrent into torrents array created from folder');
        next;
    }
	
	$currentTorrentOptions = {
		isDelete => 1,
		isLoad => 1,
		loadingFolder => (/poka.+stan.+spit/) ? 'kazaki' : 'films'
	};

    $mw->Label(	-text => decode('utf8', $_) )->pack();
    
    $mw->Checkbutton(
        -text     => "Delete",
        -onvalue  => 1,
        -offvalue => 0,
        -variable => \$currentTorrentOptions->{isDelete},
    )->pack();
    
    $mw->Checkbutton(
        -text     => "Load",
        -onvalue  => 1,
        -offvalue => 0,
        -variable => \$currentTorrentOptions->{isLoad},
    )->pack();
    
    $mw->BrowseEntry(
        -variable => \$currentTorrentOptions->{loadingFolder},
        -choices => [ qw(films kazaki mult skazki) ]
    )->pack();
    
	$torrentsOptions->{$_} = $currentTorrentOptions;
    $log->trace('Controls was created.');
}

$mw->Button(
    -text => 'Run',
    -command => sub {
    	runButtonHandler($torrentsOptions);
    	exit;
    }
)->pack();

$log->trace('Main windows showing...');
MainLoop;

sub loadTorrent
{
	my ($torrentFileName, $loadingFolder) = @_;
    $log->trace('Load torrent');
    $log->debug("Filename: $torrentFileName");
    $log->debug("Folder: $loadingFolder");
	
	if ( not -e $torrentFileName )
	{
		$log->error_warn("File does not exit: $torrentFileName");
		return 0;
	}
	
    my $torrentFileContent = read_file( $torrentFileName, binmode => ':raw' );
    $log->debug( 'Content size: '.length($torrentFileContent) );
    my $torrentContentEncoded = encode_base64($torrentFileContent);
    $torrentContentEncoded =~ s/\n//g;
    
    my $curlCommand = q(curl 'http://192.168.1.1:8090/transmission/rpc' )
                    . q(-H 'Cookie: compact_display_state=true; filter=all' )
                    . q(-H 'Origin: http://192.168.1.1:8090' )
                    . q(-H 'Accept-Encoding: gzip,deflate,sdch' )
                    . q(-H 'Accept-Language: ru-RU,ru;q=0.8,en-US;q=0.6,en;q=0.4' )
                    . q(-H 'Authorization: Basic dXNlcjpwYXZlbDEyMzEyMw==' )
                    . q(-H 'Content-Type: json' )
                    . q(-H 'Accept: application/json, text/javascript, */*; q=0.01' )
                    . q(-H 'Referer: http://192.168.1.1:8090/transmission/web/' )
                    . q(-H 'X-Requested-With: XMLHttpRequest' )
                    . q(-H 'Connection: keep-alive' )
                    . q(-H 'User-Agent: Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/34.0.1847.116 Chrome/34.0.1847.116 Safari/537.36' )
                    . q(-H 'X-Transmission-Session-Id: ' )
                    . qq(--data-binary '{"method":"torrent-add","arguments":{"paused":false,"download-dir":"/tmp/mnt/disk//media/$loadingFolder","metainfo":"$torrentContentEncoded"}}' )
                    . q(--compressed);

    $log->trace('Running curl command...');
    my @curlResult = `$curlCommand 2>&1`;

    if ( $? == -1 )
	{
	  $log->error_warn("Command failed: $! on '$torrentFileName'");
	  return 0;
	}
	else
	{
	  $log->debug( 'Command exited with value: ' . ($? >> 8) );
	}
    my @webResponse = grep(/^{/, @curlResult);
    
    if (not scalar @webResponse)
    {
        $log->error_warn("Bad response: @webResponse for '$torrentFileName'");
        return 0;
    }    
    
    if ($webResponse[0] !~ /"result":"success"/)
    {
        $log->error_warn("Result is not success for '$torrentFileName'");
        return 0;
    }
    
    $log->info("Torrent was loaded: $torrentFileName");
    return 1;
}

sub runButtonHandler
{
	my $torrentsOptions = shift;
    $log->trace('Run button pressed');

    $log->trace('Loop torrents options');
	foreach my $fileName ( keys %{$torrentsOptions} )
	{
        $log->debug("Torrent name: $fileName");
        $log->debug( 'Torrent options: ' . Dumper($torrentsOptions->{$fileName}) );
		
		if ( $torrentsOptions->{$fileName}->{isLoad} )
		{
            $log->trace('Load was chosen');
			if ( not loadTorrent( $fileName, $torrentsOptions->{$fileName}->{loadingFolder} ) )
			{
			    $log->error_warn("Cannot load torrent: $fileName");
			    next;
			}
		}
		
		if ( $torrentsOptions->{$fileName}->{isDelete} )
		{
			$log->trace('Delete was chosen');
			unless ( unlink($fileName) )
            {
                $log->error_warn("Cannot delete file '$fileName': $!");
            }
            else
            {
                $log->info("Файл был удалён: $fileName");
            }
		}
	}	
}


__DATA__

https://trac.transmissionbt.com/browser/branches/1.7x/doc/rpc-spec.txt
...
	3.4.  Adding a Torrent
309	
310	   Method name: "torrent-add"
311	
312	   Request arguments:
313	
314	   key                | value type & description
315	   -------------------+-------------------------------------------------
316	   "download-dir"     | string      path to download the torrent to
317	   "filename"         | string      filename or URL of the .torrent file
318	   "metainfo"         | string      base64-encoded .torrent content
319	   "paused"           | boolean     if true, don't start the torrent
320	   "peer-limit"       | number      maximum number of peers
321	   "files-wanted"     | array       indices of file(s) to download
322	   "files-unwanted"   | array       indices of file(s) to not download
323	   "priority-high"    | array       indices of high-priority file(s)
324	   "priority-low"     | array       indices of low-priority file(s)
325	   "priority-normal"  | array       indices of normal-priority file(s)
326	
327	   Either "filename" OR "metainfo" MUST be included.
328	   All other arguments are optional.
329	
330	   Response arguments: on success, a "torrent-added" object in the
331	                       form of one of 3.3's tr_info objects with the
332	                       fields for id, name, and hashString.

curl 'http://192.168.1.1:8090/transmission/rpc' 
    -H 'Cookie: compact_display_state=true; filter=all' 
    -H 'Origin: http://192.168.1.1:8090' 
    -H 'Accept-Encoding: gzip,deflate,sdch' 
    -H 'Accept-Language: ru-RU,ru;q=0.8,en-US;q=0.6,en;q=0.4' 
    -H 'Authorization: Basic dXNlcjpwYXZlbDEyMzEyMw==' 
    -H 'Content-Type: json' 
    -H 'Accept: application/json, text/javascript, */*; q=0.01' 
    -H 'Referer: http://192.168.1.1:8090/transmission/web/' 
    -H 'X-Requested-With: XMLHttpRequest' 
    -H 'Connection: keep-alive' 
    -H 'User-Agent: Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/34.0.1847.116 Chrome/34.0.1847.116 Safari/537.36' 
    -H 'X-Transmission-Session-Id: ' 
    --data-binary '
        {
            "method":"torrent-add",
            "arguments":{
                "paused":false,
                "download-dir":"/tmp/mnt/disk//kazaki",
                "metainfo":"ZDE.....ZWVl"
            }
        }
    ' 
    --compressed

{"arguments":{"torrent-added":{"hashString":"d8174178485298deb5674d58d63e1fc9f15b3051","id":4,"name":"Poka.stanica.spit.112.SATRip.[www.Riper.AM].avi"}},"result":"success"}