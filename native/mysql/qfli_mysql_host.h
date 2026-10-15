#ifndef QFLI_MYSQL_HOST_H
#define QFLI_MYSQL_HOST_H

#include <string>

// Process hosting for the bundled Oracle MySQL child.
//
// On phones the HarmonyOS native-child API is unavailable, so the runtime forks
// and executes a packaged PIE launcher that loads the server library in a fresh
// process image. On PC/2-in-1 and tablets the native-child API is used instead
// and registered through the same tracked-child table.
namespace qfli_mysql {

enum class ChildState {
    // The pid is not a child owned by this host.
    Unknown = 0,
    // The child is still running.
    Running = 1,
    // The child exited and its exact exit code is available.
    Exited = 2,
};

struct ChildStatus {
    ChildState state = ChildState::Unknown;
    // Valid only when state == ChildState::Exited. 128 + signal if killed.
    int exit_code = 0;

    bool running() const { return state == ChildState::Running; }
    bool exited() const { return state == ChildState::Exited; }
};

// Registers a PID owned by another host (the HarmonyOS native-child API) so
// poll/terminate can manage it through the same tracked table. The framework may
// be the real parent, so this child is not waitpid()-reaped: liveness is derived
// from a verified process identity plus a signal-0 probe, and completion comes
// from the shell's own exit record, never from waitpid ECHILD. Returns 0 on
// success, -1 if the pid is invalid or its identity cannot be captured.
int register_child(int pid);

// Adopts a PID forked by another translation unit (the preload host) into the
// same waitpid-owned tracking as start_child()'s forked children. The child is a
// direct fork of this process, so waitpid() is the authoritative reaper.
int adopt_forked_child(int pid);

// Completes a registered (non-waitpid) child after its exit record is observed.
// Returns 0 on success, -1 if the pid is unknown or not yet reaped.
int complete_registered_child(int pid, int exit_code);

// Reads the child's two-int exec-error frame from a pipe descriptor.
//
//   Returns 1  and fills errors[0..1] when a complete frame arrived.
//   Returns 0  on a clean zero-byte EOF (no exec error was reported; this is
//              not proof exec succeeded, only that no failure frame arrived).
//   Returns -1 on a partial frame or a read error (protocol failure).
// Only a clean zero-byte EOF may be treated as "no error frame"; a partial
// frame or read error must never be treated as success. Exposed for testing.
int read_error_frame(int descriptor, int errors[2]);

// Outcome of start_child. On failure the caller still owns `pending_pid` when
// `owned` is true: the child could not be confirmed terminated, so it is RETAINED
// in the owned-child table and must be cleaned through the normal lifecycle
// (signal/terminate + poll + release) reachable from stop()/dispose(). This
// makes a pending owned child explicit at the API boundary rather than an
// unreachable map entry.
struct StartResult {
    // > 1 on success; -1 on failure.
    int pid = -1;
    // True when `pending_pid` is a still-owned child that needs lifecycle cleanup.
    bool owned = false;
    // The owned child pid to clean up when `owned` is true (else -1).
    int pending_pid = -1;
    bool succeeded() const { return pid > 1; }
};

// Prepares argument storage before fork and execs launcher_path with
// entry_params. Allocates nothing in the child and uses only async-signal-safe
// operations before execve. A parent-side error pipe reports the child's exec
// errno without stdio/allocation. Returns a structured result: on success the
// child pid; on failure a negative pid plus, when the child could not be
// confirmed terminated, an owned pending pid for lifecycle cleanup.
StartResult start_child(const std::string &launcher_path, const std::string &entry_params,
                        const std::string &log_path);

// Reports an owned child's status. Repeatable: an exited child keeps reporting
// Exited with the same code until release_child().
ChildStatus poll_child(int pid);

// Releases a completed child's retained status. Rejects a still-running child.
// Returns 0 on success, -1 if the pid is unknown or still running.
int release_child(int pid);

// Signal-only cancellation: sends SIGTERM (or SIGKILL when force is true) to an
// owned child. Returns 0 if the signal was delivered, -1 if the pid is not
// owned. The caller polls poll_child() with bounded escalation and only reports
// success after observing Exited.
int signal_child(int pid, bool force);

} // namespace qfli_mysql

#endif // QFLI_MYSQL_HOST_H
