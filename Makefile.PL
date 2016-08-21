#!/usr/bin/env perl
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile (
    AUTHOR           => 'Roberto Frenna <robertof@cpan.org>',
    NAME             => 'WWW::Telegram::BotAPI',
    VERSION_FROM     => 'lib/WWW/Telegram/BotAPI.pm',
    ABSTRACT         => 'Perl implementation of the Telegram Bot API',
    LICENSE          => 'artistic_2',
    PREREQ_PM        => {
        map { $_ => 0 } qw[Carp Encode LWP::UserAgent LWP::Protocol::https JSON::MaybeXS]
    },

    (eval { ExtUtils::MakeMaker->VERSION(6.46) } ?
       (META_MERGE => {
            resources => {
                license    => 'http://www.opensource.org/licenses/artistic-license-2.0',
                bugtracker => 'https://github.com/Robertof/perl-www-telegram-botapi/issues',
                repository => 'https://github.com/Robertof/perl-www-telegram-botapi'
            } 
        }) : ()
    )
);

# Create the target "README.md" used to generate the markdown version of the POD documentation.
# It uses the script gen_doc, which requires Pod::Markdown.
# Thanks to the author of Mojolicious::Plugin::DigestAuth, who used a similar section in its
# makefile to do the same thing.
sub MY::postamble
{
    my $self = shift;
    <<END_MAKE;
README.md: $self->{VERSION_FROM}
\t\$(PERLRUN) gen_doc $self->{VERSION_FROM}
END_MAKE
}
