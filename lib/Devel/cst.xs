#include <signal.h>
#include <execinfo.h>

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

static int stack_depth;

static void handler(int signo, siginfo_t* info, void* context) {
	psiginfo(info, NULL);

	void** buffer = alloca(sizeof(void*) * stack_depth);
	size_t len = backtrace(buffer, stack_depth);
	/* Skip signal handler itself */
	backtrace_symbols_fd(buffer + 2, len - 2, 2);

	raise(signo);
}

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
	action.sa_flags     = SA_RESETHAND | SA_NODEFER | SA_SIGINFO;
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
