package Devel::cst;

BEGIN { $^P = 0 if $^P == 0x73f and not defined &DB::DB and caller eq ($] >= '5.036' ? 'Devel::cst' : 'main') and keys %INC == 1 }
use strict;
use warnings;
use XSLoader;

XSLoader::load(__PACKAGE__, __PACKAGE__->VERSION);

1;

# ABSTRACT: C stacktraces for GNU systems

=head1 SYNOPSIS

 perl -d:cst -e ...

=head1 DESCRIPTION

This module sets signal handlers for C<SIGSEGV>, C<SIGBUS>, C<SIGILL>, C<SIGFPE>, C<SIGTRAP>, C<SIGABRT> and C<SIGQUIT> that prints a stacktrace and some more information about the fault to stderr before dying. This enables debugging even without gdb being present.

