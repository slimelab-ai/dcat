#include "input_handler.h"
#include <string.h>
#include <unistd.h>
#include <poll.h>
#include <cglm/cglm.h>

static const float ROTATION_AMOUNT = GLM_PI / 8.0f;
static const float ZOOM_AMOUNT = 0.25f;

// Kitty keyboard protocol key codes for modifier keys
#define KITTY_LEFT_SHIFT   57441
#define KITTY_RIGHT_SHIFT  57447
#define KITTY_LEFT_CTRL    57442
#define KITTY_RIGHT_CTRL   57448

// Kitty key codes for special characters
#define KITTY_LEFT_BRACKET   91   // [
#define KITTY_RIGHT_BRACKET  93   // ]
#define KITTY_MINUS          45   // -
#define KITTY_EQUAL          61   // =

static void handle_key(InputThreadData* data, int key_code,
                       int modifiers, int event_type) {
    (void)modifiers;
    bool pressed = (event_type != 3);

    // Update FPS held-key state
    if (data->fps_controls && data->key_state) {
        switch (key_code) {
            case 'w':  data->key_state->w = pressed; break;
            case 'a':  data->key_state->a = pressed; break;
            case 's':  data->key_state->s = pressed; break;
            case 'd':  data->key_state->d = pressed; break;
            case 'i':  data->key_state->i = pressed; break;
            case 'j':  data->key_state->j = pressed; break;
            case 'k':  data->key_state->k = pressed; break;
            case 'l':  data->key_state->l = pressed; break;
            case ' ':  data->key_state->space = pressed; break;
            case 'q':  data->key_state->q = pressed; break;
            case 'v':  data->key_state->v = pressed; break;
            case 'b':  data->key_state->b = pressed; break;
            case KITTY_LEFT_BRACKET:  data->key_state->left_bracket = pressed; break;
            case KITTY_RIGHT_BRACKET: data->key_state->right_bracket = pressed; break;
            case KITTY_MINUS:         data->key_state->minus = pressed; break;
            case KITTY_EQUAL:         data->key_state->equal = pressed; break;
            case KITTY_LEFT_SHIFT: case KITTY_RIGHT_SHIFT:
                data->key_state->shift = pressed; break;
            case KITTY_LEFT_CTRL: case KITTY_RIGHT_CTRL:
                data->key_state->ctrl = pressed; break;
            default: break;
        }
    }

    // Discrete actions on press only
    if (event_type != 1) return;

    if (key_code == 'q') {
        atomic_store(data->running, false);
        return;
    }

    if (key_code == 'm') {
        bool current = vulkan_renderer_get_wireframe_mode(data->renderer);
        vulkan_renderer_set_wireframe_mode(data->renderer, !current);
    }
    
    // Effect controls
    // [ and ] cycle effects
    // - and = adjust intensity
    // Shift+- and Shift+= adjust speed
    if (key_code == KITTY_LEFT_BRACKET) {
        EffectMode current = vulkan_renderer_get_effect_mode(data->renderer);
        vulkan_renderer_set_effect_mode(data->renderer, 
            (EffectMode)((current + EFFECT_COUNT - 1) % EFFECT_COUNT));
    }
    if (key_code == KITTY_RIGHT_BRACKET) {
        vulkan_renderer_next_effect(data->renderer);
    }
    if (key_code == KITTY_MINUS && !data->key_state->shift) {
        float intensity = data->renderer->effect_intensity - 0.1f;
        vulkan_renderer_set_effect_intensity(data->renderer, intensity);
    }
    if (key_code == KITTY_EQUAL && !data->key_state->shift) {
        float intensity = data->renderer->effect_intensity + 0.1f;
        vulkan_renderer_set_effect_intensity(data->renderer, intensity);
    }
    // Shift + -/+ for speed adjustment (check modifier bit 1 for shift)
    if (key_code == KITTY_MINUS && (modifiers & 2)) {
        float speed = data->renderer->effect_speed - 0.2f;
        vulkan_renderer_set_effect_speed(data->renderer, speed);
    }
    if (key_code == KITTY_EQUAL && (modifiers & 2)) {
        float speed = data->renderer->effect_speed + 0.2f;
        vulkan_renderer_set_effect_speed(data->renderer, speed);
    }

    // Orbit camera controls
    if (!data->fps_controls) {
        switch (key_code) {
            case 'a': camera_orbit(data->camera, ROTATION_AMOUNT, 0.0f); break;
            case 'd': camera_orbit(data->camera, -ROTATION_AMOUNT, 0.0f); break;
            case 'w': camera_orbit(data->camera, 0.0f, -ROTATION_AMOUNT); break;
            case 's': camera_orbit(data->camera, 0.0f, ROTATION_AMOUNT); break;
            case 'e': camera_zoom(data->camera, ZOOM_AMOUNT); break;
            case 'r': camera_zoom(data->camera, -ZOOM_AMOUNT); break;
            default: break;
        }
    }

    // Animation controls
    if (data->has_animations) {
        switch (key_code) {
            case '1':
                data->anim_state->current_animation_index--;
                if (data->anim_state->current_animation_index < 0)
                    data->anim_state->current_animation_index =
                        (int)data->mesh->animations.count - 1;
                data->anim_state->current_time = 0.0f;
                break;
            case '2':
                data->anim_state->current_animation_index++;
                if (data->anim_state->current_animation_index >=
                    (int)data->mesh->animations.count)
                    data->anim_state->current_animation_index = 0;
                data->anim_state->current_time = 0.0f;
                break;
            case 'p':
                data->anim_state->playing = !data->anim_state->playing;
                break;
            default: break;
        }
    }
}

void* input_thread_func(void* arg) {
    InputThreadData* data = (InputThreadData*)arg;
    char buffer[512];
    ssize_t carry = 0;
    bool mouse_dragging = false;
    int last_mouse_x = 0, last_mouse_y = 0;

    while (atomic_load(data->running)) {
        struct pollfd pfd = {STDIN_FILENO, POLLIN, 0};
        if (poll(&pfd, 1, 1) <= 0 || !(pfd.revents & POLLIN)) continue;

        ssize_t n = read(STDIN_FILENO, buffer + carry,
                         (ssize_t)sizeof(buffer) - carry);
        if (n <= 0) continue;
        n += carry;
        carry = 0;

        pthread_mutex_lock(data->state_mutex);

        ssize_t i = 0;
        while (i < n) {
            if (buffer[i] != '\x1b') {
                // Fallback for raw bytes (Kitty protocol not active)
                if (buffer[i] == 'q' || buffer[i] == 'Q') {
                    atomic_store(data->running, false);
                }
                i++;
                continue;
            }

            // Need at least \x1b[X
            if (i + 2 >= n) {
                carry = n - i;
                memmove(buffer, buffer + i, carry);
                break;
            }

            if (buffer[i + 1] != '[') {
                i += 2;
                continue;
            }

            ssize_t seq_start = i;
            i += 2; // past \x1b[

            // SGR mouse: \x1b[<btn;x;yM or m
            if (buffer[i] == '<') {
                i++;
                // Find terminator M or m
                ssize_t j = i;
                while (j < n && buffer[j] != 'M' && buffer[j] != 'm') j++;
                if (j >= n) {
                    carry = n - seq_start;
                    memmove(buffer, buffer + seq_start, carry);
                    break;
                }

                // Parse btn;x;y
                int btn = 0, mx = 0, my = 0;
                ssize_t p = i;
                while (p < j && buffer[p] >= '0' && buffer[p] <= '9')
                    btn = btn * 10 + (buffer[p++] - '0');
                if (p < j && buffer[p] == ';') p++;
                while (p < j && buffer[p] >= '0' && buffer[p] <= '9')
                    mx = mx * 10 + (buffer[p++] - '0');
                if (p < j && buffer[p] == ';') p++;
                while (p < j && buffer[p] >= '0' && buffer[p] <= '9')
                    my = my * 10 + (buffer[p++] - '0');

                if (data->mouse_orbit) {
                    if (buffer[j] == 'm') {
                        mouse_dragging = false;
                    } else if (btn == 0) {
                        mouse_dragging = true;
                        last_mouse_x = mx;
                        last_mouse_y = my;
                    } else if (btn == 32 && mouse_dragging) {
                        int dx = mx - last_mouse_x;
                        int dy = my - last_mouse_y;
                        last_mouse_x = mx;
                        last_mouse_y = my;
                        if (dx != 0 || dy != 0) {
                            camera_orbit(data->camera,
                                         (float)dx * data->mouse_sensitivity,
                                         -(float)dy * data->mouse_sensitivity);
                        }
                    } else if (btn == 64) {
                        camera_zoom(data->camera, ZOOM_AMOUNT);
                    } else if (btn == 65) {
                        camera_zoom(data->camera, -ZOOM_AMOUNT);
                    }
                }

                i = j + 1;
                continue;
            }

            // Kitty keyboard / functional key CSI sequence
            // Format: CSI key[:shifted[:base]] [;mods[:event] [;text]] final
            int key_code = 0;
            while (i < n && buffer[i] >= '0' && buffer[i] <= '9') {
                key_code = key_code * 10 + (buffer[i] - '0');
                i++;
            }
            if (i >= n) {
                carry = n - seq_start;
                memmove(buffer, buffer + seq_start, carry);
                break;
            }

            // Skip :shifted[:base] sub-params
            while (i < n && buffer[i] == ':') {
                i++;
                while (i < n && buffer[i] >= '0' && buffer[i] <= '9') i++;
            }
            if (i >= n) {
                carry = n - seq_start;
                memmove(buffer, buffer + seq_start, carry);
                break;
            }

            int modifiers = 1;
            int event_type = 1;

            if (buffer[i] == ';') {
                i++;
                if (i >= n) {
                    carry = n - seq_start;
                    memmove(buffer, buffer + seq_start, carry);
                    break;
                }

                int mod_val = 0;
                while (i < n && buffer[i] >= '0' && buffer[i] <= '9') {
                    mod_val = mod_val * 10 + (buffer[i] - '0');
                    i++;
                }
                if (mod_val > 0) modifiers = mod_val;
                if (i >= n) {
                    carry = n - seq_start;
                    memmove(buffer, buffer + seq_start, carry);
                    break;
                }

                if (buffer[i] == ':') {
                    i++;
                    int evt = 0;
                    while (i < n && buffer[i] >= '0' && buffer[i] <= '9') {
                        evt = evt * 10 + (buffer[i] - '0');
                        i++;
                    }
                    if (evt > 0) event_type = evt;
                    if (i >= n) {
                        carry = n - seq_start;
                        memmove(buffer, buffer + seq_start, carry);
                        break;
                    }
                }

                // Skip ;text-as-codepoints
                if (buffer[i] == ';') {
                    i++;
                    while (i < n && !((unsigned char)buffer[i] >= 0x40 &&
                                      (unsigned char)buffer[i] <= 0x7E))
                        i++;
                    if (i >= n) {
                        carry = n - seq_start;
                        memmove(buffer, buffer + seq_start, carry);
                        break;
                    }
                }
            }

            // Final byte: u, ~, or A-Z
            unsigned char final_byte = (unsigned char)buffer[i];
            i++;

            if (final_byte == 'u' || final_byte == '~' ||
                (final_byte >= 'A' && final_byte <= 'Z')) {
                handle_key(data, key_code, modifiers, event_type);
            }
        }

        pthread_mutex_unlock(data->state_mutex);
    }

    return NULL;
}
