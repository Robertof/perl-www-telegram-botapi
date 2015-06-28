#!/usr/bin/env perl
use strict;
use warnings;
use WWW::Telegram::BotAPI;
use Test::More;

BEGIN {
    eval 'use Test::Fatal; 1' || plan skip_all => 'Test::Fatal required for this test!';
    eval 'use Test::MockObject';
}

plan tests => 4;

like (
    exception { WWW::Telegram::BotAPI->new },
    qr/missing 'token'/,
    'a token is required to create a new instance of WWW::Telegram::BotAPI'
);

like (
    exception { WWW::Telegram::BotAPI->new (force_lwp => 1, async => 1, token => 'whatever') },
    qr/Mojo::UserAgent is required/,
    'Mojo::UserAgent is required to use "async"'
);

SKIP: {
    skip 'Test::MockObject required to test Mojo::UserAgent based features', 2
        unless Test::MockObject->can ('new');
    my $mojo_mock = Test::MockObject->new->set_always ('post',
        Test::MockObject->new->set_false ('success')->set_always ('error', { message => ':<' }));
    $mojo_mock->set_isa ('Mojo::UserAgent');
    my $inst = WWW::Telegram::BotAPI->new (token => 'whatever');
    $inst->{_agent} = $mojo_mock;
    like (
        exception { $inst->something },
        qr/ERROR: :</,
        'errors are reported correctly'
    );
    $inst->{async} = 1;
    like (
        exception { $inst->something },
        qr/missing CODE reference/,
        'croak when async is enabled and a callback is missing'
    );
}
