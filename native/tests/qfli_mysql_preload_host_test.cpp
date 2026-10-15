#include "qfli_mysql_host.h"
#include "qfli_mysql_proto_probe.h"

#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <string>
#include <sys/wait.h>
#include <unistd.h>

namespace {
int failures = 0;
pid_t original_process = 0;

void check(bool condition, const char *message)
{
    std::printf("%s %s\n", condition ? "PASS" : "FAIL", message);
    if (!condition) ++failures;
}

void check_failed_child(const ProtoResult &result)
{
    check(result.childPid > 1, "failed start records the attempted child PID");
    check(!result.owned && result.pendingPid == -1,
          "confirmed termination does not retain pending ownership");
    check(qfli_mysql::poll_child(result.childPid).state == qfli_mysql::ChildState::Unknown,
          "failed child is released from tracked ownership");
    int status = 0;
    errno = 0;
    check(waitpid(result.childPid, &status, WNOHANG) == -1 && errno == ECHILD,
          "failed child was reaped without leaving a zombie");
}

qfli_mysql::ChildStatus await_exit(int pid)
{
    qfli_mysql::ChildStatus status;
    for (int attempt = 0; attempt < 100; ++attempt) {
        status = qfli_mysql::poll_child(pid);
        if (status.exited()) break;
        usleep(10000);
    }
    return status;
}
} // namespace

// Linker-only fault injection: production builds contain neither this wrapper
// nor a runtime switch. Parent fork-thread creation always uses the real call.
extern "C" int __real_pthread_create(pthread_t *, const pthread_attr_t *,
                                     void *(*)(void *), void *);
extern "C" int __wrap_pthread_create(pthread_t *thread, const pthread_attr_t *attributes,
                                     void *(*entry)(void *), void *argument)
{
    if (getpid() != original_process) {
        const char *mode = std::getenv("QFLI_PRELOAD_HOST_TEST_MODE");
        if (mode != nullptr && std::strcmp(mode, "watchdog_failure") == 0) return EAGAIN;
        sigset_t current;
        if (pthread_sigmask(SIG_SETMASK, nullptr, &current) != 0 ||
            !sigismember(&current, SIGTERM) || !sigismember(&current, SIGINT) ||
            !sigismember(&current, SIGHUP) || !sigismember(&current, SIGQUIT)) _exit(45);
    }
    return __real_pthread_create(thread, attributes, entry, argument);
}

int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    // A broken deadline must fail the regression instead of hanging CTest.
    alarm(15);
    original_process = getpid();
    unsetenv("QFLI_PRELOAD_HOST_TEST_MODE");
    ProtoResult normal;
    const int pid = qfli_mysql_preload_start(argv[1], "{}", &normal);
    check(pid > 1 && normal.error[0] == '\0', "normal preload start succeeds");
    const auto status = await_exit(pid);
    check(status.exited() && status.exit_code == 0, "successful child retains exact exit status");
    check(qfli_mysql::release_child(pid) == 0, "successful child ownership can be released");

    ProtoResult self_test;
    check(qfli_mysql_proto_probe(argv[1], &self_test) && self_test.childExitIsolated,
          "debug exit self-test still succeeds through tracked lifecycle");
    check(qfli_mysql::poll_child(self_test.childPid).state == qfli_mysql::ChildState::Unknown,
          "debug self-test releases child ownership");

    setenv("QFLI_PRELOAD_HOST_TEST_MODE", "stall", 1);
    const auto started = std::chrono::steady_clock::now();
    ProtoResult stalled;
    const int stalled_pid = qfli_mysql_preload_start(argv[1], "{}", &stalled);
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - started).count();
    check(stalled_pid == -1, "pre-handshake timeout reports a failed start");
    check(elapsed >= 1800 && elapsed < 4000, "stalled handshake obeys its two-second deadline");
    check(std::strstr(stalled.error, "handshake") != nullptr,
          "handshake timeout retains its diagnostic");
    check_failed_child(stalled);

    setenv("QFLI_PRELOAD_HOST_TEST_MODE", "exit", 1);
    ProtoResult exited;
    check(qfli_mysql_preload_start(argv[1], "{}", &exited) == -1,
          "child exit before handshake reports a failed start");
    check_failed_child(exited);

    const int fixture = open("/dev/null", O_RDONLY);
    check(fixture >= 3 && (fcntl(fixture, F_GETFD) & FD_CLOEXEC) == 0,
          "parent opens an inheritable descriptor fixture");
    const std::string fixture_text = std::to_string(fixture);
    setenv("QFLI_PRELOAD_HOST_TEST_MODE", "fd", 1);
    setenv("QFLI_PRELOAD_HOST_TEST_FD", fixture_text.c_str(), 1);
    ProtoResult descriptor_result;
    const int descriptor_pid = qfli_mysql_preload_start(argv[1], "{}", &descriptor_result);
    check(descriptor_pid > 1 && await_exit(descriptor_pid).exit_code == 0,
          "preload child closes the inherited non-CLOEXEC descriptor");
    check(qfli_mysql::release_child(descriptor_pid) == 0, "descriptor-check child can be released");
    check(fcntl(fixture, F_GETFD) >= 0, "child descriptor cleanup preserves the parent's fixture");
    close(fixture);
    unsetenv("QFLI_PRELOAD_HOST_TEST_FD");

    sigset_t unrelated;
    sigset_t previous;
    sigemptyset(&unrelated);
    sigaddset(&unrelated, SIGUSR1);
    check(pthread_sigmask(SIG_BLOCK, &unrelated, &previous) == 0,
          "parent establishes an unrelated signal-mask fixture");
    setenv("QFLI_PRELOAD_HOST_TEST_MODE", "mask", 1);
    ProtoResult mask_result;
    const int mask_pid = qfli_mysql_preload_start(argv[1], "{}", &mask_result);
    check(mask_pid > 1 && await_exit(mask_pid).exit_code == 0,
          "watchdog inherits blocked Oracle signals and entry thread restores its original mask");
    check(qfli_mysql::release_child(mask_pid) == 0, "signal-mask child can be released");
    pthread_sigmask(SIG_SETMASK, &previous, nullptr);

    setenv("QFLI_PRELOAD_HOST_TEST_MODE", "watchdog_failure", 1);
    ProtoResult watchdog_failure;
    check(qfli_mysql_preload_start(argv[1], "{}", &watchdog_failure) == -1,
          "watchdog creation failure refuses startup before the ready handshake");
    check(std::strstr(watchdog_failure.error, "watchdog") != nullptr,
          "watchdog failure preserves a specific diagnostic");
    check_failed_child(watchdog_failure);
    unsetenv("QFLI_PRELOAD_HOST_TEST_MODE");
    alarm(0);
    return failures == 0 ? 0 : 1;
}
