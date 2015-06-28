package WWW::Telegram::BotAPI;
use strict;
use warnings;
use Carp ();
use JSON::MaybeXS ();

our $VERSION = "0.01";

BEGIN {
    eval "require Mojo::UserAgent; 1" or
        eval "require LWP::UserAgent; 1" or
        die "Either Mojo::UserAgent or LWP::UserAgent is required.\n$@";
}

# %settings = (
#     async     => Bool,
#     token     => String,
#     api_url   => "http://something/%s/%s", # 1st %s = tok, 2nd %s = method
#     force_lwp => Bool
# )
sub new
{
    my ($class, %settings) = @_;
    exists $settings{token}
        or Carp::croak "ERROR: missing 'token' from \%settings.";
    # Ensure that LWP is loaded if "force_lwp" is specified.
    $settings{force_lwp}
        and require LWP::UserAgent;
    $settings{_agent} = ($settings{force_lwp} or !Mojo::UserAgent->can ("new")) ?
        LWP::UserAgent->new : Mojo::UserAgent->new;
    exists $settings{async}
        or $settings{async} = 0;
    $settings{async} and $settings{_agent}->isa ("LWP::UserAgent")
        and Carp::croak "ERROR: Mojo::UserAgent is required to use 'async'.";
    exists $settings{api_url}
        or $settings{api_url} = "https://api.telegram.org/bot%s/%s";
    bless \%settings, $class
}

# Magically provide methods named as the Telegram API ones, such as $o->sendMessage.
sub AUTOLOAD
{
    my $self = shift;
    our $AUTOLOAD;
    (my $method = $AUTOLOAD) =~ s/.*:://; # removes the package name at the beginning
    $self->api_request ($method, @_);
}

sub api_request
{
    my ($self, $method) = map { shift } 1 .. 2;
    # Detect if the user provided a callback to use for async requests.
    # The only parameter whose order matters is $method. The callback and the request parameters
    # can be put in any order, like this: $o->api_request ($method, sub {}, { a => 1 }) or
    # $o->api_request ($method, { a => 1 }, sub {}), or even
    # $o->api_request ($method, "LOL", "DONGS", sub {}, { a => 1 }).
    my ($postdata, $async_cb);
    foreach my $arg (@_)
    {
        # Poor man's switch block
        for (ref $arg)
        {
            ($async_cb = $arg, last) if $_ eq "CODE";
            ($postdata = $arg, last) if $_ eq "HASH";
        }
        last if defined $async_cb and defined $postdata;
    }
    # Croak if we don't have a callback, but "async" is true.
    $self->{async} and !defined $async_cb
        and Carp::croak "ERROR: missing CODE reference to call on non-blocking request.";
    # Prepare the request method parameters.
    my @request;
    my $is_lwp = $self->_is_lwp;
    # Push the request URI. (at least, this is the same in LWP and Mojo)
    push @request, sprintf ($self->{api_url}, $self->{token}, $method);
    if (defined $postdata)
    {
        # Determine if we are going to perform a file upload, and if so, do some magic. (LWP only)
        if ($is_lwp)
        {
            # Traverse the post arguments.
            my $has_file_upload = 0;
            foreach my $k (keys %$postdata)
            {
                if (ref $postdata->{$k} eq "HASH") # there's our file upload
                {
                    # The structure of the hash must be either this:
                    # { content => 'file content' }
                    # Or this:
                    # { file => 'path to file' }
                    # With an optional key "filename" that specifies the... filename, and
                    # optional headers to be merged into the multipart/form-data stuff.
                    # See https://metacpan.org/pod/Mojo::UserAgent::Transactor#tx
                    ++$has_file_upload;
                    # HTTP::Request::Common uses this syntax instead:
                    # [ $file, $filename, SomeHeader => 'bla bla', Content => 'fileContent' ]
                    # See p3rl.org/HTTP::Request::Common#POST-url-Header-Value-...-Content-content
                    my $new_val = [];
                    # Push and remove the keys 'file' and 'filename' (if defined) to $new_val.
                    push @$new_val, delete $postdata->{$k}{file},
                                    delete $postdata->{$k}{filename};
                    # Push 'Content' (note the uppercase 'C')
                    exists $postdata->{$k}{content}
                        and push @$new_val, Content => delete $postdata->{$k}{content};
                    # Push the other headers.
                    push @$new_val, %{$postdata->{$k}};
                    # Finalize the changes.
                    $postdata->{$k} = $new_val;
                }
                elsif (ref $postdata->{$k} eq "ARRAY")
                {
                    Carp::croak "ERROR: the upload of multiple files w/LWP is not supported yet.";
                }
            }
            $has_file_upload
                and push @request, Content      => $postdata,
                                   Content_Type => "form-data"
                or  push @request, $postdata;
        }
        else
        {
            # Mojo::UserAgent stuff
            push @request, form => $postdata;
        }
    }
    # Protip (also mentioned in the doc): if you are using non-blocking requests with
    # Mojo::UserAgent, remember to start the event loop with Mojo::IOLoop->start.
    # This is unnecessary when you are using this module with Mojolicious.
    push @request, $async_cb if $self->{async};
    # Stop here if this is a test - specified using the "_dry_run" flag.
    return 1 if $self->{_dry_run};
    # Perform the request.
    my $tx = $self->agent->post (@request);
    # We're done if the request is asynchronous.
    return $tx if $self->{async};
    # Otherwise, if we f****d up... die horribly.
    unless ($is_lwp ? $tx->is_success : $tx->success)
    {
        die "ERROR: ", ($is_lwp ? $tx->status_line : $tx->error->{message});
    }
    # Decode and return the JSON.
    $is_lwp ? eval { JSON::MaybeXS::decode_json ($tx->decoded_content) } || undef : $tx->res->json
}

sub agent
{
    shift->{_agent}
}

sub _is_lwp
{
    shift->agent->isa ("LWP::UserAgent")
}

1;

=encoding utf8

=head1 NAME

WWW::Telegram::BotAPI - Perl implementation of the Telegram Bot API

=head1 SYNOPSIS

    use WWW::Telegram::BotAPI;
    my $api = WWW::Telegram::BotAPI->new (
        token => 'my_token'
    );
    # The API methods die when an error occurs.
    say $api->getMe->{result}{username};
    # Uploading files is easier than ever.
    $api->sendPhoto ({
        chat_id => 123456,
        photo   => {
            file => "/home/me/cool_pic.png"
        },
        caption => "Look at my cool photo!"
    });
    # Asynchronous request support with Mojo::UserAgent.
    $api = WWW::Telegram::BotAPI->new (
        token => 'my_token',
        async => 1
    );
    $api->sendMessage ({
        chat_id => 123456,
        text    => 'Hello world!'
    }, sub {
        my ($ua, $tx) = @_;
        die "Something bad happened!" unless $tx->success;
        say $tx->res->json->{ok} ? "YAY!" : ":(";
    });
    Mojo::IOLoop->start;

=head1 DESCRIPTION

This module provides an easy to use interface for the
L<Telegram Bot API|https://core.telegram.org/bots/api>. It also supports async requests out of the
box using L<Mojo::UserAgent>, which makes this module easy to integrate with an existing
L<Mojolicious> application.

=head1 METHODS

L<WWW::Telegram::BotAPI> implements the following methods.

=head2 new

    my $api = WWW::Telegram::BotAPI->new (%options);

Creates a new L<WWW::Telegram::BotAPI> instance.

C<%options> may contain the following:

=over 4

=item * C<< token => 'my_token' >>

The token that will be used to authenticate the bot.

B<This is required! The method will croak if this option is not specified.>

=item * C<< api_url => 'https://api.example.com/token/%s/method/%s' >>

A format string that will be used to create the final API URL. The first parameter specifies
the token, the second one specifies the method.

Defaults to C<https://api.telegram.org/bot%s/%s>.

=item * C<< async => 1 >>

Enables asynchronous requests.

B<This requires L<Mojo::UserAgent>, and the method will croak if it isn't found.>

B<NOTE:> I<all> requests will be asynchronous when this option is enabled, and if a method
is called without a callback then it will croak.

=item * C<< force_lwp => 1 >>

Forces the usage of L<LWP::UserAgent> instead of L<Mojo::UserAgent>, even if the latter is
available.

By default, the module tries to load L<Mojo::UserAgent>, and on failure it uses L<LWP::UserAgent>.

=back

=head2 AUTOLOAD

    $api->getMe;
    $api->whatever;

This module makes use of L<perlsub/"Autoloading">. This means that every current and future method
of the Telegram Bot API can be used by calling its Perl equivalent, without requiring an update
of the module.

If you'd like to avoid using C<AUTOLOAD>, then you may simply call the L</"api_request"> method
specifying the method name as the first argument.

    $api->api_request ('getMe');

This is, by the way, the exact thing the C<AUTOLOAD> method of this module does.

=head2 api_request

    $api->api_request ('getMe');
    $api->api_request ('sendMessage', {
        chat_id => 123456,
        text    => 'Oh, hai'
    });
    # file upload
    $api->api_request ('sendDocument', {
        chat_id  => 123456,
        document => {
            filename => 'dump.txt',
            content  => 'secret stuff'
        }
    });
    # with async => 1, and the IOLoop already started
    $api->api_request ('getMe', sub {
        my ($ua, $tx) = @_;
        die unless $tx->success;
        # ...
    });

This method performs an API request. The first argument must be the method name
(L<here's a list|https://core.telegram.org/bots/api#available-methods>).

Once the request is completed, the response is decoded using L<JSON::MaybeXS> and then
returned. If L<Mojo::UserAgent> is used as the user-agent, then the response is decoded
automatically using L<Mojo::JSON>.

Parameters can be specified using an hash reference.

File uploads are specified using an hash reference containing the following mappings:

=over 4

=item * C<< file => '/path/to/file.ext' >>

Path to the file you want to upload.

Required only if C<content> is not specified.

=item * C<< filename => 'file_name.ext' >>

An optional filename that will be used instead of the real name of the file.

Particularly recommended when C<content> is specified.

=item * C<< content => 'Being a file is cool :-)' >>

The content of the file to send. When this is used, C<file> must not be specified.

=item * C<< AnyCustom => 'Header' >>

Custom headers can be specified as hash mappings.

=back

Upload of multiple files is not supported. See L<Mojo::UserAgent::Transactor/"tx"> for more
information about file uploads.

When asynchronous requests are enabled, a callback has to be specified as an argument.
The arguments passed to the callback are, in order, the user-agent (a L<Mojo::UserAgent> object)
and the response (a L<Mojo::Transaction::HTTP> object). More information can be found in the
documentation of L<Mojo::UserAgent> and L<Mojo::Transaction::HTTP>.

B<NOTE:> ensure that the event loop L<Mojo::IOLoop> is started when using asynchronous requests.
This is not needed when using this module inside a L<Mojolicious> app.

The order of the arguments, except of the first one, does not matter:

    $api->api_request ('sendMessage', $parameters, $callback);
    $api->api_request ('sendMessage', $callback, $parameters); # same thing!

=head2 agent

    my $user_agent = $api->agent;

Returns the instance of the user-agent used by the module. You can determine if the module is using
L<LWP::UserAgent> or L<Mojo::UserAgent> by using C<isa>:

    my $is_lwp = $user_agent->isa ('LWP::UserAgent');

=head1 CAVEATS

No error handling is performed when using asynchronous requests.

If the response is not a valid JSON string, C<undef> is returned.

=head1 SEE ALSO

L<LWP::UserAgent>, L<Mojo::UserAgent>,
L<https://core.telegram.org/bots/api>, L<https://core.telegram.org/bots>

=head1 AUTHOR

Roberto Frenna (robertof AT cpan DOT org)

=head1 BUGS

Please report any bugs or feature requests to
L<https://github.com/Robertof/perl-www-telegram-botapi>.

=head1 THANKS

Thanks to L<the authors of Mojolicious|Mojolicious> for inspiration about the license and the
documentation.

=head1 LICENSE

Copyright (C) 2015, Roberto Frenna.

This program is free software, you can redistribute it and/or modify it under the terms of the
Artistic License version 2.0.

=cut
