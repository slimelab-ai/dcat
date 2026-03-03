#ifndef DCAT_INPUT_HANDLER_H
#define DCAT_INPUT_HANDLER_H

#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include "../graphics/camera.h"
#include "../graphics/animation.h"
#include "../renderer/vulkan_renderer.h"
#include "../graphics/model.h"

// Key state tracking
typedef struct KeyState {
    bool w, a, s, d;
    bool i, j, k, l;
    bool space;
    bool shift;
    bool ctrl;
    bool q;
    bool m;
    bool v, b;
    bool left_bracket;   // [
    bool right_bracket;  // ]
    bool minus;          // -
    bool equal;          // =
    int mouse_dx;
    int mouse_dy;
} KeyState;

typedef struct InputThreadData {
    Camera* camera;
    VulkanRenderer* renderer;
    AnimationState* anim_state;
    Mesh* mesh;
    pthread_mutex_t* state_mutex;
    atomic_bool* running;
    bool fps_controls;
    bool mouse_orbit;
    float mouse_sensitivity;
    bool has_animations;
    KeyState* key_state;
} InputThreadData;

// Input thread function
void* input_thread_func(void* arg);

#endif
