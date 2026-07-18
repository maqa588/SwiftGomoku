#ifndef RAPFI_BRIDGE_H
#define RAPFI_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*EngineOutputCallback)(const char* output);

void rapfi_init(EngineOutputCallback callback, int argc, char* argv[]);
void rapfi_shutdown();
void rapfi_send_command(const char* command);

#ifdef __cplusplus
}
#endif

#endif // RAPFI_BRIDGE_H
