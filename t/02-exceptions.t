#!/usr/bin/env perl
use strict;
use warnings;
use WWW::Telegram::BotAPI;
use Test::More;

BEGIN {
    eval 'use Test::Fatal; 1' || plan skip_all => 'Test::Fatal required for this test!';
    eval 'use Test::MockObject';
}

plan tests => 10;

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
    skip 'Test::MockObject required to test Mojo::UserAgent features', 8
        unless Test::MockObject->can ('new');
    my $mojo_mock = Test::MockObject->new->set_always ('post',
        Test::MockObject->new->set_false ('success')->set_always ('error', { message => ':<' })
            ->set_always ('res', Test::MockObject->new->set_false ('json')));
    $mojo_mock->set_isa ('Mojo::UserAgent');
    my $inst = WWW::Telegram::BotAPI->new (token => 'whatever');
    $inst->{_agent} = $mojo_mock;
    like my $msg = exception { $inst->something }, qr/ERROR: :</, 'errors are actually reported 1';
    my $error = $inst->parse_error ($msg);
    is $error->{type}, 'agent', 'error reported by our agent is marked as such';
    is $error->{msg}, ':<', 'error message is correctly parsed';
    ok !exists $error->{code}, 'error code does not exist in agent errors';
    # Update the mock
    $mojo_mock->set_always ('post', Test::MockObject->new->set_true ('success')->set_always ('res',
            Test::MockObject->new->set_always ('json', {
                ok          => 0,
                description => 'Meow!',
                error_code  => 1337
            })
        )
    );
    like $msg = exception { $inst->something }, qr/ERROR: code/, 'errors are actually reported 2';
    $error = $inst->parse_error ($msg);
    is $error->{type}, 'api', 'error reported by the API is marked as such';
    is $error->{msg}, 'Meow!', 'error message is correctly parsed';
    is $error->{code}, 1337, 'error code is correctly parsed';
}
