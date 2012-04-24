#include <signal.h>
#include <execinfo.h>

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define stack_depth 128

void handler(int signo) {
	void** buffer = alloca(sizeof(void*) * stack_depth);
	size_t len = backtrace(buffer, stack_depth);
	backtrace_symbols_fd(buffer, len, 2);
}

MODULE = Devel::CStacktrace				PACKAGE = Devel::CStacktrace

BOOT:
	struct sigaction action;
	action.sa_handler = handler;
	action.sa_flags   = SA_RESETHAND;
	sigaction(SIGSEGV, &action, NULL);
	sigaction(SIGBUS , &action, NULL);
	sigaction(SIGILL , &action, NULL);
	sigaction(SIGFPE , &action, NULL);

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
