#include <signal.h>
#include <execinfo.h>

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define add_raw(ptr, length) buffers[counter++] = (struct iovec){ ptr, length }
#define add_ptr(arg) add_raw(arg, strlen(arg))
#define add_string(arg) buffers[counter++] = (struct iovec){ STR_WITH_LEN(arg) }

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
					add_string("from user");
					break;
				case SI_KERNEL:
					add_string("from kernel");
					break;
				default:
					add_string("unknown cause or source");
			}
	}
	add_string(")\n");
	writev(2, buffers, counter);
}

static int stack_depth;

static void handler(int signo, siginfo_t* info, void* context) {
	void** buffer = alloca(sizeof(void*) * stack_depth);
	size_t len = backtrace(buffer, stack_depth);
	my_psiginfo(info);
	/* Skip signal handler itself */
	backtrace_symbols_fd(buffer + 2, len - 2, 2);
	raise(signo);
}

static const int signals[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE };

#ifndef MAX
#define MAX(a, b) (a > b ? a : b)
#endif

static int stack_destroy(pTHX_ SV* sv, MAGIC* magic) {
	stack_t stack = (stack_t){ NULL, SS_DISABLE, 0 };
	sigaltstack(&stack, NULL);
	return 0;
}

static const MGVTBL stack_magic = { NULL, NULL, NULL, NULL, stack_destroy };

static void S_set_signalstack(pTHX_ int depth) {
	size_t stacksize = MAX(sizeof(void*) * depth + 2 * MINSIGSTKSZ, SIGSTKSZ);
	SV* ret = newSVpvn("", 0);
	SvGROW(ret, stacksize);
	sv_magicext(ret, NULL, PERL_MAGIC_ext, &stack_magic, NULL, 0);
	stack_t altstack = { SvPV_nolen(ret), 0, stacksize };
	sigaltstack(&altstack, NULL);
}
#define set_signalstack(depth) S_set_signalstack(aTHX_ depth)

static void set_handlers() {
	struct sigaction action;
	int i;
	action.sa_sigaction = handler;
	action.sa_flags   = SA_RESETHAND | SA_SIGINFO | SA_ONSTACK;
	sigemptyset(&action.sa_mask);
	for (i = 0; i < sizeof signals / sizeof *signals; i++)
		sigaction(signals[i], &action, NULL);
}

static volatile int inited = 0;

MODULE = Devel::cst        				PACKAGE = Devel::cst

void
import(package, depth = 20)
	SV* package;
	size_t depth;
	CODE:
	if (!inited++) {
		set_signalstack(depth);
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
