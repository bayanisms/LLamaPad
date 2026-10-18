#include "LlamaNative.h"
#include "platform.h"
#include "common.h"
#include "log.h"
#include "llama.h"
#include "ggml-rpc.h"
#ifdef LP_HAS_METAL
#include "ggml-metal.h"
#endif
#include "server-context.h"
#include "server-http.h"
#include "server-stream.h"
#include "vendor/nlohmann/json.hpp"

#include <atomic>
#include <chrono>
#include <deque>
#include <filesystem>
#include <mutex>
#include <thread>
#include <cstdlib>
#include <cstring>

using config_json = nlohmann::json;
namespace fs = std::filesystem;
static constexpr uint64_t MiB = 1024 * 1024;
static std::mutex log_mutex;
static std::deque<std::string> log_lines;
static std::once_flag backend_once;
static std::atomic<bool> runtime_claimed {false};

static void append_log(const std::string & message) {
    std::lock_guard<std::mutex> lock(log_mutex);
    log_lines.push_back(message.substr(0, 2000));
    while (log_lines.size() > 160) log_lines.pop_front();
}

static void backend_log(enum ggml_log_level level, const char * text, void *) {
    static const bool debug = std::getenv("GGML_METAL_FUSION_DEBUG") != nullptr;
    if (level == GGML_LOG_LEVEL_DEBUG && !debug) return;
    append_log(text);
    fputs(text, stderr);
}

static char * copy_string(const std::string & text) { return strdup(text.c_str()); }

static server_http_context::handler_t safe_route(server_http_context::handler_t handler) {
    return [handler = std::move(handler)](const server_http_req & request) -> server_http_res_ptr {
        try { return handler(request); }
        catch (const std::exception & error) {
            auto response = std::make_unique<server_http_res>();
            response->status = 400;
            response->data = config_json{{"error", {{"message", error.what()}, {"type", "invalid_request_error"}}}}.dump();
            return response;
        }
    };
}

struct lp_runtime {
    std::mutex mutex;
    std::thread worker;
    std::atomic<bool> stopping {false};
    std::atomic<bool> active {false};
    std::string state = "stopped";
    std::string message = "Ready to start";
    std::string backend_name;
    double progress = 0;
    server_context * server = nullptr;
    server_http_context * http = nullptr;
    ggml_rpc_server_control_t rpc = nullptr;
    std::chrono::steady_clock::time_point started;
    uint64_t reserve = 1536 * MiB;

    void update(std::string new_state, std::string detail) {
        std::lock_guard<std::mutex> lock(mutex);
        state = std::move(new_state);
        message = std::move(detail);
        append_log(message);
    }

    void finish(std::string new_state, std::string detail) {
        std::lock_guard<std::mutex> lock(mutex);
        state = std::move(new_state);
        message = std::move(detail);
        append_log(message);
        // Publish completion with the state so a UI-observed "stopped" state
        // always permits restarting the same runtime.
        active = false;
    }

    static size_t memory_available(void * data) {
        auto * self = static_cast<lp_runtime *>(data);
        uint64_t available = lp_available_memory();
        return available > self->reserve ? available - self->reserve : 0;
    }

    void run_node(const config_json & config) {
        auto device = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU);
        if (!device) device = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU);
        if (!device) throw std::runtime_error("No Metal or CPU backend is available.");
        const uint64_t limit = std::min<uint64_t>(config.value("nodeMemoryMiB", 8192) * MiB, memory_available(this));
        if (limit < 256 * MiB) throw std::runtime_error("Not enough available memory to start a node.");
        auto control = ggml_rpc_server_control_new(limit, memory_available, this);
        struct cleanup {
            lp_runtime * self;
            ggml_rpc_server_control_t control;
            ~cleanup() {
                std::lock_guard<std::mutex> lock(self->mutex);
                self->rpc = nullptr;
                ggml_rpc_server_control_free(control);
            }
        } guard {this, control};
        {
            std::lock_guard<std::mutex> lock(mutex);
            rpc = control;
            backend_name = ggml_backend_dev_description(device);
            if (stopping) ggml_rpc_server_control_stop(control);
        }
        const std::string endpoint = (config.value("connection", "usb") == "usb" ? "127.0.0.1:" : "0.0.0.0:")
                                    + std::to_string(config.at("port").get<int>());
        std::string cache = config.value("cacheDirectory", "");
        const bool use_cache = config.value("rpcCache", true) && !cache.empty();
        if (use_cache) fs::create_directories(cache);
        const bool ok = ggml_backend_rpc_run_server(endpoint.c_str(), use_cache ? cache.c_str() : nullptr,
            config.value("threads", 4), 1, &device, control);
        if (!ok && !stopping) throw std::runtime_error("Could not start RPC. Check the port and runtime log.");
    }

    void run_server(const config_json & config) {
        const std::string path = config.at("modelPath");
        if (!fs::is_regular_file(path)) throw std::runtime_error("The selected model file is missing.");
        if (fs::file_size(path) > memory_available(this)) {
            throw std::runtime_error("Model file exceeds available app memory after the reserve. Choose a smaller quantization.");
        }
        common_params params;
        params.model.path = path;
        params.model_alias = {config.value("modelAlias", "llamapad")};
        params.hostnames = {config.value("connection", "usb") == "usb" ? "127.0.0.1" : "0.0.0.0"};
        params.port = config.at("port");
        params.n_ctx = config.value("contextSize", 4096);
        params.n_batch = config.value("batchSize", 512);
        params.n_ubatch = config.value("microBatchSize", 128);
        params.cpuparams.n_threads = config.value("threads", 4);
        params.cpuparams_batch.n_threads = params.cpuparams.n_threads;
        params.n_gpu_layers = config.value("gpuLayers", 999);
        params.n_parallel = 1;
        params.n_sequences = 1;
        params.n_threads_http = 4;
        params.cache_ram_mib = 0;
        params.cache_ram_explicit = true;
        // Hybrid-model state snapshots can consume hundreds of MiB each.
        params.n_ctx_checkpoints = 0;
        params.load_mode = LLAMA_LOAD_MODE_MMAP;
        params.fit_params = false;
        params.ui = true;
        params.use_jinja = true;
        params.endpoint_metrics = true;
        params.endpoint_slots = true;
        params.ctx_shift = true;
        params.warmup = true;
        const std::string attention = config.value("flashAttention", "auto");
        params.flash_attn_type = attention == "on" ? LLAMA_FLASH_ATTN_TYPE_ENABLED
            : attention == "off" ? LLAMA_FLASH_ATTN_TYPE_DISABLED : LLAMA_FLASH_ATTN_TYPE_AUTO;
        params.cache_type_k = params.cache_type_v = config.value("kvCacheType", "f16") == "q8_0" ? GGML_TYPE_Q8_0 : GGML_TYPE_F16;
        const std::string key = config.value("apiKey", "");
        if (!key.empty()) params.api_keys = {key};

        server_context context;
        server_routes routes(params, context);
        server_http_context web;
        struct cleanup {
            lp_runtime * self;
            server_context & context;
            server_http_context & web;
            ~cleanup() {
                {
                    std::lock_guard<std::mutex> lock(self->mutex);
                    self->server = nullptr;
                    self->http = nullptr;
                    web.is_ready = false;
                }
                context.terminate();
                server_stream_session_manager_stop();
                web.stop();
                web.join();
            }
        } guard {this, context, web};

        if (!web.init(params)) throw std::runtime_error("Could not initialize HTTP server.");
        web.get("/health", safe_route(routes.get_health));
        web.get("/v1/health", safe_route(routes.get_health));
        web.get("/models", safe_route(routes.get_models));
        web.get("/v1/models", safe_route(routes.get_models));
        web.get("/props", safe_route(routes.get_props));
        web.get("/metrics", safe_route(routes.get_metrics));
        web.get("/slots", safe_route(routes.get_slots));
        web.post("/completion", safe_route(routes.post_completions));
        web.post("/v1/completions", safe_route(routes.post_completions_oai));
        web.post("/chat/completions", safe_route(routes.post_chat_completions));
        web.post("/v1/chat/completions", safe_route(routes.post_chat_completions));
        web.post("/tokenize", safe_route(routes.post_tokenize));
        web.post("/detokenize", safe_route(routes.post_detokenize));
        web.post("/apply-template", safe_route(routes.post_apply_template));

        web.post("/v1/chat/completions/control", safe_route(routes.post_control));
        web.post("/chat/completions/input_tokens", safe_route(routes.post_chat_completions_tok));
        web.post("/v1/chat/completions/input_tokens", safe_route(routes.post_chat_completions_tok));
        web.get("/v1/stream", safe_route(server_stream_make_get_handler()));
        web.post("/v1/streams/lookup", safe_route(server_stream_make_lookup_handler()));
        web.del("/v1/stream", safe_route(server_stream_make_delete_handler()));

        context.set_state_callback([this](server_state, json payload) {
            std::lock_guard<std::mutex> lock(mutex);
            progress = payload.value("value", 0.0);
        });
        server_stream_session_manager_start();
        if (!web.start()) throw std::runtime_error("Could not listen on this port. Another service may be using it.");
        {
            std::lock_guard<std::mutex> lock(mutex);
            http = &web;
            server = &context;
        }
        if (stopping) return;
        if (!context.load_model(params)) throw std::runtime_error("Model loading failed. Check memory, model format, and the runtime log.");
        if (stopping) return;
        routes.update_meta(context);
        {
            std::lock_guard<std::mutex> lock(mutex);
            if (stopping) return;
            web.is_ready = true;
            progress = 1;
            auto device = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU);
            backend_name = device ? ggml_backend_dev_description(device) : "CPU";
            state = "running";
            message = "Inference server is ready";
        }
        append_log("Inference server ready; OpenAI chat/completions, streaming, metrics enabled.");
        context.start_loop();
    }
};

static void validate(const config_json & config) {
    const auto mode = config.value("mode", "server");
    if (mode != "server" && mode != "node") throw std::runtime_error("Unknown service mode.");
    const int port = config.value("port", 0);
    if (port < 1024 || port > 65535) throw std::runtime_error("Port must be between 1024 and 65535.");
    const auto connection = config.value("connection", "usb");
    if (connection != "usb" && connection != "network") throw std::runtime_error("Unknown connection type.");
    const int threads = config.value("threads", 4);
    if (threads < 1 || threads > 16) throw std::runtime_error("Threads must be between 1 and 16.");
    const int reserve = config.value("memoryReserveMiB", 1536);
    if (reserve < 512 || reserve > 16384) throw std::runtime_error("Memory reserve must be 512–16384 MiB.");
    const int budget = config.value("nodeMemoryMiB", 8192);
    if (budget < 512 || budget > 12288) throw std::runtime_error("Node memory budget must be 512–12288 MiB.");
    if (mode == "node") return;
    const int context = config.value("contextSize", 4096);
    const int batch = config.value("batchSize", 512);
    const int ubatch = config.value("microBatchSize", 128);
    if (context < 256 || context > 32768 || batch < 32 || batch > 2048 || ubatch < 32 || ubatch > batch) {
        throw std::runtime_error("Invalid context or batch size.");
    }
    const auto attention = config.value("flashAttention", "auto");
    const auto cache = config.value("kvCacheType", "f16");
    if ((attention != "auto" && attention != "on" && attention != "off") || (cache != "f16" && cache != "q8_0")) {
        throw std::runtime_error("Unsupported attention or KV cache configuration.");
    }
    if (cache == "q8_0" && attention != "on") throw std::runtime_error("Q8 KV requires Flash Attention on.");
    const int layers = config.value("gpuLayers", 999);
    if (layers < 0 || layers > 999) throw std::runtime_error("Invalid GPU layer count.");
    if (connection == "network" && config.value("apiKey", "").size() < 16) throw std::runtime_error("Network server requires an API key of at least 16 characters.");
}

lp_runtime_t lp_runtime_create() {
    if (runtime_claimed.exchange(true)) return nullptr;
    return new lp_runtime;
}

char * lp_runtime_start(lp_runtime_t runtime, const char * configuration_json) {
    if (!runtime) return copy_string("A runtime is already active in this process.");
    bool claimed = false;
    try {
        const auto config = config_json::parse(configuration_json);
        validate(config);
        if (runtime->active.exchange(true)) return copy_string("Stop the current service before starting another.");
        claimed = true;
        if (runtime->worker.joinable()) runtime->worker.join();
        runtime->stopping = false;
        {
            std::lock_guard<std::mutex> lock(runtime->mutex);
            runtime->started = std::chrono::steady_clock::now();
            runtime->progress = 0;
            runtime->backend_name.clear();
        }
        runtime->reserve = config.value("memoryReserveMiB", 1536) * MiB;
        runtime->update("starting", config.value("mode", "server") == "node" ? "Starting RPC node" : "Loading model");
        runtime->worker = std::thread([runtime, config] {
            try {
                std::call_once(backend_once, [] {
#ifdef LP_HAS_METAL
                    ggml_backend_metal_monitor_enable(true);
#endif
                    common_init();
                    llama_backend_init();
                    llama_log_set(backend_log, nullptr);
                    ggml_log_set(backend_log, nullptr);
                });
                if (config.value("mode", "server") == "node") runtime->run_node(config);
                else runtime->run_server(config);
                runtime->finish("stopped", "Service stopped; model memory released");
            } catch (const std::exception & error) {
                runtime->finish(runtime->stopping ? "stopped" : "failed", error.what());
            }
        });
        return nullptr;
    } catch (const std::exception & error) {
        if (claimed) {
            runtime->active = false;
            runtime->update("failed", error.what());
        }
        return copy_string(error.what());
    }
}

void lp_runtime_stop(lp_runtime_t runtime) {
    if (!runtime || !runtime->active) return;
    runtime->stopping = true;
    std::lock_guard<std::mutex> lock(runtime->mutex);
    runtime->state = "stopping";
    runtime->message = "Stopping; waiting for current work to finish";
    if (runtime->rpc) ggml_rpc_server_control_stop(runtime->rpc);
    if (runtime->http) runtime->http->is_ready = false;
    if (runtime->server) runtime->server->terminate();
}

char * lp_runtime_snapshot(lp_runtime_t runtime) {
    if (!runtime) return copy_string("{}");
    std::lock_guard<std::mutex> lock(runtime->mutex);
    uint64_t allocated = lp_memory_footprint();
    if (runtime->rpc) {
        allocated = ggml_rpc_server_control_allocated(runtime->rpc);
        if (!runtime->stopping && ggml_rpc_server_control_ready(runtime->rpc)) {
            runtime->state = "running";
            runtime->message = "RPC node is ready for a Mac coordinator";
        }
    }
    ggml_rpc_server_stats stats {};
    ggml_rpc_server_control_stats(runtime->rpc, &stats);
    uint64_t gpu_commands = 0, gpu_nanoseconds = 0;
#ifdef LP_HAS_METAL
    ggml_metal_activity gpu {};
    ggml_backend_metal_monitor_stats(&gpu);
    gpu_commands = gpu.command_count;
    gpu_nanoseconds = gpu.command_nanoseconds;
#endif
    const double uptime = runtime->active ? std::chrono::duration<double>(std::chrono::steady_clock::now() - runtime->started).count() : 0;
    std::lock_guard<std::mutex> logs_lock(log_mutex);
    return copy_string(config_json{
        {"state", runtime->state}, {"message", runtime->message}, {"progress", runtime->progress},
        {"availableMemory", lp_available_memory()}, {"physicalMemory", lp_physical_memory()},
        {"allocatedMemory", allocated}, {"thermalState", lp_thermal_state()},
        {"backend", runtime->backend_name}, {"revision", LLAMAPAD_REVISION},
        {"metalPatch", "lfm2-decode-2"},
        {"launchID", std::getenv("LLAMAPAD_RPC_LAUNCH_ID") ? std::getenv("LLAMAPAD_RPC_LAUNCH_ID") : ""},
        {"gpuName", lp_device().gpu_name}, {"gpuFamily", lp_device().gpu_family},
        {"performanceCores", lp_device().performance_cores},
        {"tensorHardware", lp_device().tensor_hardware}, {"lowPowerMode", lp_low_power_mode()},
        {"telemetry", {{"timestamp", std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count()},
            {"cpuSeconds", lp_cpu_seconds()}, {"cpuCores", lp_cpu_cores()}, {"appMemory", lp_memory_footprint()},
            {"uptime", uptime}, {"bytesReceived", stats.bytes_received}, {"bytesSent", stats.bytes_sent},
            {"graphCalls", stats.graph_calls}, {"dispatchMilliseconds", stats.dispatch_nanoseconds / 1e6},
            {"gpuCommands", gpu_commands}, {"gpuMilliseconds", gpu_nanoseconds / 1e6},
            {"connectedClients", stats.connected_clients}, {"allocationLimit", stats.allocation_limit}}},
        {"logs", log_lines}
    }.dump(-1, ' ', false, config_json::error_handler_t::replace));
}

void lp_runtime_destroy(lp_runtime_t runtime) {
    if (!runtime) return;
    lp_runtime_stop(runtime);
    if (runtime->worker.joinable()) runtime->worker.join();
    delete runtime;
    runtime_claimed = false;
}
void lp_string_free(char * string) { free(string); }
