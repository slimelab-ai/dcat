# Procedural Animation Effects for dcat

This document describes the new procedural animation effects system added to dcat (3D terminal model viewer).

## Overview

A comprehensive procedural effects system has been integrated into dcat, enabling dynamic, GPU-driven visual effects that can be toggled and controlled in real-time. The system includes 7 unique effects with independent intensity and speed controls.

## Available Effects

### 1. **Wave** - Rippling vertex displacement
- **Vertex Effect**: Sine wave displacement along multiple axes
- **Fragment Effect**: Cyan/blue energy ripples following vertex waves
- **Use Case**: Organic, fluid-like motion applied to any 3D model

### 2. **Glitch** - Cyberpunk digital distortion
- **Vertex Effect**: Random vertex jitter triggered probabilistically, creating discontinuous jumps
- **Fragment Effect**: 
  - RGB channel separation and random channel swapping
  - Scanline distortion
  - Color component flickering
- **Use Case**: Corrupted digital asset look, matrix-like effects

### 3. **Holographic** - Sci-fi projection effect
- **Vertex Effect**: Subtle positional wobbling with synchronized oscillation
- **Fragment Effect**:
  - Animated scanlines with real-time glitch blocks
  - Rainbow hue shifting based on position
  - Brightness flickering for stability loss
- **Use Case**: Hologram, display glitch, or digital projection aesthetics

### 4. **Pulse** - Energetic wave expansion
- **Vertex Effect**: Time-based breathing expansion and contraction
- **Fragment Effect**:
  - Concentric energy rings expanding outward
  - Warm color core glow with pulsing rhythm
  - Distance-based intensity falloff
- **Use Case**: Life energy, charging effects, or power cores

### 5. **Vortex** - Swirling spiral distortion
- **Vertex Effect**: Twisted rotation around vertical axis with position-dependent twist angle
- **Fragment Effect**:
  - Animated spiral patterns based on angle and distance
  - Rotating color swirl overlay
  - Purple/magenta energy coloring
- **Use Case**: Portals, tornadoes, black hole effects

### 6. **Breath** - Organic expansion breathing
- **Vertex Effect**: Smooth sinusoidal scale modulation affecting entire model
- **Fragment Effect**:
  - Subsurface scattering-like effect based on normal orientation
  - Interpolated color gradients (pink ↔ green)
  - Life-like glow modulation
- **Use Case**: Living organisms, biological entities, heartbeat effects

### 7. **Jello** - Wobbly jelly physics look
- **Vertex Effect**: Complex multi-axis wobble with harmonic frequencies
- **Fragment Effect**:
  - Subsurface lighting simulation
  - Color interpolation with positional modulation
  - Translucent glow highlights
- **Use Case**: Jelly, slime, soft-body objects, gelatinous creatures

## Control System

### Keyboard Controls

| Key | Action |
|-----|--------|
| `[` | Previous effect |
| `]` | Next effect |
| `-` | Decrease effect intensity |
| `+` | Increase effect intensity |
| `Shift + -` | Decrease effect speed |
| `Shift + +` | Increase effect speed |
| `m` | Toggle wireframe (unchanged) |
| `p` | Play/pause animation (unchanged) |
| `1`/`2` | Switch animations (unchanged) |

### Status Bar Display

The status bar now shows:
```
FPS: 60.0 | SPEED: 1.00 | POS: 0.12, 0.34, 2.56 | ANIM: Walk | EFFECT: Wave (I:1.0 S:1.0)
```

- **I**: Effect intensity (0.0 to 2.0)
- **S**: Effect speed (0.1 to 5.0)

## Technical Implementation

### Architecture

The procedural effects system is implemented across multiple components:

#### 1. **Shader System** (shader.vert & shader.frag)

**Push Constants** (updated per frame):
```c
typedef struct PushConstants {
    mat4 mvp;
    mat4 model;
    float time;              // Global time accumulator
    uint32_t effect_mode;    // Current effect enum
    float effect_intensity;  // User-controlled intensity (0-2)
    float effect_speed;      // User-controlled speed multiplier (0.1-5)
} PushConstants;
```

**Fragment Uniforms** (updated per frame):
```c
typedef struct FragmentUniforms {
    // ... existing fields ...
    uint32_t effect_mode;
    float time;
    float effect_intensity;
    float effect_speed;
} FragmentUniforms;
```

**Vertex Shader Features**:
- Procedural noise function (simplex noise) for natural-looking displacements
- Effect mode dispatch switch on `pushConstants.effectMode`
- Local position tracking for effect calculations
- Normal vector preservation and transformation

**Fragment Shader Features**:
- Hash-based procedural noise for random patterns
- FBM (Fractional Brownian Motion) noise for complex patterns
- Procedural color generation based on position and time
- Smooth interpolation and blending

#### 2. **Renderer System** (vulkan_renderer.h/c)

**New EffectMode Enum**:
```c
typedef enum {
    EFFECT_NONE = 0,
    EFFECT_WAVE,
    EFFECT_GLITCH,
    EFFECT_HOLOGRAPHIC,
    EFFECT_PULSE,
    EFFECT_VORTEX,
    EFFECT_BREATH,
    EFFECT_JELLO,
    EFFECT_COUNT
} EffectMode;
```

**New Renderer Fields**:
```c
EffectMode effect_mode;
float effect_intensity;
float effect_speed;
float effect_time;  // Accumulated time
```

**New Renderer Functions**:
```c
void vulkan_renderer_set_effect_mode(VulkanRenderer* r, EffectMode mode);
EffectMode vulkan_renderer_get_effect_mode(const VulkanRenderer* r);
void vulkan_renderer_next_effect(VulkanRenderer* r);
void vulkan_renderer_set_effect_intensity(VulkanRenderer* r, float intensity);
void vulkan_renderer_set_effect_speed(VulkanRenderer* r, float speed);
void vulkan_renderer_update_effect_time(VulkanRenderer* r, float delta_time);
const char* vulkan_renderer_get_effect_name(const VulkanRenderer* r);
```

#### 3. **Input Handler** (input_handler.h/c)

**New Key State Fields**:
```c
typedef struct KeyState {
    // ... existing keys ...
    bool left_bracket;   // [
    bool right_bracket;  // ]
    bool minus;          // -
    bool equal;          // =
} KeyState;
```

**Key Handlers**:
- `[` / `]`: Cycle through effects (previous/next)
- `-` / `+`: Adjust effect intensity in real-time
- `Shift + -` / `Shift + +`: Adjust effect speed

#### 4. **Terminal Display** (terminal.h/c)

**New Status Bar Function**:
```c
void draw_status_bar_with_effects(
    float fps, 
    float speed, 
    const float* pos,
    const char* animation_name, 
    const char* effect_name,
    float effect_intensity, 
    float effect_speed);
```

Shows effect name and current intensity/speed parameters.

#### 5. **Main Loop** (main.c)

**Effect Time Update**:
```c
// Called each frame in the main render loop
vulkan_renderer_update_effect_time(renderer, delta_time);
```

## Mathematical Details

### Wave Effect
```glsl
float wave = sin(pos.y * 3.0 + time * speed);
wave += sin(pos.x * 2.0 + time * speed * 0.7) * 0.5;
wave += sin(pos.z * 4.0 + time * speed * 1.3) * 0.3;
pos = pos + normal * wave * 0.1 * intensity;
```

### Glitch Effect
```glsl
float glitch = step(0.98, sin(t * 50.0)) * intensity;  // Probabilistic trigger
vec3 offset = vec3(sin(t * 123.456), cos(t * 789.012), sin(t * 345.678)) * glitch;
// Random per-vertex glitch based on position hash
```

### Vortex Effect
```glsl
float angle = t + length(pos.xz) * 2.0;
float twist = sin(pos.y * 2.0 + t) * intensity;
// Apply rotation matrix with twist
```

### Holographic Scanlines
```glsl
float scanline = sin(pos.y * 100.0 + time * 10.0) * 0.1;
float glitch = step(0.99, hash(vec2(floor(time * 20.0), floor(pos.y * 50.0))));
```

## Performance Considerations

- **GPU-Driven**: All calculations performed on GPU per-vertex and per-fragment
- **No CPU Overhead**: Effect time is simple accumulation, intensity/speed are just uniforms
- **Real-Time Adjustment**: No recompilation needed to change intensity or speed
- **Scalable**: Effects scale to any model complexity (vertex count independent relative cost)

## Usage Examples

### Wave Simulation
```bash
./dcat model.glb
# Press ] to cycle to Wave effect
# Press + to increase intensity for more dramatic waves
# Press Shift++ to increase wave speed
```

### Holographic Character
```bash
./dcat character.glb
# Press [] multiple times to find Holographic
# Adjust with +/- for intensity (strong = more scanlines)
# Press Shift for speed control (faster = more flicker)
```

### Creature Animation
```bash
./dcat creature.glb
# Use Breath or Jello for organic movement
# Combine with model animations (1/2 keys)
# Adjust intensity to enhance or subtly apply
```

## Future Enhancement Ideas

1. **Combined Effects**: Stack multiple effects for more complex visuals
2. **Effect Morphing**: Smooth transitions between effect modes
3. **Custom Parameters**: Per-effect fine-tuning (frequency, amplitude, etc.)
4. **Effect Presets**: Save/load effect configurations
5. **Particle Effects**: Add particle systems triggered by effects
6. **Audio Sync**: Beat-sync effects to audio input
7. **Effect Recording**: Keyframe effect parameters for animation
8. **Procedural Texture Generation**: Effects that modify textures procedurally

## Building with Effects

```bash
cd dcat
meson setup build
meson compile -C build
./build/dcat /path/to/model.glb
```

## Troubleshooting

### Effects Not Visible
1. Check that effect intensity is > 0 (default is 1.0)
2. Press `]` to cycle to a different effect
3. Check status bar shows effect name (not "None")

### Performance Issues
1. Reduce model complexity with topology optimization
2. Lower target FPS with `--target-fps` flag
3. Reduce effect intensity if performance drops

### Visual Artifacts
- Some effects may interact with existing lighting/materials
- Adjust `fog_color` and lighting for better blending
- Try different effects to find best combination

## Credits

Procedural effects system implemented with GPU-accelerated noise functions and real-time shader techniques. Compatible with existing dcat rendering pipeline and model formats.
