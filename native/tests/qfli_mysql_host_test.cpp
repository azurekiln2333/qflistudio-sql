// Host lifecycle test for the phone child-process host.
//
// This exercises the real production host (native/mysql/qfli_mysql_host.cpp)
// and the real production launcher (native/mysql/qfli_mysql_launcher.cpp). A
// stub server entry (qfli_mysql_child_stub.cpp) stands in for mysqld so the
// test can force success, nonzero exit, and slow exits. The host and launcher
// are production code; only mysqld is stubbed.
//
// CMake stages the launcher and the stub server library beside each other so
// the launcher's dladdr-derived directory resolves the server entry.
#include "qfli_mysql_host.h"

#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <string>

namespace {

int failures = 0;

void check(bool condition, const std::string &message)
{
    if (condition) {
        std::printf("ok   %s\n", message.c_str());
    } else {
        std::printf("FAIL %s\n", message.c_str());
        ++failures;
    }
}

std::string temporary_directory()
{
    char pattern[] = "/tmp/qfli_mysql_host_XXXXXX";
    char *path = mkdtemp(pattern);
    if (path == nullptr) {
        std::perror("mkdtemp");
        std::exit(2);
    }
    return path;
}

std::string read_file(const std::string &path)
{
    FILE *file = std::fopen(path.c_str(), "rb");
    if (file == nullptr) return {};
    std::string text;
    char buffer[64];
    std::size_t count = 0;
    while ((count = std::fread(buffer, 1, sizeof(buffer), file)) > 0) text.append(buffer, count);
    std::fclose(file);
    return text;
}

// Polls until the child reaches a terminal state, bounded so a bug cannot hang
// the test.
qfli_mysql::ChildStatus await_exit(int pid, int milliseconds)
{
    qfli_mysql::ChildStatus status;
    for (int elapsed = 0; elapsed < milliseconds; elapsed += 20) {
        status = qfli_mysql::poll_child(pid);
        if (status.state != qfli_mysql::ChildState::Running) return status;
        usleep(20 * 1000);
    }
    return status;
}

std::string payload(const std::string &exit_file, int code, int sleep_seconds)
{
    return "{\"exitFile\":\"" + exit_file + "\",\"sleepSeconds\":" +
           std::to_string(sleep_seconds) + ",\"exitCode\":" + std::to_string(code) + "}";
}

bool launcher_is_executable(const std::string &path)
{
    return access(path.c_str(), X_OK) == 0;
}

void copy_file(const std::string &source, const std::string &destination)
{
    FILE *in = std::fopen(source.c_str(), "rb");
    if (in == nullptr) return;
    FILE *out = std::fopen(destination.c_str(), "wb");
    if (out == nullptr) {
        std::fclose(in);
        return;
    }
    char buffer[4096];
    std::size_t count = 0;
    while ((count = std::fread(buffer, 1, sizeof(buffer), in)) > 0) {
        std::fwrite(buffer, 1, count, out);
    }
    std::fclose(out);
    std::fclose(in);
}

std::string payload_with_fd_report(const std::string &exit_file, const std::string &report)
{
    return "{\"exitFile\":\"" + exit_file + "\",\"sleepSeconds\":0,\"exitCode\":0," +
           "\"fdReport\":\"" + report + "\"}";
}

} // namespace

int main(int argc, char **argv)
{
    if (argc != 2) {
        std::fprintf(stderr, "usage: %s <launcher path>\n", argv[0]);
        return 2;
    }
    const std::string launcher = argv[1];
    const std::string directory = temporary_directory();
    const std::string log = directory + "/child.log";

    // 1. A successful exit 0 must be distinguishable from a running child, and
    //    polling must stay idempotent until released.
    {
        const std::string exit_file = directory + "/success.exit";
        const int pid = qfli_mysql::start_child(launcher, payload(exit_file, 0, 0), log).pid;
        if (pid < 0) std::printf("      start_child errno=%d (%s)\n", errno, std::strerror(errno));
        check(pid > 1, "start_child returns a real pid");
        const qfli_mysql::ChildStatus status = await_exit(pid, 5000);
        check(status.state == qfli_mysql::ChildState::Exited, "child is reported exited, not running");
        check(status.exit_code == 0, "successful child exit code is 0");
        check(read_file(exit_file) == "0\n", "successful child writes its exit record");
        const qfli_mysql::ChildStatus again = qfli_mysql::poll_child(pid);
        check(again.state == qfli_mysql::ChildState::Exited && again.exit_code == 0,
              "poll after exit is idempotent with the same code");
        check(qfli_mysql::release_child(pid) == 0, "release_child releases a completed child");
        check(qfli_mysql::poll_child(pid).state == qfli_mysql::ChildState::Unknown,
              "released child is unknown");
    }

    // 1b. Parent-identity check: the launcher must reject a wrong passed pid and
    //     accept the real parent pid, which the host now supplies before fork.
    if (launcher_is_executable(launcher)) {
        // Wrong pid: expect exit 125 without starting the server.
        const pid_t bad = fork();
        if (bad == 0) {
            execl(launcher.c_str(), launcher.c_str(),
                  "{\"exitFile\":\"/nonexistent\",\"exitCode\":0}", "1", (char *)nullptr);
            _exit(126);
        }
        int bad_status = 0;
        check(waitpid(bad, &bad_status, 0) == bad, "launcher bad-pid child reaped");
        check(WIFEXITED(bad_status) && WEXITSTATUS(bad_status) == 125,
              "launcher rejects an invalid app pid");

        // Correct pid: the launcher accepts it and the server stub runs to a
        // normal exit, proving the host-supplied parent identity is accepted.
        const std::string exit_file = directory + "/identity.exit";
        const pid_t good = fork();
        if (good == 0) {
            const std::string pid_argument = std::to_string(static_cast<long long>(getppid()));
            const std::string json = payload(exit_file, 0, 0);
            execl(launcher.c_str(), launcher.c_str(), json.c_str(), pid_argument.c_str(),
                  (char *)nullptr);
            _exit(126);
        }
        int good_status = 0;
        check(waitpid(good, &good_status, 0) == good, "launcher good-pid child reaped");
        check(WIFEXITED(good_status) && WEXITSTATUS(good_status) == 0,
              "launcher accepts the real parent pid");
        check(read_file(exit_file) == "0\n", "accepted-identity child wrote its exit record");
    }

    // 1c. EACCES diagnostic: a launcher copy without the execute bit must fail
    //     with a rich diagnostic (mode + interpreter), matching the phone case.
    {
        const std::string blocked = directory + "/blocked_launcher";
        copy_file(launcher, blocked);
        chmod(blocked.c_str(), 0644);
        const std::string exit_file = directory + "/blocked.exit";
        const std::string blocked_log = directory + "/blocked.log";
        errno = 0;
        const qfli_mysql::StartResult blocked_result =
            qfli_mysql::start_child(blocked, payload(exit_file, 0, 0), blocked_log);
        const int pid = blocked_result.pid;
        check(pid < 0, "non-executable launcher fails to start");
        check(!blocked_result.owned,
              "a confirmed-reaped failed child leaves no owned pending pid");
        check(errno == EACCES || errno == ENOEXEC || errno == ENOENT,
              "non-executable launcher reports an exec/permission error");
        const std::string diag = read_file(blocked_log);
        check(diag.find("[host] direct errno=") != std::string::npos,
              "diagnostic records the direct exec errno");
        check(diag.find("interp errno=") != std::string::npos,
              "diagnostic records the interpreter exec errno");
        check(diag.find("mode=") != std::string::npos,
              "diagnostic records the launcher mode");
        check(diag.find("ld-musl-aarch64.so.1") != std::string::npos,
              "diagnostic records the interpreter path");
        chmod(blocked.c_str(), 0755);
    }

    // 1d. Error-frame protocol: only a clean zero-byte EOF means "no frame"; a
    //     complete two-int frame reports both errnos; a partial frame or read
    //     error is a protocol failure, never success.
    {
        // Complete frame.
        int full_pipe[2];
        check(pipe(full_pipe) == 0, "error-frame pipe created");
        const int frame[2] = {13, 2};
        check(write(full_pipe[1], frame, sizeof(frame)) == static_cast<ssize_t>(sizeof(frame)),
              "test writes a complete error frame");
        close(full_pipe[1]);
        int read_errors[2] = {0, 0};
        check(qfli_mysql::read_error_frame(full_pipe[0], read_errors) == 1,
              "complete frame is read");
        check(read_errors[0] == 13 && read_errors[1] == 2,
              "complete frame preserves both errnos");
        close(full_pipe[0]);

        // Clean EOF: no frame at all.
        int eof_pipe[2];
        check(pipe(eof_pipe) == 0, "eof pipe created");
        close(eof_pipe[1]);
        int eof_errors[2] = {0, 0};
        check(qfli_mysql::read_error_frame(eof_pipe[0], eof_errors) == 0,
              "clean zero-byte EOF is reported as no frame");
        close(eof_pipe[0]);

        // Partial frame: one int then EOF.
        int partial_pipe[2];
        check(pipe(partial_pipe) == 0, "partial pipe created");
        const int one = 13;
        check(write(partial_pipe[1], &one, sizeof(one)) == static_cast<ssize_t>(sizeof(one)),
              "test writes a partial frame");
        close(partial_pipe[1]);
        int partial_errors[2] = {0, 0};
        errno = 0;
        check(qfli_mysql::read_error_frame(partial_pipe[0], partial_errors) == -1,
              "partial frame is a protocol failure");
        check(errno == EPROTO, "partial frame reports EPROTO");
        close(partial_pipe[0]);

        // Read error: bad descriptor.
        int bad_errors[2] = {0, 0};
        check(qfli_mysql::read_error_frame(-1, bad_errors) == -1,
              "read error is a protocol failure");
    }

    // 1e. Live-child injection: a real forked child that writes a partial frame
    //     must be detected as a protocol failure, cleaned up with bounded
    //     termination (no hang), and never reported as a started server. Also
    //     covers a live child whose parent read fails, with a suppressed kill so
    //     ownership is retained (never a blocking wait).
    {
        setenv("QFLI_MYSQL_HOST_TEST_FAULT_PARTIAL", "1", 1);
        const std::string exit_file = directory + "/inject.exit";
        const std::string inject_log = directory + "/inject.log";
        const time_t before = time(nullptr);
        errno = 0;
        const qfli_mysql::StartResult r =
            qfli_mysql::start_child(launcher, payload(exit_file, 0, 0), inject_log);
        const time_t after = time(nullptr);
        check(r.pid < 0, "partial-frame child is reported as a start failure");
        check(errno == EPROTO, "partial-frame failure reports EPROTO");
        check(after - before <= 5, "protocol-failure cleanup returns promptly (bounded)");
        // The partial-frame child exits; it should be confirmed reaped.
        if (r.owned && r.pending_pid > 1) {
            qfli_mysql::release_child(r.pending_pid);
        }
        unsetenv("QFLI_MYSQL_HOST_TEST_FAULT_PARTIAL");

        // Live child + failed parent read + suppressed kill: the child stays
        // alive, so ownership must be RETAINED and reported, never blocked on.
        setenv("QFLI_MYSQL_HOST_TEST_FAULT_READ", "1", 1);
        setenv("QFLI_MYSQL_HOST_TEST_FAULT_NO_KILL", "1", 1);
        const time_t read_before = time(nullptr);
        errno = 0;
        const qfli_mysql::StartResult live =
            qfli_mysql::start_child(launcher, payload(exit_file, 0, 30), inject_log);
        const time_t read_after = time(nullptr);
        check(live.pid < 0, "read-failure child is a start failure");
        check(live.owned && live.pending_pid > 1,
              "unconfirmed termination retains ownership with a pending pid");
        check(read_after - read_before <= 5, "read-failure cleanup is bounded (no hang)");
        if (live.owned && live.pending_pid > 1) {
            // The child is still alive; terminate it for real and release.
            unsetenv("QFLI_MYSQL_HOST_TEST_FAULT_NO_KILL");
            qfli_mysql::signal_child(live.pending_pid, true);
            for (int i = 0; i < 100; ++i) {
                if (qfli_mysql::poll_child(live.pending_pid).state == qfli_mysql::ChildState::Exited) break;
                usleep(10 * 1000);
            }
            qfli_mysql::release_child(live.pending_pid);
        }
        unsetenv("QFLI_MYSQL_HOST_TEST_FAULT_READ");
    }

    // 2. A still-running child reports Running (distinct from exit 0).
    {
        const std::string exit_file = directory + "/slow.exit";
        const int pid = qfli_mysql::start_child(launcher, payload(exit_file, 0, 5), log).pid;
        check(qfli_mysql::poll_child(pid).state == qfli_mysql::ChildState::Running,
              "slow child reports running, not exited-0");
        check(qfli_mysql::release_child(pid) != 0, "release_child rejects a running child");
        check(qfli_mysql::signal_child(pid, false) == 0, "signal_child signals the owned child");
        const qfli_mysql::ChildStatus status = await_exit(pid, 5000);
        check(status.state == qfli_mysql::ChildState::Exited, "signalled child reaches a terminal state");
        qfli_mysql::release_child(pid);
    }

    // 3. Nonzero exit is reported verbatim.
    {
        const std::string exit_file = directory + "/failure.exit";
        const int pid = qfli_mysql::start_child(launcher, payload(exit_file, 7, 0), log).pid;
        check(await_exit(pid, 5000).exit_code == 7, "nonzero child exit code is reported");
        qfli_mysql::release_child(pid);
    }

    // 4. A failed exec is reported at start, not as a later silent exit.
    {
        const qfli_mysql::StartResult r =
            qfli_mysql::start_child(directory + "/missing_launcher", "{}", log);
        check(r.pid < 0, "start_child fails when the launcher cannot be executed");
        if (r.owned && r.pending_pid > 1) qfli_mysql::release_child(r.pending_pid);
    }

    // 5. Non-owned PIDs are never signalled.
    {
        check(qfli_mysql::signal_child(1, false) != 0, "signal_child rejects pid 1");
        check(qfli_mysql::signal_child(getpid(), false) != 0, "signal_child rejects a non-owned pid");
        check(qfli_mysql::poll_child(getpid()).state == qfli_mysql::ChildState::Unknown,
              "poll rejects a non-owned pid");
    }

    // 6. Registering a framework child (native-child API path): liveness only,
    //    and completion must be explicit, never waitpid ECHILD.
    {
        const pid_t child = fork();
        if (child == 0) {
            sleep(2);
            _exit(0);
        }
        const int pid = static_cast<int>(child);
        check(qfli_mysql::register_child(pid) == 0, "register_child accepts a framework pid");
        check(qfli_mysql::poll_child(pid).state == qfli_mysql::ChildState::Running,
              "registered child reports running");
        check(qfli_mysql::complete_registered_child(pid, 0) != 0,
              "registered child cannot be completed while still running");
        // In production the framework (AppSpawn) reaps its child; here the test
        // reaps it so it is not left as a zombie that kill(0) would still see.
        int status = 0;
        check(waitpid(child, &status, 0) == child, "test reaps the framework child");
        check(qfli_mysql::complete_registered_child(pid, 0) == 0,
              "registered child completes after it exits");
        check(qfli_mysql::poll_child(pid).state == qfli_mysql::ChildState::Exited,
              "completed registered child is exited");
        check(qfli_mysql::release_child(pid) == 0,
              "release succeeds for a confirmed-exited registered child");
        check(qfli_mysql::signal_child(pid, false) != 0,
              "signal is refused after release (unknown pid)");
    }

    // 6b. Register -> externally reaped (framework race): signal is refused, but
    //     the host still settles from the exit record, completes, and releases.
    {
        const pid_t child = fork();
        if (child == 0) {
            sleep(2);
            _exit(3);
        }
        const int pid = static_cast<int>(child);
        check(qfli_mysql::register_child(pid) == 0, "register_child accepts the racy framework pid");
        // The framework reaps the child before stop() runs.
        int status = 0;
        check(waitpid(child, &status, 0) == child, "framework reaps the child externally");
        check(WIFEXITED(status) && WEXITSTATUS(status) == 3, "reaped child exit code is 3");
        // Signalling now must be refused: the verified identity is gone.
        check(qfli_mysql::signal_child(pid, false) != 0,
              "signal refuses a gone registered identity");
        // poll marks it exited with the sentinel; completion from the observed
        // exit record replaces it with the real code.
        qfli_mysql::ChildStatus observed = qfli_mysql::poll_child(pid);
        check(observed.state == qfli_mysql::ChildState::Exited,
              "gone registered child is reported exited");
        check(qfli_mysql::complete_registered_child(pid, 3) == 0,
              "completion from the exit record succeeds");
        check(qfli_mysql::poll_child(pid).exit_code == 3,
              "settled exit code is the real recorded value");
        check(qfli_mysql::release_child(pid) == 0, "release succeeds after racy completion");
    }

    // 7. Regression: a non-CLOEXEC descriptor inherited from the parent must
    //    not leak into the exec'd launcher child.
    {
        const int fixture = open(directory.c_str(), O_RDONLY | O_DIRECTORY);
        check(fixture >= 3, "test opens a non-CLOEXEC fixture descriptor");
        if (fixture >= 3) {
            const int flags = fcntl(fixture, F_GETFD);
            check((flags & FD_CLOEXEC) == 0, "fixture descriptor is not close-on-exec");
            const std::string exit_file = directory + "/fdreport.exit";
            const std::string report = directory + "/fds.txt";
            const int pid = qfli_mysql::start_child(
                launcher, payload_with_fd_report(exit_file, report), log).pid;
            check(pid > 1, "fd-report child starts");
            check(await_exit(pid, 5000).state == qfli_mysql::ChildState::Exited,
                  "fd-report child exits");
            qfli_mysql::release_child(pid);
            const std::string listing = read_file(report);
            const std::string fixture_name = std::to_string(fixture);
            // The report contains one fd number per line; the fixture must be
            // absent unless it happens to be stdio or the error pipe.
            bool leaked = false;
            std::size_t start = 0;
            while (start < listing.size()) {
                const std::size_t end = listing.find('\n', start);
                const std::string line = listing.substr(start, end - start);
                if (line == fixture_name) leaked = true;
                if (end == std::string::npos) break;
                start = end + 1;
            }
            check(!listing.empty(), "fd-report child wrote its descriptor list");
            check(!leaked, "non-CLOEXEC fixture descriptor did not leak into the child");
            close(fixture);
        }
    }

    // 8. Regression: an unverified/recycled PID is never signalled.
    {
        const pid_t child = fork();
        if (child == 0) {
            sleep(1);
            _exit(0);
        }
        const int pid = static_cast<int>(child);
        check(qfli_mysql::register_child(pid) == 0, "register_child records a stable identity");
        int status = 0;
        check(waitpid(child, &status, 0) == child, "test reaps the registered child");
        // The registered process is gone; signalling must refuse rather than
        // risk hitting a recycled PID.
        check(qfli_mysql::signal_child(pid, false) != 0,
              "signal_child refuses a reaped/recycled registered pid");
        qfli_mysql::release_child(pid);
    }

    if (failures != 0) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("all host lifecycle checks passed\n");
    return 0;
}
