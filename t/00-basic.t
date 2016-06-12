#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 14 + 2 * 2;

require_ok 'WWW::Telegram::BotAPI'
    || BAIL_OUT "Can't load WWW::Telegram::BotAPI";

can_ok 'WWW::Telegram::BotAPI', 'new', 'api_request', 'agent';

my $inst = WWW::Telegram::BotAPI->new (token => 'something');
isa_ok $inst, 'WWW::Telegram::BotAPI';
like ref $inst->agent, qr/^(LWP|Mojo)::UserAgent$/, 'agent is either LWP or Mojo';

$inst = WWW::Telegram::BotAPI->new (token => 'something', force_lwp => 1);
isa_ok $inst->agent, 'LWP::UserAgent';

# Test parse_error with pre-defined error messages
my $error = $inst->parse_error ("ERROR: your pizza is not reachable!\n");
is $error->{type}, 'agent', 'error type is "agent" when no code is specified';
is $error->{msg}, 'your pizza is not reachable!', 'error message is correctly parsed';
ok !exists $error->{code}, 'error code does not exist in agent errors';

$error = $inst->parse_error ('ERROR: code 403: access to pizzas is forbidden!');
is $error->{type}, 'api', 'error type is "api" when there is a numeric code';
is $error->{msg}, 'access to pizzas is forbidden!', 'error message is correctly parsed';
is $error->{code}, 403, 'access to our pizza is really forbidden (code is correctly parsed)';

$error = $inst->parse_error ("What is a pizza?\n");
is $error->{type}, 'unknown', 'error type is "unknown" when we don\'t know what it is';
is $error->{msg}, "What is a pizza?\n", 'error message is not modified when type == "unknown"';
ok !exists $error->{code}, 'error code does not exist in unknown errors';

# Test AUTOLOAD
for (0 .. 1)
{
    $inst = WWW::Telegram::BotAPI->new (token => 'something', force_lwp => $_, _dry_run => 1);
    is $inst->blaBlaBla(), 1, 'AUTOLOAD works';
    is $inst->something ({ a => 1 }), 1, 'AUTOLOAD works (with POST arguments)';
}
