// Test closure for the actual production preload host. Only the Oracle entry
// is replaced; fork, handshake, PID ownership and cleanup use production code.
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>

extern "C" void qfli_mysql_proto_report(int *threads, int *atfork, int *exits)
{
    *threads = 0;
    *atfork = 0;
    *exits = 0;
}

extern "C" int qfli_mysql_proto_ready() { return 1; }

extern "C" void qfli_mysql_proto_enter_child_scope()
{
    const char *mode = std::getenv("QFLI_PRELOAD_HOST_TEST_MODE");
    if (mode != nullptr && std::strcmp(mode, "stall") == 0) {
        const struct timespec pause = {6, 0};
        nanosleep(&pause, nullptr);
    }
    if (mode != nullptr && std::strcmp(mode, "exit") == 0) _exit(9);
}

extern "C" void qfli_mysql_proto_child_exit(int code) { _exit(code); }
extern "C" void qfli_mysql_child_main(const char *)
{
    const char *mode = std::getenv("QFLI_PRELOAD_HOST_TEST_MODE");
    if (mode != nullptr && std::strcmp(mode, "fd") == 0) {
        const char *text = std::getenv("QFLI_PRELOAD_HOST_TEST_FD");
        const int descriptor = text == nullptr ? -1 : std::atoi(text);
        errno = 0;
        _exit(descriptor >= 3 && fcntl(descriptor, F_GETFD) == -1 && errno == EBADF ? 0 : 42);
    }
    if (mode != nullptr && std::strcmp(mode, "mask") == 0) {
        sigset_t current;
        if (pthread_sigmask(SIG_SETMASK, nullptr, &current) != 0) _exit(43);
        if (sigismember(&current, SIGTERM) || sigismember(&current, SIGINT) ||
            sigismember(&current, SIGHUP) || sigismember(&current, SIGQUIT) ||
            !sigismember(&current, SIGUSR1)) _exit(44);
    }
    _exit(0);
}
