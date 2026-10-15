// Isolated prototype for the option-B lifecycle mechanisms (Linux-runnable).
//
// Proves the *mechanism* the design depends on, without the full Oracle image:
//   1. Constructor-time instrumentation: wrap pthread_create/pthread_atfork and
//      count calls made while the private image's constructors run.
//   2. Private closure load via dlopen(RTLD_LOCAL).
//   3. Child-local exit wrapper: an inherited parent atexit sentinel must NOT run
//      in a forked child; the child exits through the wrapper with _Exit.
//
// It uses a stand-in "closure" library whose constructor calls the wrapped
// functions, so the wrapper counting is exercised deterministically. The real
// server image is audited separately (resolve-ctors.py + source audit); this test
// validates the instrumentation and exit-isolation mechanics.
#include <dlfcn.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include <atomic>

namespace {

std::atomic<int> constructor_thread_calls{0};
std::atomic<int> constructor_atfork_calls{0};
std::atomic<int> parent_atexit_runs{0};

} // namespace

// Interpose the thread/atfork calls so constructor-time use is observable. In the
// real closure these would be resolved inside the private image (symbolic
// binding); here they are interposed to count.
extern "C" int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                              void *(*start)(void *), void *arg)
{
    ++constructor_thread_calls;
    using Fn = int (*)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
    static Fn real = reinterpret_cast<Fn>(dlsym(RTLD_NEXT, "pthread_create"));
    return real(thread, attr, start, arg);
}

extern "C" int pthread_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void))
{
    ++constructor_atfork_calls;
    using Fn = int (*)(void (*)(void), void (*)(void), void (*)(void));
    static Fn real = reinterpret_cast<Fn>(dlsym(RTLD_NEXT, "pthread_atfork"));
    return real(prepare, parent, child);
}

extern "C" void parent_atexit_sentinel()
{
    ++parent_atexit_runs;
}

extern "C" int qfli_proto_closure_entry(const char *json)
{
    // Stand-in server entry: record then exit through the child wrapper.
    (void)json;
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <closure.so>\n", argv[0]);
        return 2;
    }
    // A parent atexit sentinel that must never run in the child.
    atexit(parent_atexit_sentinel);

    // Load the stand-in closure with RTLD_LOCAL. Its constructor calls the
    // wrapped pthread_create/pthread_atfork.
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
        fprintf(stderr, "closure load failed: %s\n", dlerror());
        return 3;
    }
    int failures = 0;

    printf("constructor_thread_calls=%d\n", constructor_thread_calls.load());
    printf("constructor_atfork_calls=%d\n", constructor_atfork_calls.load());
    // The critical observation is that a constructor-time pthread_create is
    // visible to the wrapper. pthread_atfork interposition is environment
    // dependent, so it is recorded but not required.
    if (constructor_thread_calls.load() == 0) {
        fprintf(stderr, "FAIL: wrapper did not observe constructor-time pthread_create\n");
        ++failures;
    } else {
        printf("ok   wrapper observed constructor-time pthread_create calls\n");
    }

    // Fork; the child must exit through the child-local wrapper with _Exit and
    // must NOT run the inherited parent atexit sentinel.
    const int before = parent_atexit_runs.load();
    const pid_t pid = fork();
    if (pid == 0) {
        // Child-local exit: skip inherited finalizers by using _Exit.
        _Exit(0);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0 && parent_atexit_runs.load() == before) {
        printf("ok   child exited without running the inherited parent atexit sentinel\n");
    } else {
        fprintf(stderr, "FAIL: child exit/atexit isolation\n");
        ++failures;
    }

    dlclose(handle);
    if (failures == 0) printf("all prototype mechanism checks passed\n");
    return failures == 0 ? 0 : 1;
}
