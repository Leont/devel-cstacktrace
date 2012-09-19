package Devel::CStacktrace;

use strict;
use warnings;
use Devel::cst ();
use Sub::Exporter::Progressive -setup => { exports => [qw/stacktrace/] };

1;

# ABSTRACT: C stacktraces for GNU systems

=head1 SYNOPSIS

 say for stacktrace(128);

=head1 DESCRIPTION

This module exports one function, stacktrace, that returns a list. 

=func stacktrace($max_depth)

Return a list of called functions, and their locations.

