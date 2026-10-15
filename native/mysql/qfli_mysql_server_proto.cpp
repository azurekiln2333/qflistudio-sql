// Prototype-only entry for the private, statically linked Oracle server image.
//
// NOT part of the production server. Built only when
// QFLI_MYSQL_PRELOAD_PROTOTYPE=ON, used by the isolated phone probe to measure,
// on the real arm64 Oracle closure:
//   * constructor-time thread creation and atfork registration, and
//   * child-local exit interception so a forked child never runs inherited
//     parent finalizers.
//
// Binding strategy (reviewer-required): the closure is linked with
// -Bsymbolic-functions and a `local:*` version script, so the image's internal
// references bind to the definitions in THIS image. We therefore define the
// interposers as real exported-within-the-image symbols and resolve the real
// libc functions EAGERLY in the parent at load time, via a library constructor
// that runs during dlopen(RTLD_NOW). The child never performs a lazy dlsym.
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <atomic>

namespace {

std::atomic<int> g_thread_calls{0};
std::atomic<int> g_atfork_calls{0};
std::atomic<int> g_exit_intercepts{0};
std::atomic<int> g_in_child_scope{0};

using CreateFn = int (*)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
using AtforkFn = int (*)(void (*)(void), void (*)(void), void (*)(void));
using ExitFn = void (*)(int);

// Resolved eagerly in the parent by the constructor below. Not atomic storage is
// fine because resolution happens before any thread uses them.
CreateFn g_real_create = nullptr;
AtforkFn g_real_atfork = nullptr;
ExitFn g_real_exit = nullptr;

void resolve_real_symbols()
{
    // Resolve the real libc functions through an explicit libc handle. RTLD_NEXT
    // is not reliable here because this runs in a library constructor during
    // dlopen; RTLD_NOLOAD reuses the already-loaded libc.
    if (g_real_create == nullptr || g_real_atfork == nullptr || g_real_exit == nullptr) {
        void *libc = dlopen("libc.so", RTLD_NOW | RTLD_NOLOAD);
        if (libc == nullptr) libc = dlopen("libc.so", RTLD_NOW);
        if (libc != nullptr) {
            if (g_real_create == nullptr) {
                g_real_create = reinterpret_cast<CreateFn>(dlsym(libc, "pthread_create"));
            }
            if (g_real_atfork == nullptr) {
                g_real_atfork = reinterpret_cast<AtforkFn>(dlsym(libc, "pthread_atfork"));
            }
            if (g_real_exit == nullptr) {
                g_real_exit = reinterpret_cast<ExitFn>(dlsym(libc, "exit"));
            }
        }
    }
}

// Library constructor: runs during dlopen(RTLD_NOW) in the PARENT, so all real
// pointers are resolved before any fork. The child only reads them.
__attribute__((constructor)) void qfli_mysql_proto_init()
{
    resolve_real_symbols();
}

void record_exit(int code)
{
    const char *path = getenv("QFLI_MYSQL_PROTO_EXIT_FILE");
    if (path == nullptr || path[0] == '\0') return;
    const int descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (descriptor < 0) return;
    char text[32];
    const int length = snprintf(text, sizeof(text), "%d\n", code);
    ssize_t written = 0;
    while (written < length) {
        const ssize_t count = write(descriptor, text + written, length - written);
        if (count <= 0) break;
        written += count;
    }
    fsync(descriptor);
    close(descriptor);
}

} // namespace

// The closure's internal calls bind here (symbolic functions + local map).
extern "C" int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                              void *(*start)(void *), void *arg)
{
    g_thread_calls.fetch_add(1);
    if (g_real_create == nullptr) resolve_real_symbols();
    return g_real_create != nullptr ? g_real_create(thread, attr, start, arg) : -1;
}

extern "C" int pthread_atfork(void (*prepare)(void), void (*parent)(void),
                              void (*child)(void))
{
    g_atfork_calls.fetch_add(1);
    if (g_real_atfork == nullptr) resolve_real_symbols();
    return g_real_atfork != nullptr ? g_real_atfork(prepare, parent, child) : -1;
}

// Child-scope exit interception. Outside child scope, forward to the real exit.
// Inside child scope, record and _Exit so no inherited finalizer runs.
extern "C" void exit(int status)
{
    if (g_in_child_scope.load() != 0) {
        g_exit_intercepts.fetch_add(1);
        record_exit(status);
        _exit(status);
    }
    if (g_real_exit == nullptr) resolve_real_symbols();
    if (g_real_exit != nullptr) g_real_exit(status);
    _exit(status);
}

extern "C" __attribute__((visibility("default")))
void qfli_mysql_proto_report(int *thread_calls, int *atfork_calls, int *exit_intercepts)
{
    if (thread_calls != nullptr) *thread_calls = g_thread_calls.load();
    if (atfork_calls != nullptr) *atfork_calls = g_atfork_calls.load();
    if (exit_intercepts != nullptr) *exit_intercepts = g_exit_intercepts.load();
}

extern "C" __attribute__((visibility("default")))
int qfli_mysql_proto_ready(void)
{
    resolve_real_symbols();
    return (g_real_create != nullptr && g_real_atfork != nullptr && g_real_exit != nullptr) ? 1 : 0;
}

extern "C" __attribute__((visibility("default")))
void qfli_mysql_proto_enter_child_scope(void)
{
    g_in_child_scope.store(1);
}

// Exercises the exit interception in a forked child: enters child scope and
// calls the image's own exit, which must record and _Exit. Never returns.
extern "C" __attribute__((visibility("default")))
void qfli_mysql_proto_child_exit(int code)
{
    g_in_child_scope.store(1);
    exit(code);
}
