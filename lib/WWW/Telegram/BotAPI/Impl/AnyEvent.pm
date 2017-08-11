=head1 NAME

WWW::Telegram::BotAPI::Impl::AnyEvent - WWW::Telegram::BotAPI adaptor for AnyEvent

=head1 SYNOPSIS

   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support of AnyEvent.

=cut

package WWW::Telegram::BotAPI::Impl::AnyEvent;

use AnyEvent::HTTP;
use JSON::MaybeXS ();
use warnings;
use strict;

sub new
{
    my ($class, %settings) = @_;
    $settings{success} = 0;
    bless \%settings, $class;
}

sub json { return $_[0]->{res} }

sub success { return $_[0]->{success} }

sub res { return $_[0] }

sub post
{
    my ($self,$url) = (shift,shift);
    my ($cb,$cv,$ret);
    if (@_ and ref $_[-1] eq 'CODE') {
        $cb = pop;
    } else {
        $cv = AnyEvent->condvar;
        $cb = sub {
            $self->{res} = eval { JSON::MaybeXS::decode_json ($_[0]) } || undef;
            $self->{success} = 1;
            $cv->send;
        }
    }
    my %arg = @_;
    my $body = '';
    if (exists $arg{json}) {
        $body = JSON::MaybeXS::encode_json (delete $arg{json});
        $arg{headers}->{'Content-type'} = 'application/json';
    } elsif (exists $arg{form}) {
        use HTTP::Request::Common;
        my @c = map { ref $_ eq 'HASH' ? ( exists $_->{file} ? [$_->{file}] :
                                           exists $_->{content} ? [ undef,"",$_->{content} ] :$_ ): $_}
                                           %{delete $arg{form}};
        my $r = POST ($url, 'Content_Type' => 'form-data', 'Content_Encoding' => 'base64', 'Content' => \@c);

        $body = $r->content;
        $arg{headers}->{'Content-type'} = $r->header('Content-type');
    }
    http_post $url, $body, %arg, $cb;
    if ($cv) { $cv->recv; return $self; }
    return 1;
}
1
