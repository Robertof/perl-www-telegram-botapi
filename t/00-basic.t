#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 5 + 2 * 2;

require_ok 'WWW::Telegram::BotAPI'
    || BAIL_OUT "Can't load WWW::Telegram::BotAPI";

can_ok 'WWW::Telegram::BotAPI', 'new', 'api_request', 'agent';

my $inst = WWW::Telegram::BotAPI->new (token => 'something');
isa_ok $inst, 'WWW::Telegram::BotAPI';
like ref $inst->agent, qr/^(LWP|Mojo)::UserAgent$/, 'agent is either LWP or Mojo';

$inst = WWW::Telegram::BotAPI->new (token => 'something', force_lwp => 1);
isa_ok $inst->agent, 'LWP::UserAgent';

# Test AUTOLOAD
for (0 .. 1)
{
    $inst = WWW::Telegram::BotAPI->new (token => 'something', force_lwp => $_, _dry_run => 1);
    is $inst->blaBlaBla(), 1, "AUTOLOAD works";
    is $inst->something ({ a => 1 }), 1, "AUTOLOAD works (with POST arguments)";
}
