package ResponseHandler;

use strict;
use warnings;

my $main;

sub new
{
    my ($self, $main_ref) = @_;
    $main = $main_ref;
    return bless {}, $self;
}

# sub ping
# {
#   #   my ($this, $responseMessage) = @_;
#   #   return 1;
# }

1;