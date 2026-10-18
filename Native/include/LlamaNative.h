#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct lp_runtime * lp_runtime_t;
lp_runtime_t lp_runtime_create(void);
// NULL means accepted. A non-NULL error and snapshots must be freed with lp_string_free.
char * lp_runtime_start(lp_runtime_t runtime, const char * configuration_json);
void lp_runtime_stop(lp_runtime_t runtime);
char * lp_runtime_snapshot(lp_runtime_t runtime);
// Waits for all work to stop. Call off the main UI thread.
void lp_runtime_destroy(lp_runtime_t runtime);
void lp_string_free(char * string);

#ifdef __cplusplus
}
#endif
