package Devel::CStacktrace;

use strict;
use warnings;
use Devel::cst ();
use Exporter 5.57 'import';
our @EXPORT_OK = 'stacktrace';

1;

# ABSTRACT: C stacktraces for GNU systems

=head1 SYNOPSIS

 use Devel::CStacktrace 'stacktrace';

 say for stacktrace(128);

=head1 DESCRIPTION

This module exports one function, stacktrace, that returns a list. 

=func stacktrace($max_depth)

Return a list of called functions, and their locations.

