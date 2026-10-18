#pragma once

#include "ggml-backend.h"

#ifdef  __cplusplus
extern "C" {
#endif

#define RPC_PROTO_MAJOR_VERSION    8
#define RPC_PROTO_MINOR_VERSION    0
#define RPC_PROTO_PATCH_VERSION    0

#ifdef  __cplusplus
static_assert(GGML_OP_COUNT == 101, "GGML_OP_COUNT has changed - update RPC_PROTO_PATCH_VERSION");
#endif

#define GGML_RPC_MAX_SERVERS       16

// Optional lifecycle and allocation budget for an embedded, single-client TCP worker.
// The owner must join run_server before freeing its control or callback data.
typedef struct ggml_rpc_server_control * ggml_rpc_server_control_t;
typedef size_t (*ggml_rpc_memory_available_t)(void * user_data);
GGML_BACKEND_API ggml_rpc_server_control_t ggml_rpc_server_control_new(
    size_t allocation_limit, ggml_rpc_memory_available_t available, void * user_data);
GGML_BACKEND_API void ggml_rpc_server_control_stop(ggml_rpc_server_control_t control);
GGML_BACKEND_API void ggml_rpc_server_control_free(ggml_rpc_server_control_t control);
GGML_BACKEND_API bool ggml_rpc_server_control_ready(ggml_rpc_server_control_t control);
GGML_BACKEND_API size_t ggml_rpc_server_control_allocated(ggml_rpc_server_control_t control);
GGML_BACKEND_API bool ggml_backend_rpc_run_server(const char * endpoint, const char * cache_dir,
    size_t n_threads, size_t n_devices, ggml_backend_dev_t * devices, ggml_rpc_server_control_t control);

struct ggml_rpc_server_stats {
    uint64_t bytes_received;
    uint64_t bytes_sent;
    uint64_t graph_calls;
    uint64_t dispatch_nanoseconds;
    uint64_t allocation_limit;
    uint32_t connected_clients;
};
GGML_BACKEND_API void ggml_rpc_server_control_stats(ggml_rpc_server_control_t control, struct ggml_rpc_server_stats * stats);

// backend API
GGML_BACKEND_API ggml_backend_t ggml_backend_rpc_init(const char * endpoint, uint32_t device);
GGML_BACKEND_API bool ggml_backend_is_rpc(ggml_backend_t backend);

GGML_BACKEND_API ggml_backend_buffer_type_t ggml_backend_rpc_buffer_type(const char * endpoint, uint32_t device);

GGML_BACKEND_API void ggml_backend_rpc_get_device_memory(const char * endpoint, uint32_t device, size_t * free, size_t * total);

GGML_BACKEND_API void ggml_backend_rpc_start_server(const char * endpoint, const char * cache_dir,
                                                    size_t n_threads, size_t n_devices, ggml_backend_dev_t * devices);

GGML_BACKEND_API ggml_backend_reg_t ggml_backend_rpc_reg(void);
GGML_BACKEND_API ggml_backend_reg_t ggml_backend_rpc_add_server(const char * endpoint);

#ifdef  __cplusplus
}
#endif
