package Devel::cst;

use strict;
use warnings;
use XSLoader;
XSLoader::load(__PACKAGE__, __PACKAGE__->VERSION);

sub DB::DB {}

# ABSTRACT: C stacktraces for GNU systems

=head1 SYNOPSIS

 perl -d:cst -e ...

=head1 DESCRIPTION

This module sets signal handlers for C<SIGSEGV>, C<SIGBUS>, C<SIGILL> and C<SIGFPE> that prints a stacktrace and some more information about the fault to stderr before dying. This enables debugging even without gdb being present.

