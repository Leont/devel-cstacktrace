#include <signal.h>
#include <execinfo.h>

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define stack_depth 128

#define add_string(arg) write(2, STR_WITH_LEN(arg))
#define add_line(arg) add_string(arg "\n")

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-result"

void write_addrinfo(const char* format, void* addr) {
	/* This is not really allowed per POSIX but seems safe enough */
	char buffer[80];
	int len = snprintf(buffer, 80, format, addr);
	write(2, buffer, len);
}
#define add_addr(format, ptr) write_addrinfo(format " at 0x%p\n", ptr)

void write_siginfo(siginfo_t* info) {
	switch (info->si_signo) {
		case SIGSEGV:
			switch (info->si_code) {
				case SEGV_MAPERR: add_addr("address not mapped to object", info->si_addr); break;
				case SEGV_ACCERR: add_addr("invalid permissions for mapped object", info->si_addr); break;
				default: goto backup;
			}
			break;
		case SIGBUS:
			switch (info->si_code) {
				case BUS_ADRALN: add_addr("invalid address alignment", info->si_addr); break;
				case BUS_ADRERR: add_addr("nonexistent physical address", info->si_addr); break;
				case BUS_OBJERR: add_addr("object-specific hardware error", info->si_addr); break;
#ifdef BUS_MCEERR_AR
				case BUS_MCEERR_AR: add_addr("Hardware memory error consumed on a machine check; action required.", info->si_addr); break;
				case BUS_MCEERR_AO: add_addr("Hardware memory error detected in process but not consumed; action optional.", info->si_addr); break;
#endif
				default: goto backup;
			}
			break;
		case SIGILL:
			switch (info->si_code) {
				case ILL_ILLOPC: add_addr("illegal opcode", info->si_addr); break;
				case ILL_ILLOPN: add_addr("illegal operand", info->si_addr); break;
				case ILL_ILLADR: add_addr("illegal addressing mode", info->si_addr); break;
				case ILL_ILLTRP: add_addr("illegal trap", info->si_addr); break;
				case ILL_PRVOPC: add_addr("privileged opcode", info->si_addr); break;
				case ILL_PRVREG: add_addr("privileged register", info->si_addr); break;
				case ILL_COPROC: add_addr("coprocessor error", info->si_addr); break;
				case ILL_BADSTK: add_addr("internal stack error", info->si_addr); break;
				default: goto backup;
			}
			break;
		case SIGFPE:
			switch (info->si_code) {
				case FPE_INTDIV: add_addr("integer divide by zero", info->si_addr); break;
				case FPE_INTOVF: add_addr("integer overflow", info->si_addr); break;
				case FPE_FLTDIV: add_addr("floating-point divide by zero", info->si_addr); break;
				case FPE_FLTOVF: add_addr("floating-point overflow", info->si_addr); break;
				case FPE_FLTUND: add_addr("floating-point underflow", info->si_addr); break;
				case FPE_FLTRES: add_addr("floating-point inexact result", info->si_addr); break;
				case FPE_FLTINV: add_addr("floating-point invalid operation", info->si_addr); break;
				case FPE_FLTSUB: add_addr("subscript out of range", info->si_addr); break;
				default: goto backup;
			}
			break;
		default:
			backup:
			switch (info->si_code) {
				case SI_USER: 
					add_line("from user");
					break;
				case SI_KERNEL:
					add_line("from kernel");
					break;
				default:
					add_line("unknown cause or source");
			}
	}
}

static struct iovec name[NSIG];

void handler(int signo, siginfo_t* info, void* context) {
	void** buffer = alloca(sizeof(void*) * stack_depth);
	size_t len = backtrace(buffer, stack_depth);
	write(2, STR_WITH_LEN("Received signal "));
	if (name[signo].iov_len) {
		write(2, name[signo].iov_base, strlen(name[signo].iov_base));
	}
	else {
		char signal_str[2] = { '0' + signo / 10, '0' + signo % 10 };
		write(2, signal_str, 2);
	}
	write(2, STR_WITH_LEN(" : "));
	write_siginfo(info);
	backtrace_symbols_fd(buffer, len, 2);
	raise(signo);
}

#pragma GCC diagnostic pop

static const int signals[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE };
static int inited = 0;

#define STACKSIZE 8096
char altstack_buffer[STACKSIZE];

MODULE = Devel::cst        				PACKAGE = Devel::cst

BOOT:
	name[SIGSEGV] = (struct iovec){ STR_WITH_LEN("SIGSEGV") };
	name[SIGBUS]  = (struct iovec){ STR_WITH_LEN("SIGBUS") };
	name[SIGILL]  = (struct iovec){ STR_WITH_LEN("SIGILL") };
	name[SIGFPE]  = (struct iovec){ STR_WITH_LEN("SIGFPE") };

void
import(package)
	SV* package;
	CODE:
	if (!inited) {
		struct sigaction action;
		int i;
		stack_t altstack = { altstack_buffer, 0, STACKSIZE };
		sigaltstack(&altstack, NULL);
		action.sa_sigaction = handler;
		action.sa_flags   = SA_RESETHAND | SA_SIGINFO | SA_ONSTACK;
		sigemptyset(&action.sa_mask);
		for (i = 0; i < sizeof signals / sizeof *signals; i++)
			sigaction(signals[i], &action, NULL);
		inited = 1;
	}

MODULE = Devel::cst        				PACKAGE = Devel::CStacktrace

void
stacktrace(depth)
	size_t depth;
	PREINIT:
	void** buffer;
	size_t len;
	char** values;
	int i;
	PPCODE:
	Newx(buffer, depth, void*);
	len = backtrace(buffer, depth);
	values = backtrace_symbols(buffer, len);
	for (i = 0; i < len; i++) {
		mXPUSHp(values[i], strlen(values[i]));
	}
