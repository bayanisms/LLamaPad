#include "LlamaNative.h"
#include <fstream>
#include <iostream>
#include <sstream>
#include <csignal>
#include <thread>
#include <chrono>
static volatile sig_atomic_t stop_requested = 0;
static void handle_signal(int) { stop_requested = 1; }
int main(int argc, char ** argv) {
    if (argc != 2) { std::cerr << "Usage: llamapad-host configuration.json\n"; return 2; }
    std::ifstream file(argv[1]);
    std::stringstream input;
    input << file.rdbuf();
    auto runtime = lp_runtime_create();
    if (char * error = lp_runtime_start(runtime, input.str().c_str())) {
        std::cerr << error << '\n'; lp_string_free(error); lp_runtime_destroy(runtime); return 1;
    }
    signal(SIGINT, handle_signal); signal(SIGTERM, handle_signal);
    while (!stop_requested) {
        char * snapshot = lp_runtime_snapshot(runtime);
        std::cout << snapshot << std::endl;
        const std::string state(snapshot);
        lp_string_free(snapshot);
        if (state.find("\"state\":\"failed\"") != std::string::npos) {
            lp_runtime_destroy(runtime); return 1;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
    lp_runtime_destroy(runtime);
}
