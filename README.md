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
```

# Description

This module provides an easy to use interface for the
[Telegram Bot API](https://core.telegram.org/bots/api). It also supports async requests out of the
box using [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent), which makes this module easy to integrate with an existing
[Mojolicious](https://metacpan.org/pod/Mojolicious) application.

# Methods

[WWW::Telegram::BotAPI](https://metacpan.org/pod/WWW::Telegram::BotAPI) implements the following methods.

## new

```perl
my $api = WWW::Telegram::BotAPI->new (%options);
```

Creates a new [WWW::Telegram::BotAPI](https://metacpan.org/pod/WWW::Telegram::BotAPI) instance.

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

    **This requires [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent), and the method will croak if it isn't found.**

    **NOTE:** _all_ requests will be asynchronous when this option is enabled, and if a method
    is called without a callback then it will croak.

    Defaults to `0`.

- `force_lwp => 1`

    Forces the usage of [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) instead of [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent), even if the latter is
    available.

    By default, the module tries to load [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent), and on failure it uses [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent).

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
    die unless $tx->success;
    say "Webhook set!"
});
```

This module makes use of ["Autoloading" in perlsub](https://metacpan.org/pod/perlsub#Autoloading). This means that every current and future method
of the Telegram Bot API can be used by calling its Perl equivalent, without requiring an update
of the module.

If you'd like to avoid using `AUTOLOAD`, then you may simply call the ["api\_request"](#api_request) method
specifying the method name as the first argument.

```perl
$api->api_request ('getMe');
```

This is, by the way, the exact thing the `AUTOLOAD` method of this module does.

## api\_request

```perl
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
# with async => 1 and the IOLoop already started
$api->api_request ('getMe', sub {
    my ($ua, $tx) = @_;
    die unless $tx->success;
    # ...
});
```

This method performs an API request. The first argument must be the method name
([here's a list](https://core.telegram.org/bots/api#available-methods)).

Once the request is completed, the response is decoded using [JSON::MaybeXS](https://metacpan.org/pod/JSON::MaybeXS) and then
returned. If [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) is used as the user-agent, then the response is decoded
automatically using [Mojo::JSON](https://metacpan.org/pod/Mojo::JSON).

Parameters can be specified using an hash reference.

File uploads are specified using an hash reference containing the following mappings:

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

Upload of multiple files is not supported. See ["tx" in Mojo::UserAgent::Transactor](https://metacpan.org/pod/Mojo::UserAgent::Transactor#tx) for more
information about file uploads.

To resend files, you don't need to perform a file upload at all. Just pass the ID as a normal
parameter.

```perl
$api->sendPhoto ({
    chat_id => 123456,
    photo   => $photo_id
});
```

When asynchronous requests are enabled, a callback has to be specified as an argument.
The arguments passed to the callback are, in order, the user-agent (a [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) object)
and the response (a [Mojo::Transaction::HTTP](https://metacpan.org/pod/Mojo::Transaction::HTTP) object). More information can be found in the
documentation of [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) and [Mojo::Transaction::HTTP](https://metacpan.org/pod/Mojo::Transaction::HTTP).

**NOTE:** ensure that the event loop [Mojo::IOLoop](https://metacpan.org/pod/Mojo::IOLoop) is started when using asynchronous requests.
This is not needed when using this module inside a [Mojolicious](https://metacpan.org/pod/Mojolicious) app.

The order of the arguments, except of the first one, does not matter:

```perl
$api->api_request ('sendMessage', $parameters, $callback);
$api->api_request ('sendMessage', $callback, $parameters); # same thing!
```

## agent

```perl
my $user_agent = $api->agent;
```

Returns the instance of the user-agent used by the module. You can determine if the module is using
[LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) or [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) by using `isa`:

```perl
my $is_lwp = $user_agent->isa ('LWP::UserAgent');
```

# Debugging

To perform some cool troubleshooting, you can set the environment variable `TELEGRAM_BOTAPI_DEBUG`
to a true value:

```perl
TELEGRAM_BOTAPI_DEBUG=1 perl script.pl
```

This dumps the content of each request and response in a friendly, human-readable way.
It also prints the version and the configuration of the module. As a security measure, the bot's
token is automatically removed from the output of the dump.

**WARNING:** using this option along with an old Mojolicious version (< 6.22) leads to a warning,
and forces [LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent) instead of [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent). This is because [Mojo::JSON](https://metacpan.org/pod/Mojo::JSON)
used incompatible boolean values up to version 6.21, which led to an horrible death of
[JSON::MaybeXS](https://metacpan.org/pod/JSON::MaybeXS) when serializing the data.

# Caveats

When asynchronous mode is enabled, no error handling is performed. You have to do it by
yourself as shown in the ["SYNOPSIS"](#synopsis).

# See also

[LWP::UserAgent](https://metacpan.org/pod/LWP::UserAgent), [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent),
[https://core.telegram.org/bots/api](https://core.telegram.org/bots/api), [https://core.telegram.org/bots](https://core.telegram.org/bots),
[example implementation of a Telegram bot](https://git.io/vlOK0)

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
