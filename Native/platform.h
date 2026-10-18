#pragma once
#include <cstdint>
#include <string>
struct lp_device_info {
    std::string gpu_name;
    int gpu_family = 0;
    int performance_cores = 4;
    bool tensor_hardware = false;
};
const lp_device_info & lp_device();
bool lp_low_power_mode();
uint64_t lp_available_memory();
uint64_t lp_physical_memory();
uint64_t lp_memory_footprint();
int lp_thermal_state();

double lp_cpu_seconds();
int lp_cpu_cores();
