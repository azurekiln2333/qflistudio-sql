// Option-B prototype probe host (DEBUG ONLY).
//
// Loads the private, statically linked Oracle prototype DSO with
// dlopen(RTLD_NOW | RTLD_LOCAL) inside the app process (a supported
// native-library load, not exec), reads the constructor-time thread/atfork
// counters captured by the DSO's own link-time wrappers, and verifies
// child-local exit interception in a forked child.
//
// Only compiled when QFLI_MYSQL_PRELOAD_PROTOTYPE is set; it does not touch the
// production runtime or production data (the probe uses an isolated root).
#include "qfli_mysql_proto_probe.h"
#include "qfli_mysql_stdio_protocol.h"
#include "qfli_mysql_host.h"

#include <dlfcn.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <cstddef>

namespace {

using ReportFn = void (*)(int *, int *, int *);
using ReadyFn = int (*)();
using EnterChildScopeFn = void (*)();
using ChildExitFn = void (*)(int);
using ServerEntryFn = void (*)(const char *);

// Parent-death watchdog for the preloaded child. The old exec launcher no longer
// runs, so the child polls getppid() and _exits when the owning app dies. Uses
// only standard calls; the child never lazily dlsym's.
void *watch_parent_thread(void *argument)
{
    const pid_t parent = static_cast<pid_t>(reinterpret_cast<intptr_t>(argument));
    const struct timespec interval = {0, 200 * 1000 * 1000};
    for (;;) {
        if (getppid() != parent) _exit(125);
        nanosleep(&interval, nullptr);
    }
    return nullptr;
}

bool watch_parent(pid_t parent)
{
    // Oracle uses a dedicated signal-handling thread. The extra watchdog must
    // inherit its termination signals blocked, as in the exec launcher.
    sigset_t blocked;
    sigset_t previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGTERM);
    sigaddset(&blocked, SIGINT);
    sigaddset(&blocked, SIGHUP);
    sigaddset(&blocked, SIGQUIT);
    if (pthread_sigmask(SIG_BLOCK, &blocked, &previous) != 0) return false;
    pthread_t thread;
    const int created = pthread_create(&thread, nullptr, watch_parent_thread,
        reinterpret_cast<void *>(static_cast<intptr_t>(parent)));
    const int restored = pthread_sigmask(SIG_SETMASK, &previous, nullptr);
    if (created != 0 || restored != 0) return false;
    pthread_detach(thread);
    return true;
}

bool copy_error(char *target, std::size_t size, const char *message)
{
    if (message == nullptr) message = "unknown error";
    std::size_t length = strlen(message);
    if (length >= size) length = size - 1;
    memcpy(target, message, length);
    target[length] = '\0';
    return false;
}

// Runs on a dedicated fresh pthread that holds no preowned recursive stdio
// locks. Applies the SAME finite protocol for both the exit self-test and the
// real server start:
//   bounded stdio locks (abort BEFORE fork on failure)
//   -> fork -> child: unlock/purge, enter_scope, reset signals/FDs, watchdog,
//      then either the exit self-test or the real server entry
//   -> parent: release locks, bounded handshake, bounded owned-child cleanup.
enum class ForkMode { ExitSelfTest, ServerEntry };

struct ForkJob {
    ForkMode mode = ForkMode::ExitSelfTest;
    EnterChildScopeFn enter_scope = nullptr;
    ChildExitFn child_exit = nullptr;
    ServerEntryFn entry = nullptr;
    const char *entry_params = nullptr;
    ProtoResult *result = nullptr;
};

// Resets signal handlers and closes inherited descriptors in the child so the
// forked server does not inherit the app's handlers or stray FDs. Uses only
// standard, async-signal-safe calls.
void child_reset_signals_and_fds(int keep_descriptor, int descriptor_count)
{
    signal(SIGTERM, SIG_DFL);
    signal(SIGINT, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    signal(SIGHUP, SIG_DFL);
    // close_range is sandbox filtered on the phone. The portable close loop
    // is also used by the exec host. Its upper bound is computed before fork.
    for (int descriptor = 3; descriptor < descriptor_count; ++descriptor) {
        if (descriptor != keep_descriptor) close(descriptor);
    }
}

// poll() enforces the deadline even if the child remains alive without writing
// a handshake byte. A blocking read inside a retry loop cannot enforce one.
char await_handshake(int descriptor)
{
    struct timespec started;
    if (clock_gettime(CLOCK_MONOTONIC, &started) != 0) return '\0';
    const int64_t deadline = static_cast<int64_t>(started.tv_sec) * 1000 +
        started.tv_nsec / 1000000 + 2000;
    for (;;) {
        struct timespec now;
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return '\0';
        const int64_t remaining = deadline -
            (static_cast<int64_t>(now.tv_sec) * 1000 + now.tv_nsec / 1000000);
        if (remaining <= 0) return '\0';
        struct pollfd descriptor_state = {descriptor, POLLIN, 0};
        const int status = poll(&descriptor_state, 1, static_cast<int>(remaining));
        if (status < 0 && errno == EINTR) continue;
        if (status <= 0) return '\0';
        char byte = 0;
        const ssize_t got = read(descriptor, &byte, 1);
        if (got < 0 && errno == EINTR) continue;
        return got == 1 ? byte : '\0';
    }
}

// All forked children are adopted before the handshake. Failed starts use the
// same tracked lifecycle as successful starts and retain a pending PID only if
// bounded termination cannot confirm an exit.
void cancel_owned_child(int pid, ProtoResult *result)
{
    qfli_mysql::signal_child(pid, true);
    const struct timespec pause = {0, 10 * 1000 * 1000};
    for (int attempt = 0; attempt < 50; ++attempt) {
        const auto status = qfli_mysql::poll_child(pid);
        if (status.exited()) {
            qfli_mysql::release_child(pid);
            return;
        }
        nanosleep(&pause, nullptr);
    }
    result->owned = true;
    result->pendingPid = pid;
}

void *fork_job_main(void *argument)
{
    auto *job = static_cast<ForkJob *>(argument);
    ProtoResult *result = job->result;

    // Bounded stdio lock acquisition; a partial set is released and retried.
    bool acquired[3] = {false, false, false};
    bool locked = false;
    for (int attempt = 0; attempt < 4; ++attempt) {
        if (qfli_mysql::lock_stdio(500, acquired) == 3) {
            locked = true;
            break;
        }
    }
    if (!locked) {
        // Abort BEFORE forking: never fork without the stdio locks held.
        copy_error(result->error, sizeof(result->error), "stdio lock acquisition timed out");
        return nullptr;
    }

    const pid_t original_parent = getpid();
    long descriptor_count = sysconf(_SC_OPEN_MAX);
    if (descriptor_count < 1024) descriptor_count = 1024;
    if (descriptor_count > (1 << 20)) descriptor_count = 1 << 20;
    // Handshake pipe: the child writes one byte after it has entered child
    // scope and started the watchdog, immediately BEFORE calling the entry. The
    // parent reads it with a bounded wait, so a child that dies before reaching
    // the server entry is detected instead of silently reported as started.
    int handshake[2] = {-1, -1};
    if (pipe(handshake) != 0) {
        qfli_mysql::unlock_stdio(acquired);
        copy_error(result->error, sizeof(result->error), "handshake pipe failed");
        return nullptr;
    }
    const pid_t pid = fork();
    if (pid == 0) {
        // Child: unlock its own copies, purge inherited buffers, enter the
        // child exit scope BEFORE any Oracle exit, reset signals/FDs, start the
        // parent-death watchdog, signal the handshake, then run the mode body.
        close(handshake[0]);
        qfli_mysql::unlock_stdio(acquired);
        qfli_mysql::discard_stdio_buffers();
        child_reset_signals_and_fds(handshake[1], static_cast<int>(descriptor_count));
        if (job->enter_scope != nullptr) job->enter_scope();
        if (getppid() != original_parent) _exit(125);
        if (!watch_parent(original_parent)) {
            const char failure_byte = 'W';
            const ssize_t ignored = write(handshake[1], &failure_byte, 1);
            (void)ignored;
            _exit(125);
        }
        if (handshake[1] >= 0) {
            const char ready_byte = 'R';
            ssize_t ignored = write(handshake[1], &ready_byte, 1);
            (void)ignored;
            close(handshake[1]);
        }
        if (job->mode == ForkMode::ServerEntry) {
            if (job->entry != nullptr && job->entry_params != nullptr) {
                job->entry(job->entry_params);
            }
            _exit(127);
        }
        job->child_exit(7); // never returns in child scope
        _exit(127);
    }
    // Parent copy: release the locks this copy holds before doing anything else.
    qfli_mysql::unlock_stdio(acquired);
    close(handshake[1]);
    handshake[1] = -1;
    if (pid < 0) {
        close(handshake[0]);
        copy_error(result->error, sizeof(result->error), "fork failed");
        return nullptr;
    }
    result->childPid = pid;
    // Adopt before any failure can return a pending PID to the caller.
    if (qfli_mysql::adopt_forked_child(static_cast<int>(pid)) != 0) {
        close(handshake[0]);
        kill(pid, SIGKILL);
        copy_error(result->error, sizeof(result->error), "could not adopt the preload child");
        return nullptr;
    }
    // Bounded handshake: wait up to ~2s for the child's ready byte. A child that
    // dies first leaks the pipe (EOF) and is detected here.
    const char handshake_result = await_handshake(handshake[0]);
    close(handshake[0]);
    if (handshake_result != 'R') {
        // Child did not reach the server entry; terminate and retain the PID so
        // it is reachable for cleanup.
        cancel_owned_child(pid, result);
        copy_error(result->error, sizeof(result->error),
                   handshake_result == 'W' ? "parent watchdog could not be established" :
                   "child did not complete the post-fork handshake");
        return nullptr;
    }
    if (job->mode == ForkMode::ServerEntry) {
        // The server child is long-lived and already tracked. Cleanup is
        // bounded and owned by the runtime lifecycle.
        result->owned = false;
        result->pendingPid = -1;
        return nullptr;
    }
    // Exit self-test: bounded handshake, then kill/reap on timeout with the PID
    // retained so it is reachable.
    qfli_mysql::ChildStatus status;
    const long deadline_ms = 5000;
    long waited = 0;
    const struct timespec pause = {0, 10 * 1000 * 1000};
    for (;;) {
        status = qfli_mysql::poll_child(pid);
        if (status.exited()) break;
        if (waited >= deadline_ms) {
            cancel_owned_child(pid, result);
            copy_error(result->error, sizeof(result->error),
                       "child exit not confirmed within the deadline");
            return nullptr;
        }
        nanosleep(&pause, nullptr);
        waited += 10;
    }
    result->owned = false;
    result->pendingPid = -1;
    qfli_mysql::release_child(pid);
    result->childExitIsolated = status.exited() && status.exit_code == 7;
    if (!result->childExitIsolated) {
        copy_error(result->error, sizeof(result->error),
                   "child exit was not intercepted cleanly");
    }
    return nullptr;
}

} // namespace

extern "C" bool qfli_mysql_proto_probe(const char *library_path, ProtoResult *result)
{
    if (result == nullptr) return false;
    *result = ProtoResult{};
    if (library_path == nullptr || library_path[0] == '\0') {
        return copy_error(result->error, sizeof(result->error), "missing library path");
    }
    // RTLD_NOW: bind eagerly; the wrappers' __real_* resolve in the parent at
    // load, so the child never performs a lazy dlsym.
    void *handle = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
        return copy_error(result->error, sizeof(result->error), dlerror());
    }
    result->loaded = true;

    auto report = reinterpret_cast<ReportFn>(dlsym(handle, "qfli_mysql_proto_report"));
    auto ready = reinterpret_cast<ReadyFn>(dlsym(handle, "qfli_mysql_proto_ready"));
    auto enter_scope = reinterpret_cast<EnterChildScopeFn>(
        dlsym(handle, "qfli_mysql_proto_enter_child_scope"));
    auto child_exit = reinterpret_cast<ChildExitFn>(
        dlsym(handle, "qfli_mysql_proto_child_exit"));
    if (report == nullptr || ready == nullptr || enter_scope == nullptr ||
        child_exit == nullptr) {
        return copy_error(result->error, sizeof(result->error), "prototype entries missing");
    }
    report(&result->threadCalls, &result->atforkCalls, &result->exitIntercepts);
    result->ready = ready() != 0;
    // Quiescence gate: do not fork if binding is not ready or if any
    // constructor-time thread/atfork work was observed. A nonzero count means
    // the closure is not quiescent and the preload design is not yet safe.
    if (!result->ready) {
        return copy_error(result->error, sizeof(result->error),
                          "prototype binding not ready");
    }
    if (result->threadCalls != 0 || result->atforkCalls != 0) {
        return copy_error(result->error, sizeof(result->error),
                          "closure is not quiescent: constructor-time thread/atfork work");
    }

    // Run the fork + stdio protocol on a dedicated fresh pthread (no preowned
    // recursive stdio locks), then join it.
    ForkJob job;
    job.enter_scope = enter_scope;
    job.child_exit = child_exit;
    job.result = result;
    pthread_t thread;
    if (pthread_create(&thread, nullptr, fork_job_main, &job) != 0) {
        return copy_error(result->error, sizeof(result->error),
                          "could not create the fork thread");
    }
    pthread_join(thread, nullptr);
    return result->childExitIsolated;
}

// Preload host: loads the private server DSO (RTLD_NOW|RTLD_LOCAL) in the parent
// and starts the server in a FORKED child by calling its entry directly — no
// exec, no dlopen in the child. Returns the forked child PID (>1) or -1.
// `entry_params` is the JSON the server entry expects; `result` receives an
// error message on failure.
extern "C" int qfli_mysql_preload_start(const char *library_path, const char *entry_params,
                                        ProtoResult *result)
{
    if (result == nullptr) return -1;
    *result = ProtoResult{};
    if (library_path == nullptr || entry_params == nullptr) {
        copy_error(result->error, sizeof(result->error), "missing preload arguments");
        return -1;
    }
    // Load the private server image in the parent only.
    void *handle = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
        copy_error(result->error, sizeof(result->error), dlerror());
        return -1;
    }
    auto entry = reinterpret_cast<ServerEntryFn>(dlsym(handle, "qfli_mysql_child_main"));
    auto report = reinterpret_cast<ReportFn>(dlsym(handle, "qfli_mysql_proto_report"));
    auto ready = reinterpret_cast<ReadyFn>(dlsym(handle, "qfli_mysql_proto_ready"));
    if (entry == nullptr || report == nullptr || ready == nullptr) {
        copy_error(result->error, sizeof(result->error), "preloaded server entry missing");
        return -1;
    }
    int thread_calls = 0;
    int atfork_calls = 0;
    int exit_intercepts = 0;
    report(&thread_calls, &atfork_calls, &exit_intercepts);
    if (ready() == 0) {
        copy_error(result->error, sizeof(result->error), "prototype binding not ready");
        return -1;
    }
    if (thread_calls != 0 || atfork_calls != 0) {
        copy_error(result->error, sizeof(result->error),
                   "closure is not quiescent: constructor-time thread/atfork work");
        return -1;
    }

    // Start the server through the SAME checked fork protocol as the exit
    // self-test: ready/counter gate (above) -> fresh pthread -> bounded stdio
    // locks (abort before fork on failure) -> fork -> child unlock/purge,
    // enter_scope before any Oracle exit, signal/FD reset, watchdog, entry.
    auto enter_scope = reinterpret_cast<EnterChildScopeFn>(
        dlsym(handle, "qfli_mysql_proto_enter_child_scope"));
    ForkJob job;
    job.mode = ForkMode::ServerEntry;
    job.enter_scope = enter_scope;
    job.child_exit = nullptr;
    job.entry = entry;
    job.entry_params = entry_params;
    job.result = result;
    pthread_t thread;
    if (pthread_create(&thread, nullptr, fork_job_main, &job) != 0) {
        copy_error(result->error, sizeof(result->error),
                   "could not create the preload fork thread");
        return -1;
    }
    pthread_join(thread, nullptr);
    // fork_job_main fills childPid/owned/pendingPid and the error message.
    return result->error[0] == '\0' ? result->childPid : -1;
}
