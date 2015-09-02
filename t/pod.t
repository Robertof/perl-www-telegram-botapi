#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN { eval 'use Test::Pod 1.00; 1' || plan skip_all => 'Test::Pod 1.00 required for testing POD'; }

all_pod_files_ok();
