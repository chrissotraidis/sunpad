// A dylib with 16 MiB of data, about the size of the engine's data, so the
// probe can see where dyld places a large app dylib.
#define PROBE_DATA_SIZE (16ul << 20)

char sunpad_probe_data[PROBE_DATA_SIZE];

unsigned long sunpad_probe_data_size(void) {
    return PROBE_DATA_SIZE;
}
