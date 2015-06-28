#!/usr/bin/env perl
use strict;
use warnings;
use JSON::MaybeXS ();
use Test::More;
use WWW::Telegram::BotAPI;

BEGIN { eval 'use Test::MockObject; 1' || plan skip_all => 'Test::MockObject required for this test!'; }

my @base_constructor_args = ( api_url => '%s/%s', token => 'whatever' );
my @tests = (
    {
        agent => \&lwp_mock,
        resp  => {
            result => 'wow',
            ok     => JSON::MaybeXS::JSON->true
        },
        method => 'getWow'
    },
    {
        agent => \&lwp_mock,
        resp  => {
            ok     => JSON::MaybeXS::JSON->true,
            result => {
                wow_level => 9001
            }
        },
        method => 'getWowLevel',
        request_args => [ { wow_string => 'wow' } ]
    },
    {
        agent => \&lwp_mock,
        resp  => {
            ok     => JSON::MaybeXS::JSON->true,
            result => {
                wow_uploaded => JSON::MaybeXS::JSON->true
            }
        },
        method => 'sendWow',
        # test the translation from Mojo::UserAgent-esque args to args compatible with
        # HTTP::Request::Common
        request_args => [{
            wow_name => 'WOW!!',
            wow_file => { file => '/etc/wow.conf' }
        }],
        expected_request_args => [
            'whatever/sendWow',
            Content => {
                wow_name => 'WOW!!',
                wow_file => [ '/etc/wow.conf', undef ]
            },
            Content_Type => 'form-data'
        ]
    },
    {
        agent  => \&lwp_mock,
        resp   => { lazy_response => '¯\_(ツ)_/¯' },
        method => 'sendLaziness',
        # test sending files with a content instead of a filename
        request_args => [{
            lazy_file => { filename => 'lazy', content => '' }
        }],
        expected_request_args => [
            'whatever/sendLaziness',
            Content => { lazy_file => [ undef, 'lazy', Content => '' ] },
            Content_Type => 'form-data'
        ]
    },
    {
        agent  => \&lwp_mock,
        resp   => { out_of => 'ideas' },
        method => 'sendIdeas',
        # test sending custom headers
        request_args => [{
            idea_file => {
                file     => '/var/big_database.ideas',
                filename => 'ideas.db',
                VeryCool => 'Header'
            }
        }],
        expected_request_args => [
            'whatever/sendIdeas',
            Content => {
                idea_file => [ '/var/big_database.ideas', 'ideas.db', VeryCool => 'Header' ]
            },
            Content_Type => 'form-data'
        ]
    },
    # Mojo::UserAgent tests
    {
        agent  => \&mojo_mock,
        resp   => { password => 'hunter2' },
        method => 'getPassword'
    },
    {
        agent  => \&mojo_mock,
        resp   => { hello => 'mojo' },
        method => 'getGreet',
        request_args => [ { my_nick => 'mojo' } ]
    },
    {
        agent  => \&mojo_mock,
        resp   => { msg => 'Your file smells bad' },
        method => 'sendFile',
        request_args => [{
            file => {
                file => '/home/me/poop.jpg',
                filename => 'flowers.jpg'
            }
        }]
        # No translation is needed when using the Mojo agent.
    },
    # Async time!
    {
        agent  => \&mojo_mock,
        resp   => { msg => 'Did you mean node.js?' },
        method => 'asyncSearch',
        async  => 1,
        request_args => [ { search_term => 'Perl' } ]
    },
    {
        agent  => \&mojo_mock,
        resp   => { msg => 'Your file looks a bit too big' },
        method => 'sendBigFile',
        async  => 1,
        request_args => [{
            big_file => {
                file => '/dev/urandom',
                filename => 'important_document.docx',
                TrustMe => "I'm an engineer"
            }
        }]
    }
);

# Here's the plan...... ok sorry.
plan tests => 5 * @tests + 2; # 2 more tests for the async ones (TODO: automatize the calculation)

# Time to start testing!
foreach my $test (@tests)
{
    # Create the agent first.
    my ($mock_agent, $mock_response, @call_order) = $test->{agent}->($test->{resp});
    # Then our BotAPI instance.
    my $obj = WWW::Telegram::BotAPI->new (
        @base_constructor_args
    );
    # Illegally replace its agent with ours. Hope this does not backfire :-)
    $obj->{_agent} = $mock_agent;
    # Also enable async if needed.
    $obj->{async} = 1 if $test->{async};
    my $method = $test->{method};
    # Prepare the marvelous "mock tester".
    my $mock_tester = sub {
        my $return_value = shift;
        # Test return values (and thus, JSON encoding and decoding)
        is_deeply $return_value, $test->{resp},
            "return value of '$method' is as expected";
        # Test mock call order.
        $mock_agent->called_pos_ok (1, 'post');
        $mock_response->called_pos_ok ($_ + 1, $call_order[$_]) for (0 .. @call_order - 1);
        # Test call arguments.
        my ($name, $args) = $mock_agent->next_call;
        shift @$args; # remove $self from the argument list
        is_deeply $args, ($test->{expected_request_args} ||
            [ # automatically determine the expected request arguments
                # Parsed API url
                sprintf ($obj->{api_url}, $obj->{token}, $method),
                # Mojo specific stuff (put 'form' before the postdata)
                $mock_agent->isa ('Mojo::UserAgent') && $test->{request_args} ? qw[form] : (),
                # The rest of the request arguments.
                @{$test->{request_args} || []}
            ]),
            "arguments of '$name' for '$method' are as expected";
    };
    # Handle asynchronous requests.
    if ($test->{async})
    {
        # Push the callback.
        push @{$test->{request_args}}, $mock_tester;
        # Call the method.
        is $obj->$method (@{$test->{request_args} || []}), 'ASYNC IS COOL',
            "async request for '$method' is really async";
        # Relax.
    }
    else
    {
        # Non-async request.
        $mock_tester->($obj->$method (@{$test->{request_args} || []}));
    }
}

sub lwp_mock
{
    my $response = shift;
    my $mock_response = Test::MockObject->new->set_true ('is_success')->set_always (
        'decoded_content', JSON::MaybeXS::encode_json ($response));
    my $mock_agent = Test::MockObject->new->set_always ('post', $mock_response);
    $mock_agent->set_isa ('LWP::UserAgent');
    ($mock_agent, $mock_response, 'is_success', 'decoded_content')
}

sub mojo_mock
{
    my $response = shift;
    my $mock_response = Test::MockObject->new->set_true ('success')->set_always ('res',
        Test::MockObject->new->set_always ('json', $response));
    my $mock_agent = Test::MockObject->new->mock ('post', sub {
        if (ref (my $cb = pop) eq 'CODE') # Async request
        {
            # Fake the 'success' call when async is used - WWW::Telegram::BotAPI does not
            # verify if the request succeeded when async is true.
            $mock_response->success;
            # Call the callback (no pun intended) with the response.
            $cb->($mock_response->res->json);
            return 'ASYNC IS COOL';
        }
        # Otherwise just return the object.
        $mock_response
    });
    $mock_agent->set_isa ('Mojo::UserAgent');
    ($mock_agent, $mock_response, 'success', 'res')
}
