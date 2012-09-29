#! perl

use strict;
use warnings FATAL => 'all';

use Test::More 0.89;
use Devel::cst;

use Config;
use POSIX qw/:sys_wait_h raise SIGSEGV/;

plan(skip_all => 'no fork') if not $Config{d_fork};

sub check_segv(&@);

my $address_not_mapped = qr/address not mapped to object \[.*?\]/s;

check_segv { raise(SIGSEGV) } qr/from user/, 'Got stacktrace on raise';
check_segv { eval 'package Regexp; use overload q{""} => sub { qr/$_[0]/ }; "".qr//' } $address_not_mapped, 'Got stacktrace on overload recursion';
check_segv { unpack "p", pack "L!", 1; } $address_not_mapped, 'Acme::Boom trick';

sub check_segv(&@) {
	my ($sub, $extra, $message) = @_;

	pipe my $in, my $out or die "Can't pipe: $!";
	my $pid = fork;
	die "Can't fork: $!" if not defined $pid;

	if ($pid) {
		close $out;
		my $status = waitpid -1, 0;
		local $Test::Builder::Level = $Test::Builder::Level + 1;
		ok(WIFSIGNALED(${^CHILD_ERROR_NATIVE}), "Test died properly");
		my ($output, @rest) = <$in>;
		like $output, qr/Segmentation fault \($extra\)/i, $message;
	}
	else {
		open STDERR, '<&', fileno $out;
		$sub->();
		die "Threw no signal?\n";
	}
}

done_testing;
