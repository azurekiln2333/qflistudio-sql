#include <openssl/evp.h>
#include <openssl/ssl.h>

/* This verifies target linking only; it is not a runtime probe. */
int qfli_openssl_link_smoke(void) {
  SSL_CTX *context = SSL_CTX_new(TLS_method());
  const EVP_MD *digest = EVP_sha256();
  SSL_CTX_free(context);
  return digest != NULL;
}
