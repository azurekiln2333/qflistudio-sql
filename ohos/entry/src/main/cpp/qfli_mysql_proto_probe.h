#ifndef QFLI_MYSQL_PROTO_PROBE_H
#define QFLI_MYSQL_PROTO_PROBE_H

// Shared result type for the option-B prototype probe. Only used when the
// prototype is enabled; it does not affect the production runtime.
struct ProtoResult {
    bool loaded = false;
    bool ready = false;
    int threadCalls = 0;
    int atforkCalls = 0;
    int exitIntercepts = 0;
    bool childExitIsolated = false;
    int childPid = -1;
    bool owned = false;
    int pendingPid = -1;
    char error[256];
};

extern "C" bool qfli_mysql_proto_probe(const char *library_path, ProtoResult *result);

// Preload host: loads the private server DSO in the parent and starts the
// server in a forked child by calling its entry directly (no exec). Returns the
// child PID (>1) or -1. DEBUG/prototype only.
extern "C" int qfli_mysql_preload_start(const char *library_path, const char *entry_params,
                                        ProtoResult *result);

#endif // QFLI_MYSQL_PROTO_PROBE_H
