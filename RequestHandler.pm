package RequestHandler;

use strict;
use warnings;

use v5.10;
use feature 'say';

use autouse 'Data::Dumper' => qw(Dumper);

use Net::BitTorrent::File;
use Transmission::Client;
use File::Slurp qw(read_file write_file);
use MIME::Base64 qw(encode_base64);

my $main;
my $log;

sub new
{
    my ($self, $main_ref) = @_;
    $main = $main_ref;
    $log = $main->{log};
    return bless {}, $self;
}

sub checkTorrents
{
    my ($this, $requestMessage) = @_;
    my @files = $main->getTorrents();

    return $requestMessage->toResponse()->success() unless scalar @files;

    my @torrents = ();
    foreach (@files) {
        my $torrentFile = new Net::BitTorrent::File ($_);
        push @torrents, { name => $torrentFile->name(), path => $_ };
    }

    return $requestMessage->toResponse()->setData(\@torrents)->success();
}

sub loadTorrent
{
    my ($this, $requestMessage) = @_;

    my $client = Transmission::Client->new(
        url => 'http://192.168.1.1:8090/transmission/rpc',
        username => 'torrent',
        password => 'torrent123'
    );

    my $torrent = $requestMessage->getData();

    $log->debug( 'Torrent: ' . Dumper($torrent) );

    if ( $torrent->{isLoad} )
    {
        $log->trace('Load was chosen');

        unless ( -e $torrent->{path} )
        {
            my $errorMessage = 'File does not exit: "'.$torrent->{path}.'"';
            $log->error_warn($errorMessage);
            return $requestMessage->toResponse()->fail($errorMessage);
        }

        my $torrentFileContent = read_file( $torrent->{path}, binmode => ':raw' );

        unless ( $client->add( metainfo => $torrentFileContent,
            download_dir => '/tmp/mnt/disk//media//'.$torrent->{loadingFolder} ) )
        {
            my $errorMessage = 'Loading error: ' . $client->error;
            $log->error_warn($errorMessage);
            return $requestMessage->toResponse()->fail($errorMessage);
        }
  }
  
  if ( $torrent->{isRemove} )
  {
      $log->trace('Delete was chosen');
      unless ( unlink($torrent->{path}) )
      {
          my $errorMessage = 'Cannot delete file "'.$torrent->{path}.'": '.$!;
          $log->error_warn($errorMessage);
          return $requestMessage->toResponse()->fail($errorMessage);
      }
      else
      {
          $log->info('File was deleted: '.$torrent->{path});
      }
  }

  return $requestMessage->toResponse()->success();
}

1;