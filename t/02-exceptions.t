#!/usr/bin/env perl
use strict;
use warnings;
use WWW::Telegram::BotAPI;
use Test::More;

BEGIN {
    eval 'use Test::Fatal; 1' || plan skip_all => 'Test::Fatal required for this test!';
    eval 'use Test::MockObject';
}

plan tests => 12;

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
    my $inst = WWW::Telegram::BotAPI->new (token => 'whatever');
    # 1. Test agent-provided errors
    my $mojo_mock = Test::MockObject->new->set_always ('post',
        Test::MockObject->new->set_false  ('success')
                             ->set_always ('error', { message => ':<' })
                             ->set_always ('res', Test::MockObject->new->set_false ('json')));
    $mojo_mock->set_isa ('Mojo::UserAgent');
    $inst->{_agent} = $mojo_mock; # Do not try this at home!
    like my $msg = exception { $inst->something }, qr/ERROR: :</, 'agent errors are handled';
    test_error ($msg, type => 'agent', msg => ':<');
    # 2. Test API-provided errors
    $mojo_mock->set_always ('post',
        Test::MockObject->new->set_true   ('success')
                             ->set_always ('res', Test::MockObject->new->set_always ('json', {
                                 ok          => 0,
                                 description => 'Meow!',
                                 error_code  => 1337
                             })));
    like $msg = exception { $inst->something }, qr/ERROR: code/, 'api errors are handled';
    test_error ($msg, type => 'api', msg => 'Meow!', code => 1337);
    # 3. Test plain-string error handling
    $mojo_mock->set_always ('post',
        Test::MockObject->new->set_false  ('success')
                             ->set_always ('error', ':<')
                             ->set_always ('res', Test::MockObject->new->set_false ('json')));
    like $msg = exception { $inst->something }, qr/ERROR: :</, 'plain string errors are handled';
    test_error ($msg, type => 'agent', msg => ':<');
}

# Test error messages containing 'at' (issue #19).
test_error ('ERROR: chat not found', type => 'agent', msg => 'chat not found');

sub test_error {
    my ($message, %configuration) = @_;
    my $error = WWW::Telegram::BotAPI->parse_error ($message);
    ok !exists $error->{code}, 'error code must not exist'
        if !exists $configuration{code};
    is_deeply $error, \%configuration, 'parse_error returns expected values';
}
