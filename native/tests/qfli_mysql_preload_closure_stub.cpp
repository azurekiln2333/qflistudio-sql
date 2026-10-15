// Stand-in private closure for the option-B mechanism test.
//
// Its static constructor calls pthread_create and pthread_atfork so the test's
// interposed wrappers (which are resolved globally when this library is loaded
// with RTLD_GLOBAL-less interposition, i.e. the test binary's definitions
// preempt) observe constructor-time calls. This models a server constructor that
// spawns a thread or registers an atfork handler during load.
#include <pthread.h>
#include <unistd.h>

namespace {

void *noop_thread(void *)
{
    return nullptr;
}

void noop_handler() {}

struct ConstructorSideEffects {
    ConstructorSideEffects()
    {
        pthread_t thread;
        pthread_create(&thread, nullptr, noop_thread, nullptr);
        pthread_join(thread, nullptr);
        pthread_atfork(noop_handler, noop_handler, noop_handler);
    }
};

ConstructorSideEffects g_side_effects;

} // namespace
