#! perl

use strict;
use warnings FATAL => 'all';

use Test::More 0.89;
use Test::Exception;

use Devel::CStacktrace qw/stacktrace/;

lives_ok { stacktrace(12) } 'Can lookup stacktrace';

done_testing;
