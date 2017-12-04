#!/usr/bin/perl

use Cwd qw( abs_path getcwd );
use File::Basename qw( dirname );
use File::Slurp qw(read_file);

my $pidFileName = dirname(abs_path($0)).'/lock';
exit 0 if not -e $pidFileName;

my $pid = read_file($pidFileName);
exit 1 if not $pid;

kill ('USR1', $pid) or exit 1;

exit 1;

=POD
https://wiki.ubuntu.com/LightDM
/etc/lightdm/lightdm.conf
[SeatDefaults]
session-cleanup-script=command
/home/pavel/.bash_logout
=cut