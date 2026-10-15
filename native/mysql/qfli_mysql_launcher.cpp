// Packaged launcher for the Oracle MySQL child process.
//
// On phones the HarmonyOS native-child API is unavailable. The NAPI host forks
// and execs this launcher as a fresh process image, so none of the
// multithreaded Flutter runtime state (locks, allocator arenas, loader state)
// is inherited into a process that then loads the MySQL server.
//
// The launcher is built as a PIE executable but staged with a .so name so it
// ships inside the HAP's native library directory. It is never dlopen()ed by
// the parent; it is only exec'd. It derives the server library path from its
// own on-disk location, so no writable data path is ever used as code.
//
// argv:
//   argv[1] = entryParams JSON
//   argv[2] = original owning app pid, captured by the host before fork
#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <string>

namespace {

using MysqlChildMain = void (*)(const char *);

// Startup diagnostics use raw writes to stderr so they work before any library
// state is relied upon. The host routes stderr to the app-private log.
void stage(const char *message)
{
    const char *cursor = message;
    std::size_t length = 0;
    while (cursor[length] != '\0') ++length;
    ssize_t written = 0;
    while (written < static_cast<ssize_t>(length)) {
        const ssize_t count = write(STDERR_FILENO, cursor + written, length - written);
        if (count <= 0) return;
        written += count;
    }
}

// Parent-death watchdog. PR_SET_PDEATHSIG is not used because the phone app
// sandbox may reject prctl (observed SIGSYS with the previous build); the exact
// filtered syscall was not proven. Instead a launcher thread polls getppid():
// when the app dies the launcher is reparented and getppid() changes. Only
// standard supported calls are used (pthread_create, getppid, nanosleep,
// _exit). No kill(parent, 0) probe: EPERM is not parent death and the getppid
// comparison against the captured original PID is sufficient.
struct WatchdogState {
    pid_t parent = 0;
};

void *parent_watchdog(void *argument)
{
    auto *state = static_cast<WatchdogState *>(argument);
    stage("[launch] watchdog-ready\n");
    const struct timespec interval = {0, 200 * 1000 * 1000};
    for (;;) {
        if (getppid() != state->parent) {
            // The owning app process is gone: stop the server with the same
            // code the host uses for a lost parent.
            stage("[launch] parent-gone\n");
            _exit(125);
        }
        nanosleep(&interval, nullptr);
    }
    return nullptr;
}

// Directory containing this launcher, resolved from its own loaded image.
// Falls back to /proc/self/exe if dladdr is unavailable.
std::string self_directory()
{
    Dl_info information{};
    if (dladdr(reinterpret_cast<void *>(&self_directory), &information) != 0 &&
        information.dli_fname != nullptr && information.dli_fname[0] != '\0') {
        std::string path(information.dli_fname);
        const std::size_t slash = path.find_last_of('/');
        if (slash != std::string::npos) return path.substr(0, slash);
    }
    char buffer[PATH_MAX];
    const ssize_t length = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
    if (length > 0) {
        buffer[length] = '\0';
        std::string path(buffer);
        const std::size_t slash = path.find_last_of('/');
        if (slash != std::string::npos) return path.substr(0, slash);
    }
    return {};
}

} // namespace

int main(int argc, char **argv)
{
    stage("[launch] launcher-main\n");
    if (argc != 3 || argv[1] == nullptr || argv[1][0] == '\0' ||
        argv[2] == nullptr || argv[2][0] == '\0') {
        std::fprintf(stderr, "MySQL launcher expects a JSON argument and the app pid\n");
        return 125;
    }
    // Validate the passed original app pid and confirm it is still our parent.
    char *end = nullptr;
    const long passed_parent = std::strtol(argv[2], &end, 10);
    if (end == nullptr || *end != '\0' || passed_parent <= 1 || passed_parent > INT_MAX) {
        std::fprintf(stderr, "MySQL launcher received an invalid app pid\n");
        return 125;
    }
    if (getppid() != static_cast<pid_t>(passed_parent)) {
        std::fprintf(stderr, "MySQL launcher parent does not match the passed app pid\n");
        return 125;
    }

    const std::string directory = self_directory();
    if (directory.empty()) {
        std::fprintf(stderr, "MySQL launcher could not resolve its directory\n");
        return 125;
    }

    // Block the signals Oracle installs handlers for BEFORE creating the
    // watchdog thread, so the watcher inherits them blocked from creation. An
    // extra unblocked thread could otherwise receive a host SIGTERM and kill the
    // whole server uncleanly once mysqld resets/installs its own handler.
    sigset_t blocked;
    sigset_t previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGTERM);
    sigaddset(&blocked, SIGINT);
    sigaddset(&blocked, SIGHUP);
    sigaddset(&blocked, SIGQUIT);
    if (pthread_sigmask(SIG_BLOCK, &blocked, &previous) != 0) {
        // Without the mask the watchdog could still take a host signal and kill
        // the server; refuse to start unprotected rather than continue.
        std::fprintf(stderr, "MySQL launcher could not block signals for the watchdog\n");
        return 125;
    }

    WatchdogState watchdog;
    watchdog.parent = static_cast<pid_t>(passed_parent);
    pthread_t watchdog_thread;
    if (pthread_create(&watchdog_thread, nullptr, parent_watchdog, &watchdog) != 0) {
        // Never start the server without parent-death protection.
        std::fprintf(stderr, "MySQL launcher could not start the parent watchdog\n");
        return 125;
    }
    pthread_detach(watchdog_thread);

    // Restore the original mask in the main thread, leaving the watchdog blocked.
    pthread_sigmask(SIG_SETMASK, &previous, nullptr);

    const std::string server_library = directory + "/libqfli_mysql_server.so";
    stage("[launch] dlopen-before\n");
    void *handle = dlopen(server_library.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (handle == nullptr) {
        std::fprintf(stderr, "MySQL server library load failed: %s\n", dlerror());
        return 125;
    }
    stage("[launch] dlopen-after\n");
    auto entry = reinterpret_cast<MysqlChildMain>(dlsym(handle, "qfli_mysql_child_main"));
    if (entry == nullptr) {
        std::fprintf(stderr, "MySQL server entry missing: %s\n", dlerror());
        return 125;
    }
    stage("[launch] entry-before\n");
    // The entry validates its JSON, records an exit code itself, and calls
    // mysqld_main. If it returns without exiting, that is a failure, not a
    // success, so report failure.
    entry(argv[1]);
    std::fflush(nullptr);
    return 1;
}
