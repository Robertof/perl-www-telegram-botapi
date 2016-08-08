package WWW::Telegram::BotAPI;
use strict;
use warnings;
use warnings::register;
use Carp ();
use JSON::MaybeXS ();
use constant DEBUG => $ENV{TELEGRAM_BOTAPI_DEBUG} || 0;

our $VERSION = "0.03";
my $json; # for debugging purposes, only defined when DEBUG = 1

BEGIN {
    eval "require Mojo::UserAgent; 1" or
        eval "require LWP::UserAgent; 1" or
        die "Either Mojo::UserAgent or LWP::UserAgent is required.\n$@";
    $json = JSON::MaybeXS->new (pretty => 1, utf8 => 1) if DEBUG;
}

# Debugging functions (only used when DEBUG is true)
sub _dprintf { printf "-T- $_[0]\n", splice @_, 1 }
sub _ddump
{
    my ($varname, $to_dump) = splice @_, -2;
    _dprintf @_ if @_;
    printf "%s = %s", $varname, $json->encode ($to_dump);
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
    # When DEBUG is enabled, and Mojo::UserAgent is used, Mojolicious must be at
    # least version 6.22 (https://github.com/kraih/mojo/blob/v6.22/Changes). This is because
    # Mojo::JSON used incompatible JSON boolean constants which led JSON::MaybeXS to crash
    # with a mysterious error message. To prevent this, we force LWP in this case.
    if (DEBUG && Mojo::JSON->can ("true") && ref Mojo::JSON->true ne "JSON::PP::Boolean")
    {
        warnings::warnif (
            "WARNING: Enabling DEBUG with Mojolicious versions < 6.22 won't work. Forcing " .
            "LWP::UserAgent. (update Mojolicious or disable DEBUG to fix)"
        );
        ++$settings{force_lwp};
    }
    # Ensure that LWP is loaded if "force_lwp" is specified.
    $settings{force_lwp}
        and require LWP::UserAgent;
    # Instantiate the correct user-agent. This automatically detects whether Mojo::UserAgent is
    # available or not.
    $settings{_agent} = ($settings{force_lwp} or !Mojo::UserAgent->can ("new")) ?
        LWP::UserAgent->new : Mojo::UserAgent->new;
    ($settings{async}  ||= 0) and $settings{_agent}->isa ("LWP::UserAgent")
        and Carp::croak "ERROR: Mojo::UserAgent is required to use 'async'.";
    $settings{api_url} ||= "https://api.telegram.org/bot%s/%s";
    DEBUG && _dprintf "WWW::Telegram::BotAPI initialized (v%s), using agent %s %ssynchronously.",
        $VERSION, ref $settings{_agent}, $settings{async} ? "a" : "";
    bless \%settings, $class
}

# Don't let old Perl versions call AUTOLOAD when DESTROYing our class.
sub DESTROY {}

# Magically provide methods named as the Telegram API ones, such as $o->sendMessage.
sub AUTOLOAD
{
    my $self = shift;
    our $AUTOLOAD;
    (my $method = $AUTOLOAD) =~ s/.*:://; # removes the package name at the beginning
    $self->api_request ($method, @_);
}

# The real stuff!
sub api_request
{
    my ($self, $method) = splice @_, 0, 2;
    # Detect if the user provided a callback to use for async requests.
    # The only parameter whose order matters is $method. The callback and the request parameters
    # can be put in any order, like this: $o->api_request ($method, sub {}, { a => 1 }) or
    # $o->api_request ($method, { a => 1 }, sub {}), or even
    # $o->api_request ($method, "LOL", "DONGS", sub {}, { a => 1 }).
    my ($postdata, $async_cb);
    for my $arg (@_)
    {
        # Poor man's switch block
        for (ref $arg)
        {
            # Ensure that we don't get async callbacks when we aren't in async mode.
            ($async_cb = $arg, last) if $_ eq "CODE" and $self->{async};
            ($postdata = $arg, last) if $_ eq "HASH";
        }
        last if defined $async_cb and defined $postdata;
    }
    # Prepare the request method parameters.
    my @request;
    my $is_lwp = $self->_is_lwp;
    # Push the request URI (this is the same in LWP and Mojo)
    push @request, sprintf ($self->{api_url}, $self->{token}, $method);
    if (defined $postdata)
    {
        # POST arguments which are array/hash references need to be handled as follows:
        # - if no file upload exists, use application/json and encode everything with JSON::MaybeXS
        #   or let Mojo::UserAgent handle everything, when available.
        # - whenever a file upload exists, the MIME type is switched to multipart/form-data.
        #   Other refs which are not file uploads are then encoded with JSON::MaybeXS.
        my @fixable_keys; # This array holds keys found before file uploads which have to be fixed.
        my $has_file_upload;
        # Traverse the post arguments.
        for my $k (keys %$postdata)
        {
            next unless my $ref = ref $postdata->{$k};
            # Process file uploads.
            if ($ref eq "HASH" and
                (exists $postdata->{$k}{file} or exists $postdata->{$k}{content}))
            {
                # WARNING: using file uploads implies switching to the MIME type
                # multipart/form-data, which needs a JSON stringification for every complex object.
                ++$has_file_upload;
                # No particular treatment is needed for file uploads when using Mojo.
                next unless $is_lwp;
                # The structure of the hash must be:
                # { content => 'file content' } or { file => 'path to file' }
                # With an optional key "filename" and optional headers to be merged into the
                # multipart/form-data stuff.
                # See https://metacpan.org/pod/Mojo::UserAgent::Transactor#tx
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
            else
            {
                $postdata->{$k} = JSON::MaybeXS::encode_json $postdata->{$k}, next
                    if $has_file_upload;
                push @fixable_keys, $k;
            }
        }
        if ($has_file_upload)
        {
            # Fix keys found before the file upload.
            $postdata->{$_} = JSON::MaybeXS::encode_json $postdata->{$_} for @fixable_keys;
            $is_lwp
                and push @request, Content      => $postdata,
                                   Content_Type => "form-data"
                or  push @request, form         => $postdata;
        }
        else
        {
            $is_lwp
                and push @request, DEBUG ? (DBG => $postdata) : (), # handled in _fix_request_args
                                   Content      => JSON::MaybeXS::encode_json $postdata,
                                   Content_Type => "application/json"
                or  push @request, json         => $postdata;
        }
    }
    # Protip (also mentioned in the doc): if you are using non-blocking requests with
    # Mojo::UserAgent, remember to start the event loop with Mojo::IOLoop->start.
    # This is superfluous when using this module in a Mojolicious app.
    push @request, $async_cb if $async_cb;
    # Stop here if this is a test - specified using the (internal) "_dry_run" flag.
    return 1 if $self->{_dry_run};
    DEBUG and _ddump "BEGIN REQUEST to /%s :: %s", $method, scalar localtime,
        PAYLOAD => _fix_request_args ($self, \@request);
    # Perform the request.
    my $tx = $self->agent->post (@request);
    DEBUG and $async_cb and
        _dprintf "END REQUEST to /%s (async) :: %s", $method, scalar localtime;
    # We're done if the request is asynchronous.
    return $tx if $async_cb;
    # Pre-decode the response to provide, if possible, an error message.
    my $response = $is_lwp ?
        eval { JSON::MaybeXS::decode_json ($tx->decoded_content) } || undef :
        $tx->res->json;
    # Dump it in debug mode.
    DEBUG and _ddump RESPONSE => $response;
    # If we (or the server) f****d up... die horribly.
    unless (($is_lwp ? $tx->is_success : $tx->success) && $response && $response->{ok})
    {
        $response ||= {};
        # Print either the error returned by the API or the HTTP status line.
        Carp::confess
            "ERROR: ", ($response->{error_code} ? "code " . $response->{error_code} . ": " : ""),
            $response->{description} ? $response->{description} : $is_lwp ?
                $tx->status_line : ($tx->error || {})->{message} || "something went wrong!"
    }
    DEBUG and _dprintf "END REQUEST to /%s :: %s", $method, scalar localtime;
    $response
}

sub parse_error
{
    my $r = { type => "unknown", msg => $_[1] || $@ };
    return $r unless $r->{msg} =~ /ERROR: (?:code (?<code>[0-9]+): )?(?<msg>.+?)(?:\s*at .+)?$/m;
    # If the error message has a code, then it comes from the BotAPI. Otherwise, it's our agent
    # telling us something went wrong.
    $r->{type} = exists $+{code} ? "api" : "agent" if $+{msg} ne "something went wrong!";
    # Join our response with the matched groups, then return.
    +{ %$r, %+ }
}

sub agent
{
    shift->{_agent}
}

# Hides the bot's token from the request arguments and improves debugging output.
sub _fix_request_args
{
    my ($self, $args) = @_;
    my $args_cpy = [ @$args ];
    $args_cpy->[0] =~ s/\Q$self->{token}\E/XXXXXXXXX/g;
    # Note for the careful reader: you may remember that the position of Perl's hash keys is
    # undeterminate - that is, an hash has no particular order. This is true, however we are
    # dealing with an array which has a fixed order, so no particular problem arises here.
    # Addendum: the original reference of $args is used here to get rid of `DBG => $postdata`.
    if (@$args > 1 and $args->[1] eq "DBG")
    {
        my (undef, $data) = splice @$args, 1, 2;
        # In the debug output, substitute the JSON-encoded data (which is not human readable) with
        # the raw POST arguments.
        $args_cpy->[2] = $data;
    }
    # Ensure that we do NOT try display async subroutines!
    pop @$args_cpy if ref $args_cpy->[-1] eq "CODE";
    $args_cpy
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
    # ... but error handling is available as well.
    my $result = eval { $api->getMe }
        or die 'Got error message: ', $api->parse_error->{msg};
    # Uploading files is easier than ever.
    $api->sendPhoto ({
        chat_id => 123456,
        photo   => {
            file => '/home/me/cool_pic.png'
        },
        caption => 'Look at my cool photo!'
    });
    # Complex objects are as easy as writing a Perl object.
    $api->sendMessage ({
        chat_id      => 123456,
        # Object: ReplyKeyboardMarkup
        reply_markup => {
            resize_keyboard => \1, # \1 = true when JSONified, \0 = false
            keyboard => [
                # Keyboard: row 1
                [
                    # Keyboard: button 1
                    'Hello world!',
                    # Keyboard: button 2
                    {
                        text => 'Give me your phone number!',
                        request_contact => \1
                    }
                ]
            ]
        }
    });
    # Asynchronous request are supported with Mojo::UserAgent.
    $api = WWW::Telegram::BotAPI->new (
        token => 'my_token',
        async => 1 # WARNING: may fail if Mojo::UserAgent is not available!
    );
    $api->sendMessage ({
        chat_id => 123456,
        text    => 'Hello world!'
    }, sub {
        my ($ua, $tx) = @_;
        die 'Something bad happened!' unless $tx->success;
        say $tx->res->json->{ok} ? 'YAY!' : ':('; # Not production ready!
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

Defaults to C<0>.

=item * C<< force_lwp => 1 >>

Forces the usage of L<LWP::UserAgent> instead of L<Mojo::UserAgent>, even if the latter is
available.

By default, the module tries to load L<Mojo::UserAgent>, and on failure it uses L<LWP::UserAgent>.

=back

=head2 AUTOLOAD

    $api->getMe;
    $api->sendMessage ({
        chat_id => 123456,
        text    => 'Hello world!'
    });
    # with async => 1 and the IOLoop already started
    $api->setWebhook ({ url => 'https://example.com/webhook' }, sub {
        my ($ua, $tx) = @_;
        die unless $tx->success;
        say 'Webhook set!'
    });

This module makes use of L<perlsub/"Autoloading">. This means that B<every current and future
method of the Telegram Bot API can be used by calling its Perl equivalent>, without requiring an
update of the module.

If you'd like to avoid using C<AUTOLOAD>, then you may simply call the L</"api_request"> method
specifying the method name as the first argument.

    $api->api_request ('getMe');

This is, by the way, the exact thing the C<AUTOLOAD> method of this module does.

=head2 api_request

    # Remember: each of these samples can be aliased with
    # $api->methodName ($params).
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
    # complex objects are supported natively since v0.04
    $api->api_request ('sendMessage', {
        chat_id      => 123456,
        reply_markup => {
            keyboard => [ [ 'Button 1', 'Button 2' ] ]
        }
    });
    # with async => 1 and the IOLoop already started
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

If the request is not successful or the server tells us something isn't C<ok>, then this method
dies with the first available error message (either the error description or the status line).
You can make this method non-fatal using C<eval>:

    my $response = eval { $api->api_request ($method, $args) }
        or warn "Request failed with error '$@', but I'm still alive!";

Further processing of error messages can be obtained using L</"parse_error">.

Request parameters can be specified using an hash reference. Additionally, complex objects can be
specified like you do in JSON. See the previous examples or the example bot provided in
L</"SEE ALSO">.

File uploads can be specified using an hash reference containing the following mappings:

=over 4

=item * C<< file => '/path/to/file.ext' >>

Path to the file you want to upload.

Required only if C<content> is not specified.

=item * C<< filename => 'file_name.ext' >>

An optional filename that will be used instead of the real name of the file.

Particularly recommended when C<content> is specified.

=item * C<< content => 'Being a file is cool :-)' >>

The content of the file to send. When using this, C<file> must not be specified.

=item * C<< AnyCustom => 'Header' >>

Custom headers can be specified as hash mappings.

=back

Upload of multiple files is not supported. See L<Mojo::UserAgent::Transactor/"tx"> for more
information about file uploads.

To resend files, you don't need to perform a file upload at all. Just pass the ID as a normal
parameter.

    $api->sendPhoto ({
        chat_id => 123456,
        photo   => $photo_id
    });

When asynchronous requests are enabled, a callback can be specified as an argument.
The arguments passed to the callback are, in order, the user-agent (a L<Mojo::UserAgent> object)
and the response (a L<Mojo::Transaction::HTTP> object). More information can be found in the
documentation of L<Mojo::UserAgent> and L<Mojo::Transaction::HTTP>.

B<NOTE:> ensure that the event loop L<Mojo::IOLoop> is started when using asynchronous requests.
This is not needed when using this module inside a L<Mojolicious> app.

The order of the arguments, except of the first one, does not matter:

    $api->api_request ('sendMessage', $parameters, $callback);
    $api->api_request ('sendMessage', $callback, $parameters); # same thing!

=head2 parse_error

    unless (eval { $api->doSomething(...) }) {
        my $error = $api->parse_error;
        die "Unknown error: $error->{msg}" if $error->{type} eq 'unknown';
        # Handle error gracefully using "type", "msg" and "code" (optional)
    }
    # Or, use it with a custom error message.
    my $error = $api->parse_error ($message);

When sandboxing calls to L<WWW::Telegram::BotAPI> methods using C<eval>, it is useful to parse
error messages using this method.

This method accepts an error message as its first argument, otherwise C<$@> is used.

An hash reference containing the following elements is returned:

=over 4

=item * C<< type => unknown|agent|api >>

The source of the error.

C<api> specifies an error originating from Telegram's BotAPI. When C<type> is C<api>, the key
C<code> is guaranteed to exist.

C<agent> specifies an error originating from this module's user-agent. This may indicate a network
issue, a non-200 HTTP response code or any error not related to the API.

C<unknown> specifies an error with no known source.

=item * C<< msg => ... >>

The error message.

=item * C<< code => ... >>

The error code. B<This key only exists when C<type> is C<api>>.

=back

=head2 agent

    my $user_agent = $api->agent;

Returns the instance of the user-agent used by the module. You can determine if the module is using
L<LWP::UserAgent> or L<Mojo::UserAgent> by using C<isa>:

    my $is_lwp = $user_agent->isa ('LWP::UserAgent');

=head1 DEBUGGING

To perform some cool troubleshooting, you can set the environment variable C<TELEGRAM_BOTAPI_DEBUG>
to a true value:

    TELEGRAM_BOTAPI_DEBUG=1 perl script.pl

This dumps the content of each request and response in a friendly, human-readable way.
It also prints the version and the configuration of the module. As a security measure, the bot's
token is automatically removed from the output of the dump.

B<WARNING:> using this option along with an old Mojolicious version (< 6.22) leads to a warning,
and forces L<LWP::UserAgent> instead of L<Mojo::UserAgent>. This is because L<Mojo::JSON>
used incompatible boolean values up to version 6.21, which led to an horrible death of
L<JSON::MaybeXS> when serializing the data.

=head1 CAVEATS

When asynchronous mode is enabled, no error handling is performed. You have to do it by
yourself as shown in the L</"SYNOPSIS">.

=head1 SEE ALSO

L<LWP::UserAgent>, L<Mojo::UserAgent>,
L<https://core.telegram.org/bots/api>, L<https://core.telegram.org/bots>,
L<example implementation of a Telegram bot|https://git.io/vlOK0>

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
