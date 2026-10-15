#include "qfli_mysql_host.h"

#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#if defined(__linux__)
#include <sys/syscall.h>
#endif

namespace qfli_mysql {
namespace {

enum class ChildKind {
    // Forked by this host; waitpid() is the authoritative reaper.
    Forked,
    // Started by the HarmonyOS native-child API; AppSpawn may be the parent, so
    // waitpid must never be used. Liveness is a verified-identity probe;
    // completion is reported explicitly through complete_registered_child().
    Registered,
};

struct ChildRecord {
    ChildKind kind = ChildKind::Forked;
    ChildState state = ChildState::Running;
    int exit_code = 0;
    // Stable kernel identity for a Registered child, captured at registration.
    // start_time is field 22 of /proc/<pid>/stat; pidfd is the Linux pidfd when
    // available, else -1.
    std::uint64_t start_time = 0;
    int pidfd = -1;
};

std::map<int, ChildRecord> &owned()
{
    static std::map<int, ChildRecord> children;
    return children;
}

// Writes an int to a descriptor using only async-signal-safe syscalls.
void write_int(int descriptor, int value)
{
    const char *bytes = reinterpret_cast<const char *>(&value);
    std::size_t offset = 0;
    while (offset < sizeof(value)) {
        const ssize_t written = write(descriptor, bytes + offset, sizeof(value) - offset);
        if (written <= 0) {
            if (errno == EINTR) continue;
            return;
        }
        offset += static_cast<std::size_t>(written);
    }
}

// Async-signal-safe stage marker: one short raw write, no allocation, no stdio.
void write_stage(int descriptor, const char *stage)
{
    if (descriptor < 0 || stage == nullptr) return;
    std::size_t length = 0;
    while (stage[length] != '\0') ++length;
    ssize_t written = 0;
    while (written < static_cast<ssize_t>(length)) {
        const ssize_t count = write(descriptor, stage + written, length - written);
        if (count <= 0) {
            if (errno == EINTR) continue;
            return;
        }
        written += count;
    }
}

// Reads field 22 (starttime) of /proc/<pid>/stat. Returns 0 when unavailable.
std::uint64_t process_start_time(int pid)
{
    char path[64];
    std::snprintf(path, sizeof(path), "/proc/%d/stat", pid);
    int descriptor = open(path, O_RDONLY | O_CLOEXEC);
    if (descriptor < 0) return 0;
    char buffer[2048];
    ssize_t length = 0;
    do {
        length = read(descriptor, buffer, sizeof(buffer) - 1);
    } while (length < 0 && errno == EINTR);
    close(descriptor);
    if (length <= 0) return 0;
    buffer[length] = '\0';
    // The comm field is parenthesised and may contain spaces or ')'. Skip to the
    // last ')' so field numbering starts correctly.
    char *cursor = std::strrchr(buffer, ')');
    if (cursor == nullptr) return 0;
    ++cursor;
    // Fields after comm: 3=state ... 22=starttime. starttime is the 20th field
    // after comm (state is field 3).
    int field = 3;
    char *token = std::strtok(cursor, " ");
    while (token != nullptr) {
        if (field == 22) return std::strtoull(token, nullptr, 10);
        token = std::strtok(nullptr, " ");
        ++field;
    }
    return 0;
}

// Opens a pidfd for pid where the kernel supports it. Returns -1 otherwise.
int open_pidfd(int pid)
{
#if defined(__linux__) && defined(SYS_pidfd_open)
#if defined(__NR_pidfd_open)
    const long descriptor = syscall(__NR_pidfd_open, pid, 0);
#else
    const long descriptor = syscall(SYS_pidfd_open, pid, 0);
#endif
    if (descriptor >= 0) return static_cast<int>(descriptor);
#endif
    (void)pid;
    return -1;
}

// True when the process currently at pid is the same kernel process that was
// registered. This prevents signalling a recycled PID after AppSpawn reaps it.
bool identity_matches(int pid, const ChildRecord &record)
{
    if (record.pidfd >= 0) {
        // A pidfd keeps referring to the original process; if it is still open
        // and the recorded start time matches the live one, this is the same
        // process.
        if (process_start_time(pid) != record.start_time) return false;
        return true;
    }
    const std::uint64_t start = process_start_time(pid);
    return start != 0 && start == record.start_time;
}

// Closes inherited descriptors in the fork child so no parent handle leaks into
// the launcher. Only 0, 1, 2 and the two kept descriptors survive. A plain close
// loop is used: the close_range syscall is filtered by the phone app sandbox
// (observed as SIGSYS), so only the portable, supported close() is relied upon.
// The upper bound is computed in the parent (sysconf is not async-signal-safe
// after fork).
void close_inherited_descriptors(int keep_fd, int keep_fd_two, int max_fd)
{
    for (int descriptor = 3; descriptor < max_fd; ++descriptor) {
        if (descriptor == keep_fd || descriptor == keep_fd_two) continue;
        close(descriptor);
    }
}

// Computes the descriptor upper bound in the parent, before fork. sysconf is
// safe here and its result is passed into the child as a plain integer.
int descriptor_limit()
{
    long maximum = sysconf(_SC_OPEN_MAX);
    if (maximum < 1024) maximum = 1024;
    if (maximum > 1 << 20) maximum = 1 << 20;
    return static_cast<int>(maximum);
}

} // namespace

int register_child(int pid)
{
    if (pid <= 1) {
        errno = EINVAL;
        return -1;
    }
    // Capture a stable kernel identity before the framework can reap the child.
    const int pidfd = open_pidfd(pid);
    const std::uint64_t start = process_start_time(pid);
    if (pidfd < 0 && start == 0) {
        // Without an identity we can never safely signal this PID.
        errno = ESRCH;
        return -1;
    }
    ChildRecord record;
    record.kind = ChildKind::Registered;
    record.pidfd = pidfd;
    record.start_time = start;
    owned()[pid] = record;
    return 0;
}

// Adopts a PID forked by another translation unit (the preload host) into the
// same waitpid-owned tracking used by start_child(). The child is a direct fork
// of this process, so waitpid() is the authoritative reaper — NOT the
// registered/nativeChild semantics.
int adopt_forked_child(int pid)
{
    if (pid <= 1) {
        errno = EINVAL;
        return -1;
    }
    ChildRecord record;
    record.kind = ChildKind::Forked;
    owned()[pid] = record;
    return 0;
}

int complete_registered_child(int pid, int exit_code)
{
    auto found = owned().find(pid);
    if (found == owned().end() || found->second.kind != ChildKind::Registered) {
        errno = ECHILD;
        return -1;
    }
    // Only complete once the process is actually gone, so a stale record is
    // never reported as a clean exit while the child still runs. A recycled PID
    // is not the registered process and must not count as "still running".
    if (identity_matches(pid, found->second) && (kill(pid, 0) == 0 || errno == EPERM)) {
        errno = EBUSY;
        return -1;
    }
    found->second.state = ChildState::Exited;
    found->second.exit_code = exit_code;
    if (found->second.pidfd >= 0) {
        close(found->second.pidfd);
        found->second.pidfd = -1;
    }
    return 0;
}

// Bounded cleanup for a child whose exec/protocol state is unknown. Sends
// SIGKILL, then polls waitpid(WNOHANG) for a bounded time so a failed signal or
// a child that never dies cannot block the caller. Returns true only when the
// child was confirmed reaped (and removes it from owned()). On unconfirmed
// termination the child is RETAINED in owned() and false is returned, matching
// the lifecycle rule that ownership is only released on a confirmed terminal
// state. The caller must not block on waitpid after a false return.
bool terminate_and_reap(int pid)
{
#if defined(QFLI_MYSQL_HOST_TEST_HOOKS)
    // Test-only: simulate a failed signal so the child is never killed. This
    // exercises the retained-ownership path with a live child.
    const bool suppress_kill = getenv("QFLI_MYSQL_HOST_TEST_FAULT_NO_KILL") != nullptr;
    if (suppress_kill) {
        return false;
    }
#endif
    if (kill(static_cast<pid_t>(pid), SIGKILL) != 0 && errno != ESRCH) {
        // Signal failed; do not block. Ownership stays with the caller.
    }
    const int attempts = 50; // 50 * 10ms = 500ms bound
    for (int attempt = 0; attempt < attempts; ++attempt) {
        int status = 0;
        const pid_t result = waitpid(static_cast<pid_t>(pid), &status, WNOHANG);
        if (result == static_cast<pid_t>(pid)) {
            owned().erase(pid);
            return true;
        }
        if (result < 0) {
            // ECHILD: already reaped elsewhere; remove the stale record.
            if (errno == ECHILD) {
                owned().erase(pid);
                return true;
            }
            return false;
        }
        const struct timespec pause = {0, 10 * 1000 * 1000};
        nanosleep(&pause, nullptr);
    }
    return false;
}

int read_error_frame(int descriptor, int errors[2])
{
    int received[2] = {0, 0};
    std::size_t received_count = 0;
    std::size_t offset = 0;
    while (received_count < 2) {
        char *target = reinterpret_cast<char *>(&received[received_count]);
        const std::size_t remaining = sizeof(int);
        const ssize_t count = read(descriptor, target + offset, remaining - offset);
        if (count < 0) {
            if (errno == EINTR) continue;
            return -1; // read error: protocol failure
        }
        if (count == 0) {
            // EOF: only a wholly absent frame is "no error". A partial frame is
            // a protocol failure, never success, and reports EPROTO.
            if (received_count == 0 && offset == 0) return 0;
            errno = EPROTO;
            return -1;
        }
        offset += static_cast<std::size_t>(count);
        if (offset == remaining) {
            ++received_count;
            offset = 0;
        }
    }
    errors[0] = received[0];
    errors[1] = received[1];
    return 1;
}

StartResult start_child(const std::string &launcher_path, const std::string &entry_params,
                        const std::string &log_path)
{
    // Prepare everything before fork so the child only runs syscalls. argv[2]
    // carries the ORIGINAL owning app pid, captured before fork, so the
    // launcher does not have to recapture its parent.
#if defined(QFLI_MYSQL_HOST_TEST_HOOKS)
    // Compile-time test-only fault injection. Not present in production builds.
    //   QFLI_MYSQL_HOST_TEST_FAULT_PARTIAL: child writes one int then _exit.
    //   QFLI_MYSQL_HOST_TEST_FAULT_READ:    parent read is failed while the child
    //                                       stays alive (close our read end early
    //                                       via a closed descriptor).
    const bool inject_partial_frame = getenv("QFLI_MYSQL_HOST_TEST_FAULT_PARTIAL") != nullptr;
    const bool inject_read_failure = getenv("QFLI_MYSQL_HOST_TEST_FAULT_READ") != nullptr;
#else
    const bool inject_partial_frame = false;
    const bool inject_read_failure = false;
#endif

    const pid_t parent = getpid();
    std::vector<std::string> storage;
    storage.push_back(launcher_path);
    storage.push_back(entry_params);
    storage.push_back(std::to_string(static_cast<long long>(parent)));
    std::vector<char *> argv;
    argv.reserve(storage.size() + 1);
    for (auto &value : storage) argv.push_back(value.data());
    argv.push_back(nullptr);

    // Preferred interpreter for the fallback exec. The parent prepares the
    // path AND the full argv so the child performs no lookup, allocation, or
    // std::string/vector work after fork.
    const std::string interpreter = "/lib/ld-musl-aarch64.so.1";
    const char *interpreter_path = interpreter.c_str();
    std::vector<std::string> interp_storage;
    interp_storage.push_back(interpreter);
    interp_storage.push_back(launcher_path);
    interp_storage.push_back(entry_params);
    interp_storage.push_back(std::to_string(static_cast<long long>(parent)));
    std::vector<char *> interp_argv;
    interp_argv.reserve(interp_storage.size() + 1);
    for (auto &value : interp_storage) interp_argv.push_back(value.data());
    interp_argv.push_back(nullptr);
    const bool have_interpreter = !interpreter.empty();

    // Error pipe: the child writes its exec errno here if execve fails. The
    // write end must survive descriptor closing, so it is marked CLOEXEC and
    // kept explicitly. A high descriptor avoids colliding with stdio.
    int error_pipe[2] = {-1, -1};
    if (pipe(error_pipe) != 0) return StartResult{};
    fcntl(error_pipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(error_pipe[1], F_SETFD, FD_CLOEXEC);

    // Launch-stage trace: opened in the parent so the child needs no open()
    // before its first marker. Each marker is one raw async-signal-safe write;
    // if the child dies from a filtered syscall (SIGSYS), the last marker in the
    // log identifies the exact failing stage without a crash report.
    int trace_fd = -1;
    if (!log_path.empty()) {
        trace_fd = open(log_path.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0600);
        // Keep the launcher from inheriting this descriptor; stderr is a dup of
        // it that survives exec.
        if (trace_fd >= 0) fcntl(trace_fd, F_SETFD, FD_CLOEXEC);
    }

    // Compute the descriptor bound in the parent; sysconf is not
    // async-signal-safe after fork.
    const int max_fd = descriptor_limit();

    const pid_t pid = fork();
    if (pid < 0) {
        const int saved = errno;
        close(error_pipe[0]);
        close(error_pipe[1]);
        if (trace_fd >= 0) close(trace_fd);
        errno = saved;
        return StartResult{};
    }
    if (pid == 0) {
        // Only async-signal-safe operations from here until execve.
        write_stage(trace_fd, "[launch] fork\n");
        // PR_SET_PDEATHSIG is intentionally NOT used: the phone app sandbox can
        // reject prctl with SIGSYS before any log exists. Parent-death cleanup
        // is handled by the launcher's getppid() watchdog instead, using only
        // standard supported calls. The parent re-check below covers the race
        // where the parent died between fork and here.
        if (getppid() != parent) _exit(125);
        write_stage(trace_fd, "[launch] parent-ok\n");
        signal(SIGTERM, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        signal(SIGPIPE, SIG_DFL);
        signal(SIGHUP, SIG_DFL);
        write_stage(trace_fd, "[launch] signals\n");

        // Close every inherited descriptor except stdio, the error pipe, and
        // the trace fd. Then route the launcher's stderr to the trace fd and
        // place the post-close stage marker.
        close_inherited_descriptors(error_pipe[1], trace_fd, max_fd);
        if (trace_fd >= 3) {
            dup2(trace_fd, STDERR_FILENO);
        }
        write_stage(trace_fd, "[launch] fds-closed\n");
        if (inject_partial_frame) {
            // Test-only: write a single int then exit before exec, producing a
            // partial frame so the parent's protocol-failure cleanup runs with a
            // live child.
            write_stage(trace_fd, "[launch] inject-partial\n");
            write_int(error_pipe[1], EACCES);
            _exit(127);
        }
        execv(launcher_path.c_str(), argv.data());
        // Capture the real errno immediately: write_stage may change it.
        const int direct_errno = errno;
        write_stage(trace_fd, "[launch] exec-failed\n");
        // If direct exec of the packaged launcher is denied (EACCES/ENOEXEC),
        // retry through the OS ELF interpreter already present on the device.
        // This uses the prebuilt interpreter argv from the parent and keeps all
        // OS permission/code-signing checks in force; it does not copy, chmod,
        // or bypass anything.
        int interp_errno = 0;
        if ((direct_errno == EACCES || direct_errno == ENOEXEC) && have_interpreter) {
            write_stage(trace_fd, "[launch] exec-interp\n");
            execv(interpreter_path, interp_argv.data());
            interp_errno = errno;
        }
        // Report both attempts separately: no errno overwrites the other.
        write_int(error_pipe[1], direct_errno);
        write_int(error_pipe[1], interp_errno);
        _exit(127);
    }

    close(error_pipe[1]);
    if (trace_fd >= 0) {
        close(trace_fd);
        trace_fd = -1;
    }
    ChildRecord record;
    record.kind = ChildKind::Forked;
    owned()[static_cast<int>(pid)] = record;

    // Read the two reported errno values. Only a clean zero-byte EOF (no frame)
    // means no exec error was reported; that is NOT proof exec succeeded and
    // readiness is still confirmed by the runtime. A partial frame or read
    // error is a protocol failure, never success. The two errnos are preserved
    // separately.
    int errors[2] = {0, 0};
    int frame;
    if (inject_read_failure) {
        // Test-only: fail the parent read with a bad descriptor while the child
        // stays alive (it execs normally). Exercises the bounded-cleanup and
        // retained-ownership path with a live child.
        close(error_pipe[0]);
        frame = read_error_frame(-1, errors);
        if (frame >= 0) frame = -1;
        if (errno == 0) errno = EPROTO;
    } else {
        frame = read_error_frame(error_pipe[0], errors);
        close(error_pipe[0]);
    }
    if (frame < 0) {
        const int saved = errno;
        // A malformed/failed error frame means the child's exec state is
        // unknown; a read error does not imply the child exited. Bounded
        // termination: on unconfirmed termination ownership is retained and
        // reported to the caller so the lifecycle can clean it up.
        const bool reaped = terminate_and_reap(static_cast<int>(pid));
        StartResult result;
        result.pid = -1;
        result.owned = !reaped;
        result.pending_pid = reaped ? -1 : static_cast<int>(pid);
        errno = saved != 0 ? saved : EPROTO;
        return result;
    }
    const bool failed = frame == 1;
    if (failed) {
        const int direct_errno = errors[0];
        const int interp_errno = errors[1];
        // The child reported exec failure; bounded termination, never blocking.
        const bool reaped = terminate_and_reap(static_cast<int>(pid));
        // Append a rich diagnostic: launcher path + mode/uid/size, and both the
        // direct-exec errno and the interpreter-exec errno, plus the interpreter
        // path/mode. Written through a freshly opened descriptor so it cannot be
        // affected by the child's descriptor handling.
        if (!log_path.empty()) {
            struct stat launcher_stat {};
            const bool have_launcher_stat = stat(launcher_path.c_str(), &launcher_stat) == 0;
            struct stat interpreter_stat {};
            const bool have_interpreter_stat = stat(interpreter_path, &interpreter_stat) == 0;
            // Compare with the sibling NAPI client library in the same installed
            // directory: if OHOS grants it an execute bit and not the launcher,
            // the difference is a packaging/settings hypothesis worth testing.
            std::string sibling = launcher_path;
            const std::size_t slash = sibling.find_last_of('/');
            if (slash != std::string::npos) sibling = sibling.substr(0, slash);
            sibling += "/libqfli_mysql.so";
            struct stat sibling_stat {};
            const bool have_sibling_stat = stat(sibling.c_str(), &sibling_stat) == 0;
            char line[768];
            const int length = std::snprintf(line, sizeof(line),
                "[host] direct errno=%d interp errno=%d launcher=%s mode=%#o uid=%u size=%lld "
                "interp=%s mode=%#o sibling=%s mode=%#o\n",
                direct_errno, interp_errno, launcher_path.c_str(),
                have_launcher_stat ? static_cast<unsigned>(launcher_stat.st_mode) : 0u,
                have_launcher_stat ? static_cast<unsigned>(launcher_stat.st_uid) : 0u,
                have_launcher_stat ? static_cast<long long>(launcher_stat.st_size) : 0,
                interpreter_path,
                have_interpreter_stat ? static_cast<unsigned>(interpreter_stat.st_mode) : 0u,
                sibling.c_str(),
                have_sibling_stat ? static_cast<unsigned>(sibling_stat.st_mode) : 0u);
            if (length > 0) {
                // snprintf returns the would-be length; clamp to what fits.
                std::size_t writable = static_cast<std::size_t>(length);
                const std::size_t capacity = sizeof(line) - 1;
                if (writable > capacity) writable = capacity;
                const int diagnostic_fd = open(log_path.c_str(),
                    O_WRONLY | O_CREAT | O_APPEND, 0600);
                if (diagnostic_fd >= 0) {
                    write(diagnostic_fd, line, writable);
                    close(diagnostic_fd);
                }
            }
        }
        // Give the caller the direct-exec errno (the primary failure).
        errno = direct_errno != 0 ? direct_errno : ENOENT;
        StartResult result;
        result.pid = -1;
        result.owned = !reaped;
        result.pending_pid = reaped ? -1 : static_cast<int>(pid);
        return result;
    }
    StartResult success;
    success.pid = static_cast<int>(pid);
    return success;
}

ChildStatus poll_child(int pid)
{
    auto found = owned().find(pid);
    if (found == owned().end()) return ChildStatus{};
    if (found->second.state == ChildState::Exited) {
        return ChildStatus{ChildState::Exited, found->second.exit_code};
    }
    if (found->second.kind == ChildKind::Registered) {
        // Never waitpid; the framework may own this process. Liveness is only
        // reported for the verified registered identity.
        const bool same = identity_matches(pid, found->second);
        if (same && (kill(pid, 0) == 0 || errno == EPERM)) {
            return ChildStatus{ChildState::Running, 0};
        }
        // The verified process is gone (or the PID was recycled). Do not claim a
        // clean exit: mark it exited with a sentinel failure code.
        found->second.state = ChildState::Exited;
        found->second.exit_code = 125;
        return ChildStatus{ChildState::Exited, 125};
    }
    int status = 0;
    pid_t result = 0;
    do {
        result = waitpid(static_cast<pid_t>(pid), &status, WNOHANG);
    } while (result < 0 && errno == EINTR);
    if (result == 0) return ChildStatus{ChildState::Running, 0};
    if (result < 0) {
        // ECHILD with no recorded exit: the process is gone but we have no code.
        found->second.state = ChildState::Exited;
        found->second.exit_code = 125;
        return ChildStatus{ChildState::Exited, 125};
    }
    found->second.state = ChildState::Exited;
    found->second.exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    return ChildStatus{ChildState::Exited, found->second.exit_code};
}

int release_child(int pid)
{
    auto found = owned().find(pid);
    if (found == owned().end()) {
        errno = ECHILD;
        return -1;
    }
    if (found->second.state != ChildState::Exited) {
        errno = EBUSY;
        return -1;
    }
    if (found->second.pidfd >= 0) close(found->second.pidfd);
    owned().erase(pid);
    return 0;
}

int signal_child(int pid, bool force)
{
    auto found = owned().find(pid);
    if (found == owned().end()) {
        errno = ECHILD;
        return -1;
    }
    if (found->second.state == ChildState::Exited) return 0;
    if (found->second.kind == ChildKind::Registered) {
        // Never signal an unverified PID: the registered process may have been
        // reaped and its PID recycled by an unrelated process.
        if (!identity_matches(pid, found->second)) {
            errno = ESRCH;
            return -1;
        }
    }
    const int signal_number = force ? SIGKILL : SIGTERM;
    if (kill(pid, signal_number) != 0 && errno != ESRCH) return -1;
    return 0;
}

} // namespace qfli_mysql
