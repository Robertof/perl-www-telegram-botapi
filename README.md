# Name

WWW::Telegram::BotAPI - Perl implementation of the Telegram Bot API

# Synopsis

```perl
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
    die 'Something bad happened!' if $tx->error;
    say $tx->res->json->{ok} ? 'YAY!' : ':('; # Not production ready!
});
Mojo::IOLoop->start;
```

# Description

This module provides an easy to use interface for the
[Telegram Bot API](https://core.telegram.org/bots/api). It also supports async requests out of the
box using [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent), which makes this module easy to integrate with an existing
[Mojolicious](https://metacpan.org/pod/Mojolicious) application.

# Methods

[WWW::Telegram::BotAPI](https://metacpan.org/pod/WWW%3A%3ATelegram%3A%3ABotAPI) implements the following methods.

## new

```perl
my $api = WWW::Telegram::BotAPI->new (%options);
```

Creates a new [WWW::Telegram::BotAPI](https://metacpan.org/pod/WWW%3A%3ATelegram%3A%3ABotAPI) instance.

**WARNING:** you should only create one instance of this module and reuse it when needed. Calling
`new` each time you run an async request causes unexpected behavior with [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent) and
won't work correctly. See also
[issue #13 on GitHub](https://github.com/Robertof/perl-www-telegram-botapi/issues/13).

`%options` may contain the following:

- `token => 'my_token'`

    The token that will be used to authenticate the bot.

    **This is required! The method will croak if this option is not specified.**

- `api_url => 'https://api.example.com/token/%s/method/%s'`

    A format string that will be used to create the final API URL. The first parameter specifies
    the token, the second one specifies the method.

    Defaults to `https://api.telegram.org/bot%s/%s`.

- `async => 1`

    Enables asynchronous requests.

    **This requires [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent), and the method will croak if it isn't found.**

    Defaults to `0`.

- `force_lwp => 1`

    Forces the usage of [LWP::UserAgent](https://metacpan.org/pod/LWP%3A%3AUserAgent) instead of [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent), even if the latter is
    available.

    By default, the module tries to load [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent), and on failure it uses [LWP::UserAgent](https://metacpan.org/pod/LWP%3A%3AUserAgent).

## AUTOLOAD

```perl
$api->getMe;
$api->sendMessage ({
    chat_id => 123456,
    text    => 'Hello world!'
});
# with async => 1 and the IOLoop already started
$api->setWebhook ({ url => 'https://example.com/webhook' }, sub {
    my ($ua, $tx) = @_;
    die if $tx->error;
    say 'Webhook set!'
});
```

This module makes use of ["Autoloading" in perlsub](https://metacpan.org/pod/perlsub#Autoloading). This means that **every current and future
method of the Telegram Bot API can be used by calling its Perl equivalent**, without requiring an
update of the module.

If you'd like to avoid using `AUTOLOAD`, then you may simply call the ["api\_request"](#api_request) method
specifying the method name as the first argument.

```perl
$api->api_request ('getMe');
```

This is, by the way, the exact thing the `AUTOLOAD` method of this module does.

## api\_request

```perl
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
    die if $tx->error;
    # ...
});
```

This method performs an API request. The first argument must be the method name
([here's a list](https://core.telegram.org/bots/api#available-methods)).

Once the request is completed, the response is decoded using [JSON::MaybeXS](https://metacpan.org/pod/JSON%3A%3AMaybeXS) and then
returned. If [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent) is used as the user-agent, then the response is decoded
automatically using [Mojo::JSON](https://metacpan.org/pod/Mojo%3A%3AJSON).

If the request is not successful or the server tells us something isn't `ok`, then this method
dies with the first available error message (either the error description or the status line).
You can make this method non-fatal using `eval`:

```perl
my $response = eval { $api->api_request ($method, $args) }
    or warn "Request failed with error '$@', but I'm still alive!";
```

Further processing of error messages can be obtained using ["parse\_error"](#parse_error).

Request parameters can be specified using an hash reference. Additionally, complex objects can be
specified like you do in JSON. See the previous examples or the example bot provided in
["SEE ALSO"](#see-also).

File uploads can be specified using an hash reference containing the following mappings:

- `file => '/path/to/file.ext'`

    Path to the file you want to upload.

    Required only if `content` is not specified.

- `filename => 'file_name.ext'`

    An optional filename that will be used instead of the real name of the file.

    Particularly recommended when `content` is specified.

- `content => 'Being a file is cool :-)'`

    The content of the file to send. When using this, `file` must not be specified.

- `AnyCustom => 'Header'`

    Custom headers can be specified as hash mappings.

Upload of multiple files is not supported. See ["tx" in Mojo::UserAgent::Transactor](https://metacpan.org/pod/Mojo%3A%3AUserAgent%3A%3ATransactor#tx) for more
information about file uploads.

To resend files, you don't need to perform a file upload at all. Just pass the ID as a normal
parameter.

```perl
$api->sendPhoto ({
    chat_id => 123456,
    photo   => $photo_id
});
```

When asynchronous requests are enabled, a callback can be specified as an argument.
The arguments passed to the callback are, in order, the user-agent (a [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent) object)
and the response (a [Mojo::Transaction::HTTP](https://metacpan.org/pod/Mojo%3A%3ATransaction%3A%3AHTTP) object). More information can be found in the
documentation of [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent) and [Mojo::Transaction::HTTP](https://metacpan.org/pod/Mojo%3A%3ATransaction%3A%3AHTTP).

**NOTE:** ensure that the event loop [Mojo::IOLoop](https://metacpan.org/pod/Mojo%3A%3AIOLoop) is started when using asynchronous requests.
This is not needed when using this module inside a [Mojolicious](https://metacpan.org/pod/Mojolicious) app.

The order of the arguments, except of the first one, does not matter:

```perl
$api->api_request ('sendMessage', $parameters, $callback);
$api->api_request ('sendMessage', $callback, $parameters); # same thing!
```

## parse\_error

```perl
unless (eval { $api->doSomething(...) }) {
    my $error = $api->parse_error;
    die "Unknown error: $error->{msg}" if $error->{type} eq 'unknown';
    # Handle error gracefully using "type", "msg" and "code" (optional)
}
# Or, use it with a custom error message.
my $error = $api->parse_error ($message);
```

When sandboxing calls to [WWW::Telegram::BotAPI](https://metacpan.org/pod/WWW%3A%3ATelegram%3A%3ABotAPI) methods using `eval`, it is useful to parse
error messages using this method.

**WARNING:** up until version 0.09, this method incorrectly stopped at the first occurence of `at`
in error messages, producing results such as `missing ch` instead of `missing chat`.

This method accepts an error message as its first argument, otherwise `$@` is used.

An hash reference containing the following elements is returned:

- `type => unknown|agent|api`

    The source of the error.

    `api` specifies an error originating from Telegram's BotAPI. When `type` is `api`, the key
    `code` is guaranteed to exist.

    `agent` specifies an error originating from this module's user-agent. This may indicate a network
    issue, a non-200 HTTP response code or any error not related to the API.

    `unknown` specifies an error with no known source.

- `msg => ...`

    The error message.

- `code => ...`

    The error code. **This key only exists when `type` is `api`**.

## agent

```perl
my $user_agent = $api->agent;
```

Returns the instance of the user-agent used by the module. You can determine if the module is using
[LWP::UserAgent](https://metacpan.org/pod/LWP%3A%3AUserAgent) or [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent) by using `isa`:

```perl
my $is_lwp = $user_agent->isa ('LWP::UserAgent');
```

### Using a proxy

Since all the painful networking stuff is delegated to one of the two supported user agents
(either [LWP::UserAgent](https://metacpan.org/pod/LWP%3A%3AUserAgent) or [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent)), you can use their built-in support for proxies
by accessing the user agent object. An example of how this may look like is the following:

```perl
my $user_agent = $api->agent;
if ($user_agent->isa ('LWP::UserAgent')) {
  # Use LWP::Protocol::connect (for https)
  $user_agent->proxy ('https', '...');
  # Or if you prefer, load proxy settings from the environment.
  # $user_agent->env_proxy;
} else {
  # Mojo::UserAgent (builtin)
  $user_agent->proxy->https ('...');
  # Or if you prefer, load proxy settings from the environment.
  # $user_agent->detect;
}
```

**NOTE:** Unfortunately, [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent) returns an opaque `Proxy connection failed` when
something goes wrong with the `CONNECT` request made to the proxy. To alleviate this, since
version 0.12, this module prints the real reason of failure in debug mode. See ["DEBUGGING"](#debugging).
If you need to access the real error reason in your code, please see
[issue #29 on GitHub](https://github.com/Robertof/perl-www-telegram-botapi/issues/29).

# Debugging

To perform some cool troubleshooting, you can set the environment variable `TELEGRAM_BOTAPI_DEBUG`
to a true value:

```perl
TELEGRAM_BOTAPI_DEBUG=1 perl script.pl
```

This dumps the content of each request and response in a friendly, human-readable way.
It also prints the version and the configuration of the module. As a security measure, the bot's
token is automatically removed from the output of the dump.

Since version 0.12, enabling this flag also gives more details when a proxy connection fails.

**WARNING:** using this option along with an old Mojolicious version (< 6.22) leads to a warning,
and forces [LWP::UserAgent](https://metacpan.org/pod/LWP%3A%3AUserAgent) instead of [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent). This is because [Mojo::JSON](https://metacpan.org/pod/Mojo%3A%3AJSON)
used incompatible boolean values up to version 6.21, which led to an horrible death of
[JSON::MaybeXS](https://metacpan.org/pod/JSON%3A%3AMaybeXS) when serializing the data.

# Caveats

When asynchronous mode is enabled, no error handling is performed. You have to do it by
yourself as shown in the ["SYNOPSIS"](#synopsis).

# See also

[LWP::UserAgent](https://metacpan.org/pod/LWP%3A%3AUserAgent), [Mojo::UserAgent](https://metacpan.org/pod/Mojo%3A%3AUserAgent),
[https://core.telegram.org/bots/api](https://core.telegram.org/bots/api), [https://core.telegram.org/bots](https://core.telegram.org/bots),
[example implementation of a Telegram bot](https://git.io/vlOK0),
[example implementation of an async Telegram bot](https://git.io/vDrwL)

# Author

Roberto Frenna (robertof AT cpan DOT org)

# Bugs

Please report any bugs or feature requests to
[https://github.com/Robertof/perl-www-telegram-botapi](https://github.com/Robertof/perl-www-telegram-botapi).

# Thanks

Thanks to [the authors of Mojolicious](https://metacpan.org/pod/Mojolicious) for inspiration about the license and the
documentation.

# License

Copyright (C) 2015, Roberto Frenna.

This program is free software, you can redistribute it and/or modify it under the terms of the
Artistic License version 2.0.
