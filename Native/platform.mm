#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <algorithm>
#ifdef LP_HAS_METAL
#import <Metal/Metal.h>
#endif
#if TARGET_OS_IOS
#include <os/proc.h>
#endif
#include "platform.h"

uint64_t lp_physical_memory() { return NSProcessInfo.processInfo.physicalMemory; }
int lp_thermal_state() { return static_cast<int>(NSProcessInfo.processInfo.thermalState); }
bool lp_low_power_mode() { return NSProcessInfo.processInfo.lowPowerModeEnabled; }

const lp_device_info & lp_device() {
    static const lp_device_info info = [] {
        lp_device_info result;
        int cores = 0;
        size_t size = sizeof(cores);
        if (sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nullptr, 0) == 0 && cores > 0) {
            result.performance_cores = cores;
        } else {
            result.performance_cores = std::min<int>(4, (int) NSProcessInfo.processInfo.activeProcessorCount);
        }
#ifdef LP_HAS_METAL
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device) {
            result.gpu_name = device.name.UTF8String;
            for (int family = 10; family >= 7; --family) {
                if ([device supportsFamily:(MTLGPUFamily)(1000 + family)]) {
                    result.gpu_family = family;
                    break;
                }
            }
#if !TARGET_OS_SIMULATOR
            if (@available(iOS 26.0, macOS 26.0, *)) {
                result.tensor_hardware = result.gpu_family >= 10 && [device supportsFamily:MTLGPUFamilyMetal4];
            }
#endif
            [device release];
        }
#endif
        return result;
    }();
    return info;
}

uint64_t lp_memory_footprint() {
    task_vm_info_data_t info {};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>(&info), &count) == KERN_SUCCESS) {
        return info.phys_footprint;
    }
    return 0;
}

uint64_t lp_available_memory() {
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    return os_proc_available_memory();
#else
    vm_statistics64_data_t stats {};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    vm_size_t page_size = 0;
    host_page_size(host, &page_size);
    const auto result = host_statistics64(host, HOST_VM_INFO64, reinterpret_cast<host_info64_t>(&stats), &count);
    mach_port_deallocate(mach_task_self(), host);
    if (result != KERN_SUCCESS) return 0;
    return uint64_t(stats.free_count + stats.inactive_count) * page_size;
#endif
}

int lp_cpu_cores() { return (int) NSProcessInfo.processInfo.activeProcessorCount; }
double lp_cpu_seconds() {
    task_absolutetime_info_data_t info {};
    mach_msg_type_number_t count = TASK_ABSOLUTETIME_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_ABSOLUTETIME_INFO, reinterpret_cast<task_info_t>(&info), &count) != KERN_SUCCESS) return 0;
    mach_timebase_info_data_t scale {};
    mach_timebase_info(&scale);
    return (double(info.total_user) + double(info.total_system)) * scale.numer / scale.denom / 1e9;
}
