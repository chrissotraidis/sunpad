// Checks whether this device can hold the address windows the decompiled
// engine needs (docs/DECOMP-ENGINE-PLAN.md, task E1.1). It uses the same
// allocation calls as sms-pc-port's platform layer: an mmap hint whose result
// must equal the hint, and a hinted scan for the low window. It writes a JSON
// report to Documents and logs it with the prefix SUNPAD_ENGINE_PROBE.
#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <sys/mman.h>
#include <sys/sysctl.h>

extern char sunpad_probe_data[];
extern unsigned long sunpad_probe_data_size(void);

static const uint64_t kLowBase = 0x100000000ull;  // PORT_GAME_LO
static const uint64_t kMem1Size = 64ull << 20;    // 64-bit MEM1

static NSString *Hex(uint64_t value) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)value];
}

static NSDictionary *TryHighBase(uint64_t base) {
    void *want = (void *)(uintptr_t)(base + 0x80000000ull);
    void *got = mmap(want, kMem1Size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    BOOL exact = got == want;
    BOOL roundTrip = NO;
    if (exact) {
        volatile uint8_t *bytes = (volatile uint8_t *)got;
        bytes[0] = 0x5A;
        bytes[kMem1Size - 1] = 0xA5;
        uint32_t gameAddress = (uint32_t)(uintptr_t)got;
        roundTrip = gameAddress == 0x80000000u && base + gameAddress == (uint64_t)(uintptr_t)got
            && bytes[0] == 0x5A && bytes[kMem1Size - 1] == 0xA5;
    }
    if (got != MAP_FAILED)
        munmap(got, kMem1Size);
    return @{
        @"base": Hex(base),
        @"result": got == MAP_FAILED ? @"failed" : Hex((uint64_t)(uintptr_t)got),
        @"exact": @(exact),
        @"roundTrip": @(roundTrip),
    };
}

// The engine's low_map: hints from 256 MiB to 2 GiB above PORT_GAME_LO.
static NSDictionary *TryLowWindow(size_t size) {
    const uint64_t lo = kLowBase + 0x10000000ull, hi = kLowBase + 0x80000000ull;
    for (uint64_t at = lo; at + size <= hi; at += 0x100000ull) {
        void *q = mmap((void *)(uintptr_t)at, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (q == MAP_FAILED)
            continue;
        uint64_t placed = (uint64_t)(uintptr_t)q;
        munmap(q, size);
        if (placed >= at && placed + size <= hi)
            return @{@"size": @(size), @"placed": Hex(placed), @"inWindow": @YES};
    }
    return @{@"size": @(size), @"inWindow": @NO};
}

static BOOL InLowWindow(uint64_t start, uint64_t end) {
    return start >= kLowBase + 0x10000ull && end <= kLowBase + 0x80000000ull;
}

static NSArray *AppImages(void) {
    NSMutableArray *rows = [NSMutableArray array];
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (!strstr(name, ".app/"))
            continue;
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        uint64_t start = (uint64_t)(uintptr_t)header, end = start;
        const struct load_command *command = (const struct load_command *)(header + 1);
        for (uint32_t c = 0; c < header->ncmds; c++) {
            if (command->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
                uint64_t segmentEnd = segment->vmaddr + _dyld_get_image_vmaddr_slide(i) + segment->vmsize;
                if (strcmp(segment->segname, "__PAGEZERO") != 0 && segmentEnd > end)
                    end = segmentEnd;
            }
            command = (const struct load_command *)((const char *)command + command->cmdsize);
        }
        [rows addObject:@{
            @"name": [@(name) lastPathComponent],
            @"start": Hex(start),
            @"end": Hex(end),
            @"inLowWindow": @(InLowWindow(start, end)),
        }];
    }
    return rows;
}

static NSArray *Regions(void) {
    NSMutableArray *rows = [NSMutableArray array];
    vm_address_t address = (vm_address_t)kLowBase;
    while (rows.count < 400) {
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;
        if (vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64,
                         (vm_region_info_t)&info, &count, &object) != KERN_SUCCESS)
            break;
        [rows addObject:[NSString stringWithFormat:@"%@-%@ %d/%d", Hex(address), Hex(address + size),
                         info.protection, info.max_protection]];
        address += size;
    }
    return rows;
}

static NSDictionary *RunProbe(void) {
    char machine[64] = {0};
    size_t length = sizeof machine;
    sysctlbyname("hw.machine", machine, &length, NULL, 0);
    task_vm_info_data_t vm = {0};
    mach_msg_type_number_t vmCount = TASK_VM_INFO_COUNT;
    task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &vmCount);

    NSMutableArray *high = [NSMutableArray array];
    const uint64_t candidates[] = {
        0x10000000000ull, 0x7000000000ull, 0x4000000000ull, 0x2000000000ull,
        0x1000000000ull, 0x800000000ull, 0x400000000ull, 0x300000000ull, 0x200000000ull,
    };
    for (size_t i = 0; i < sizeof candidates / sizeof candidates[0]; i++)
        [high addObject:TryHighBase(candidates[i])];

    uint64_t dataStart = (uint64_t)(uintptr_t)sunpad_probe_data;
    uint64_t dataEnd = dataStart + sunpad_probe_data_size();
    return @{
        @"schema": @1,
        @"machine": @(machine),
        @"system": [NSString stringWithFormat:@"%@ %@", UIDevice.currentDevice.systemName,
                    UIDevice.currentDevice.systemVersion],
        @"taskMinAddress": Hex(vm.min_address),
        @"taskMaxAddress": Hex(vm.max_address),
        @"images": AppImages(),
        @"dylibData": @{@"start": Hex(dataStart), @"end": Hex(dataEnd),
                        @"inLowWindow": @(InLowWindow(dataStart, dataEnd))},
        @"highBases": high,
        @"lowStack8MiB": TryLowWindow(8u << 20),
        @"lowPool128MiB": TryLowWindow(128u << 20),
        @"regions": Regions(),
    };
}

// The probe runs before UIKit starts, so it measures the same address space a
// game engine sees at launch and needs no scene lifecycle. UIKit then keeps
// the app open with an empty screen until the system closes it.
int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSData *json = [NSJSONSerialization dataWithJSONObject:RunProbe() options:NSJSONWritingPrettyPrinted error:nil];
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *name = [NSString stringWithFormat:@"engine-memory-probe-%ld.json", (long)NSDate.date.timeIntervalSince1970];
        [json writeToFile:[documents stringByAppendingPathComponent:name] atomically:YES];
        NSLog(@"SUNPAD_ENGINE_PROBE %@", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
        return UIApplicationMain(argc, argv, nil, nil);
    }
}
