package Devel::CStacktrace;

use strict;
use warnings;
use XSLoader;
use Sub::Exporter::Progressive -setup => { exports => [qw/stacktrace/] };

XSLoader::load(__PACKAGE__, __PACKAGE__->VERSION);

1;

# ABSTRACT: C stacktraces for GNU systems

__END__

=head1 SYNOPSIS

 say for stacktrace(128);

=head1 DESCRIPTION

This module exports one function, stacktrace, that returns a list. It also sets signal handlers for C<SIGSEGV>, C<SIGBUS>, C<SIGILL> and C<SIGFPE> that prints a stacktrace and some more information about the fault to stderr before dying.

=func stacktrace($max_depth)

Return a list of called functions, and their locations.

