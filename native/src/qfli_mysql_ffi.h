#ifndef QFLI_MYSQL_FFI_H
#define QFLI_MYSQL_FFI_H

#include <stddef.h>

#ifdef _WIN32
#define QFLI_MYSQL_API __declspec(dllexport)
#else
#define QFLI_MYSQL_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* The caller owns the returned UTF-8 JSON and releases it with this library. */
QFLI_MYSQL_API char *qfli_mysql_invoke(const char *request, size_t length);
QFLI_MYSQL_API void qfli_mysql_free(char *result);

#ifdef __cplusplus
}
#endif
#endif
