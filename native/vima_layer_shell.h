#ifndef VIMA_LAYER_SHELL_H
#define VIMA_LAYER_SHELL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VimaLayerShell VimaLayerShell;

int vima_layer_shell_supported(void);
VimaLayerShell *vima_layer_shell_attach(void *display, void *surface);
void vima_layer_shell_destroy(VimaLayerShell *state);
uint32_t vima_layer_shell_width(const VimaLayerShell *state);
uint32_t vima_layer_shell_height(const VimaLayerShell *state);
int vima_layer_shell_closed(const VimaLayerShell *state);

#ifdef __cplusplus
}
#endif

#endif
