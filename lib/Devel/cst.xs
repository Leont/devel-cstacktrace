#include <signal.h>
#include <execinfo.h>

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define add_raw(ptr, length) buffers[counter++] = (struct iovec){ ptr, length }
#define add_ptr(arg) add_raw(arg, strlen(arg))
#define add_string(arg) buffers[counter++] = (struct iovec){ STR_WITH_LEN(arg) }

#ifdef USE_PSIGINFO
#define my_psiginfo(siginfo) psiginfo(siginfo, NULL)
#else

#define ptoha_size (sizeof(void*) * 2 + 2 + 1)
static const char digits[] = "0123456789abcdef";

static void rmemcpy(char* target, const char* source, size_t length) {
	const char* end = source + length - 1;
	while(end >= source)
		*target++ = *end--;
}

static const char nil[] = "(nil)";

static size_t ptoha(char* buffer, void* ptr) {
	char private[ptoha_size];
	char* private_ptr = private;
	uintptr_t num = (uintptr_t)ptr;
	size_t length = 0;
	if (num) {
		while (num) {
			*private_ptr++ = digits[num & 0xF];
			num >>= 4;
			length++;
		}
		memcpy(buffer, "0x", 2);
		rmemcpy(buffer + 2, private, length);
		buffer[length + 2] = '\0';
		return length + 2;
	}
	else {
		memcpy(buffer, nil, sizeof nil);
		return sizeof nil - 1;
	}
}

#define add_addr(desc, ptr) STMT_START {\
	char __address_buffer__[ptoha_size];\
	size_t __buffer__length__ = ptoha(__address_buffer__, ptr);\
	add_string(desc " [");\
	add_raw(__address_buffer__, __buffer__length__);\
	add_string("]");\
	} STMT_END
	
static void my_psiginfo(siginfo_t* info) {
	struct iovec buffers[6];
	const char* desc = sys_siglist[info->si_signo];
	size_t counter = 0;
	add_ptr((char*)desc);
	add_string(" (");
	switch (info->si_signo) {
		case SIGSEGV:
			switch (info->si_code) {
				case SEGV_MAPERR: add_addr("Address not mapped to object", info->si_addr); break;
				case SEGV_ACCERR: add_addr("Invalid permissions for mapped object", info->si_addr); break;
				default: goto backup;
			}
			break;
		case SIGBUS:
			switch (info->si_code) {
				case BUS_ADRALN: add_addr("Invalid address alignment", info->si_addr); break;
				case BUS_ADRERR: add_addr("Nonexistent physical address", info->si_addr); break;
				case BUS_OBJERR: add_addr("Object-specific hardware error", info->si_addr); break;
#ifdef BUS_MCEERR_AR
				case BUS_MCEERR_AR: add_addr("Hardware memory error consumed on a machine check; action required.", info->si_addr); break;
				case BUS_MCEERR_AO: add_addr("Hardware memory error detected in process but not consumed; action optional.", info->si_addr); break;
#endif
				default: goto backup;
			}
			break;
		case SIGILL:
			switch (info->si_code) {
				case ILL_ILLOPC: add_addr("Illegal opcode", info->si_addr); break;
				case ILL_ILLOPN: add_addr("Illegal operand", info->si_addr); break;
				case ILL_ILLADR: add_addr("Illegal addressing mode", info->si_addr); break;
				case ILL_ILLTRP: add_addr("Illegal trap", info->si_addr); break;
				case ILL_PRVOPC: add_addr("Privileged opcode", info->si_addr); break;
				case ILL_PRVREG: add_addr("Privileged register", info->si_addr); break;
				case ILL_COPROC: add_addr("Coprocessor error", info->si_addr); break;
				case ILL_BADSTK: add_addr("Internal stack error", info->si_addr); break;
				default: goto backup;
			}
			break;
		case SIGFPE:
			switch (info->si_code) {
				case FPE_INTDIV: add_addr("Integer divide by zero", info->si_addr); break;
				case FPE_INTOVF: add_addr("Integer overflow", info->si_addr); break;
				case FPE_FLTDIV: add_addr("Floating-point divide by zero", info->si_addr); break;
				case FPE_FLTOVF: add_addr("Floating-point overflow", info->si_addr); break;
				case FPE_FLTUND: add_addr("Floating-point underflow", info->si_addr); break;
				case FPE_FLTRES: add_addr("Floating-point inexact result", info->si_addr); break;
				case FPE_FLTINV: add_addr("Floating-point invalid operation", info->si_addr); break;
				case FPE_FLTSUB: add_addr("Subscript out of range", info->si_addr); break;
				default: goto backup;
			}
			break;
		default:
			backup:
			switch (info->si_code) {
				case SI_USER:
					add_string("Signal sent by kill()");
					break;
				case SI_QUEUE:
					add_string("Signal sent by sigqueue()");
					break;
				case SI_TIMER:
					add_string("Signal generated by the expiration of a timer");
					break;
				case SI_ASYNCIO:
					add_string("Signal generated by the completion of an asynchronous I/O request");
					break;
				case SI_MESGQ:
					add_string("Signal generated by the arrival of a message on an empty message queue");
					break;
#ifdef SI_TKILL
				case SI_TKILL:
					add_string("Signal sent by tkill()");
					break;
#endif
#ifdef SI_ASYNCNL
				case SI_ASYNCNL:
					add_string("Signal generated by the completion of an asynchronous name lookup request");
					break;
#endif
#ifdef SI_SIGIO
				case SI_SIGIO:
					add_string("Signal generated by the completion of an I/O request");
					break;
#endif
#ifdef SI_KERNEL
				case SI_KERNEL:
					add_string("Signal sent by the kernel");
					break;
#endif
				default:
					add_string("Signal with unknown cause or source");

			}
	}
	add_string(")\n");
	if (!writev(2, buffers, counter))
		raise(info->si_signo);
}
#endif

static int stack_depth;

static void handler(int signo, siginfo_t* info, void* context) {
	my_psiginfo(info);

	void** buffer = alloca(sizeof(void*) * stack_depth);
	size_t len = backtrace(buffer, stack_depth);
	/* Skip signal handler itself */
	backtrace_symbols_fd(buffer + 2, len - 2, 2);

	raise(signo);
}

#ifndef MAX
#define MAX(a, b) (a > b ? a : b)
#endif

static int stack_destroy(pTHX_ SV* sv, MAGIC* magic) {
	stack_t altstack;
	altstack.ss_sp = NULL;
	altstack.ss_size = 0;
	altstack.ss_flags = SS_DISABLE;
	sigaltstack(&altstack, NULL);
	return 0;
}

static const MGVTBL stack_magic = { NULL, NULL, NULL, NULL, stack_destroy };

static void S_set_signalstack(pTHX) {
	size_t stacksize = 2 * SIGSTKSZ;
	SV* ret = newSVpvn("", 0);
	SvGROW(ret, stacksize);
	sv_magicext(ret, NULL, PERL_MAGIC_ext, &stack_magic, NULL, 0);
	stack_t altstack;
	altstack.ss_sp = SvPV_nolen(ret);
	altstack.ss_size = stacksize;
	altstack.ss_flags = 0;
	if (sigaltstack(&altstack, NULL))
		Perl_croak(aTHX_ "Couldn't call sigaltstack: %s", strerror(errno));
}
#define set_signalstack() S_set_signalstack(aTHX)

static const int signals_normal[] = { SIGILL, SIGFPE, SIGTRAP, SIGABRT, SIGQUIT, SIGBUS };

static void set_handlers() {
	struct sigaction action;
	int i;
	action.sa_sigaction = handler;
	action.sa_flags     = SA_RESETHAND | SA_SIGINFO;
	sigemptyset(&action.sa_mask);
	for (i = 0; i < sizeof signals_normal / sizeof *signals_normal; i++)
		sigaction(signals_normal[i], &action, NULL);
	action.sa_flags |= SA_ONSTACK;
	sigaction(SIGSEGV, &action, NULL);
}

static volatile int inited = 0;

MODULE = Devel::cst        				PACKAGE = Devel::cst

BOOT:
	/* preload libgcc_s by getting a stacktrace early */
	void** buffer = alloca(sizeof(void*) * 20);
	size_t len = backtrace(buffer, 20);

void
import(package, depth = 20)
	SV* package;
	size_t depth;
	CODE:
	if (!inited++) {
		set_signalstack();
		stack_depth = depth;
		set_handlers();
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
	for (i = 0; i < len; i++)
		mXPUSHp(values[i], strlen(values[i]));
	free(values);
