// Linux test for the preload fork stdio protocol.
#include "qfli_mysql_stdio_protocol.h"

#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include <atomic>
#include <cstdlib>

namespace {

int failures = 0;

void check(bool condition, const char *message)
{
    if (condition) {
        printf("ok   %s\n", message);
    } else {
        printf("FAIL %s\n", message);
        ++failures;
    }
}

std::atomic<bool> g_hold{false};
std::atomic<bool> g_holding{false};

void *stderr_holder(void *)
{
    // Hold stderr's lock so the acquire path must time out and release cleanly.
    flockfile(stderr);
    g_holding.store(true);
    while (g_hold.load()) {
        struct timespec pause = {0, 5 * 1000 * 1000};
        nanosleep(&pause, nullptr);
    }
    funlockfile(stderr);
    return nullptr;
}

} // namespace

int main()
{
    // 1. Normal acquisition when nothing contends.
    bool acquired[3] = {false, false, false};
    check(qfli_mysql::lock_stdio(500, acquired) == 3, "acquires all stdio locks when free");
    qfli_mysql::unlock_stdio(acquired);
    check(!acquired[0] && !acquired[1] && !acquired[2], "unlock releases all locks");

    // 2. Timeout path: another thread holds stderr; acquire must fail AND release
    //    the locks it did take (no partial hold), within the bounded budget.
    g_hold.store(true);
    g_holding.store(false);
    pthread_t holder;
    pthread_create(&holder, nullptr, stderr_holder, nullptr);
    while (!g_holding.load()) usleep(1000);
    bool contended[3] = {false, false, false};
    const int result = qfli_mysql::lock_stdio(200, contended);
    check(result == -1, "times out when stderr is held");
    check(!contended[0] && !contended[1] && !contended[2], "releases all partial locks on timeout");
    // stdin/stdout must be usable again (proving they were released).
    check(ftrylockfile(stdin) == 0, "stdin lock usable after timeout release");
    funlockfile(stdin);
    g_hold.store(false);
    pthread_join(holder, nullptr);

    // 3. Repeated forks with concurrent parent stderr output, using the protocol.
    int fork_failures = 0;
    for (int iteration = 0; iteration < 8; ++iteration) {
        // Parent produces stderr output (may take the stderr lock).
        fprintf(stderr, "parent stderr during fork %d\n", iteration);
        bool locked[3] = {false, false, false};
        if (qfli_mysql::lock_stdio(500, locked) != 3) {
            ++fork_failures;
            continue;
        }
        const pid_t pid = fork();
        if (pid == 0) {
            // Child: unlock its own copies, discard inherited buffers, exit.
            qfli_mysql::unlock_stdio(locked);
            qfli_mysql::discard_stdio_buffers();
            _exit(0);
        }
        qfli_mysql::unlock_stdio(locked);
        int status = 0;
        waitpid(pid, &status, 0);
        if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) ++fork_failures;
    }
    check(fork_failures == 0, "repeated forks with concurrent stderr all exit cleanly");

    if (failures == 0) printf("all stdio protocol checks passed\n");
    return failures == 0 ? 0 : 1;
}
