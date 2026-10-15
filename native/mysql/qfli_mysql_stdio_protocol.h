// Option-B preload fork host: stdio lock protocol.
//
// This module implements the agreed finite stdio protocol for forking from a
// process that may hold stdio locks. It is a standalone, testable unit and is
// NOT wired into the production runtime.
//
// Protocol:
//   1. Take bounded ftrylockfile(stdin|stdout|stderr), total <= 500 ms.
//   2. If any acquisition times out, release all acquired locks and retry.
//   3. Hold acquired locks across the fork.
//   4. Parent and child each funlockfile their own copies of 1/2/3.
//   5. In the child, after unlocking, __fpurge inherited buffers (discard, not
//      flush), then redirect/reset handlers, then unmask.
//   6. Never fflush(NULL); never run exit() finalization in the child.
#include <stdio.h>
#include <time.h>

#include <cstddef>

namespace qfli_mysql {

// Public SDK buffer-discard hook. Declared here to avoid private FILE layouts;
// the OHOS musl SDK provides __fpurge.
extern "C" void __fpurge(FILE *stream);

// The three standard streams, in a fixed order.
inline FILE *stdio_stream(int index)
{
    switch (index) {
        case 0: return stdin;
        case 1: return stdout;
        default: return stderr;
    }
}

// Acquires the three stdio locks with a bounded total budget. On success returns
// the number of locks held (3) with acquired[] set. On timeout, releases every
// lock it acquired and returns -1 with acquired[] all false, so a caller can
// retry without holding a partial set.
inline int lock_stdio(std::size_t total_budget_ms, bool acquired[3])
{
    for (int i = 0; i < 3; ++i) acquired[i] = false;
    struct timespec pause = {0, 2 * 1000 * 1000}; // 2 ms between attempts
    std::size_t waited = 0;
    for (;;) {
        bool all = true;
        for (int i = 0; i < 3; ++i) {
            if (acquired[i]) continue;
            if (ftrylockfile(stdio_stream(i)) == 0) {
                acquired[i] = true;
            } else {
                all = false;
            }
        }
        if (all) return 3;
        if (waited >= total_budget_ms) {
            for (int i = 0; i < 3; ++i) {
                if (acquired[i]) {
                    funlockfile(stdio_stream(i));
                    acquired[i] = false;
                }
            }
            return -1;
        }
        nanosleep(&pause, nullptr);
        waited += 2;
    }
}

// Releases the locks this copy holds. Used in both parent and child.
inline void unlock_stdio(bool acquired[3])
{
    for (int i = 0; i < 3; ++i) {
        if (acquired[i]) {
            funlockfile(stdio_stream(i));
            acquired[i] = false;
        }
    }
}

// Child-side post-unlock cleanup: discard inherited stdio buffers (discard, not
// flush) so the child does not replay or deadlock on inherited buffered output.
inline void discard_stdio_buffers()
{
    __fpurge(stdin);
    __fpurge(stdout);
    __fpurge(stderr);
}

} // namespace qfli_mysql
