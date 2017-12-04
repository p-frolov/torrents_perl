package Message;

use strict;
use warnings;

use autouse 'Data::Dumper' => qw(Dumper);
use JSON;

sub new
{
    my ( $self, %message ) = @_;
    bless {
        type    => $message{type}    || undef,  # request|response
        command => $message{command} || undef,  # command
        result  => $message{result}  || undef,  # succes, fail
        data    => $message{data}    || undef,  # json data
    }, $self;
}

sub fromJson
{
    my ( $self, $message_string ) = @_;
    my $message = JSON->new->utf8(1)->decode( $message_string );
    return Message->new( %$message );
}

sub isRequest
{
    my $this = shift;
    return $this->{type} eq 'request';
}

sub isResponse
{
    my $this = shift;
    return $this->{type} eq 'response';
}

sub createRequest
{
    my (undef, $command, $data) = @_;
    return Message->new( command => $command, data => $data, type => 'request' );
}

sub createEvent
{
    my (undef, $command, $data) = @_;
    return Message->new( command => $command, data => $data, type => 'event' );
}

# sub createResponse
# {
#     my (undef, $command, $data) = @_;
#     return Message->new( command => $command, data => $data, type => 'response' );
# }

sub toResponse
{
    my ($this, $params) = @_;
    $this->{type} = 'response';
    $this->{result} = undef;
    $this->{data} = undef;
    return $this;
}

sub success
{
    my $this = shift;
    $this->{result} = 'success';
    return $this;
}

sub fail
{
    my ($this, $error) = @_;
    $this->{data} = $error if $error;
    $this->{result} = 'fail';
    return $this;
}

sub setData
{
    my ($this, $data) = @_;
    $this->{data} = $data;
    return $this;
}

sub getData
{
    my ($this) = @_;
    return $this->{data};
}

sub toString
{
    my $this = shift;
    return JSON->new->encode( {%{$this}} );
}

1;