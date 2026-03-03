#version 450

layout(set = 0, binding = 1) uniform sampler2D diffuseTexture;
layout(set = 0, binding = 2) uniform sampler2D normalTexture;

layout(set = 0, binding = 3) uniform FragmentUniforms {
    vec3 lightDir;
    uint enableLighting;
    vec3 cameraPos;
    float fogStart;
    vec3 fogColor;
    float fogEnd;
    uint useTriplanarMapping;
    uint alphaMode;    // 0: OPAQUE, 1: MASK, 2: BLEND
    float alphaCutoff;
    uint effectMode;
    float time;
    float effectIntensity;
    float effectSpeed;
} fragUniforms;

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec3 fragWorldNormal;
layout(location = 2) in vec3 fragWorldTangent;
layout(location = 3) in vec3 fragWorldBitangent;
layout(location = 4) in vec3 fragWorldPos;
layout(location = 5) in vec3 fragLocalPos;
layout(location = 6) in vec3 fragLocalNormal;

layout(location = 0) out vec4 outColor;

// Effect modes
const uint EFFECT_NONE = 0u;
const uint EFFECT_WAVE = 1u;
const uint EFFECT_GLITCH = 2u;
const uint EFFECT_HOLOGRAPHIC = 3u;
const uint EFFECT_PULSE = 4u;
const uint EFFECT_VORTEX = 5u;
const uint EFFECT_BREATH = 6u;
const uint EFFECT_JELLO = 7u;

// Hash functions for procedural noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float hash3(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

vec3 hash33(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Value noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 3D noise
float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
            hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x),
        mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
            hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.x),
        f.y
    );
}

// FBM noise
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

vec4 getTriplanarColor(vec3 worldPos, vec3 normal) {
    vec3 blendWeights = abs(normal);
    // Tighten the blending to reduce blurring
    blendWeights = pow(blendWeights, vec3(4.0));
    blendWeights = blendWeights / (blendWeights.x + blendWeights.y + blendWeights.z);
    
    vec4 colorX = texture(diffuseTexture, worldPos.zy);
    vec4 colorY = texture(diffuseTexture, worldPos.xz);
    vec4 colorZ = texture(diffuseTexture, worldPos.xy);
    
    return colorX * blendWeights.x + colorY * blendWeights.y + colorZ * blendWeights.z;
}

// Holographic effect - RGB split and scanlines
vec3 apply_holographic_color(vec3 color, vec2 uv, vec3 pos, float time, float intensity) {
    // Chromatic aberration
    float aberration = 0.003 * intensity;
    float r = color.r;
    float g = color.g;
    float b = color.b;
    
    // Scanlines
    float scanline = sin(pos.y * 100.0 + time * 10.0) * 0.1 * intensity;
    
    // Horizontal glitch lines
    float glitch = step(0.99, hash(vec2(floor(time * 20.0), floor(pos.y * 50.0))));
    scanline += glitch * 0.3 * intensity;
    
    // Rainbow hue shift based on position and time
    float hue_shift = sin(pos.y * 2.0 + time * 3.0) * 0.5 + 0.5;
    vec3 rainbow = vec3(
        sin(hue_shift * 6.28) * 0.5 + 0.5,
        sin(hue_shift * 6.28 + 2.09) * 0.5 + 0.5,
        sin(hue_shift * 6.28 + 4.18) * 0.5 + 0.5
    );
    
    color = mix(color, color * rainbow, intensity * 0.4);
    color += scanline;
    
    // Flicker
    color *= 0.95 + 0.05 * sin(time * 30.0);
    
    return color;
}

// Glitch effect - RGB split and block distortion
vec3 apply_glitch_color(vec3 color, vec2 uv, vec3 pos, float time, float intensity) {
    float t = time * 10.0;
    
    // RGB split
    float split = 0.01 * intensity;
    vec2 r_offset = vec2(sin(t * 1.1) * split, cos(t * 1.3) * split);
    vec2 b_offset = vec2(sin(t * 0.9) * split, cos(t * 1.7) * split);
    
    // Block glitch
    float block_noise = step(0.97, hash(vec2(floor(t), floor(pos.y * 10.0))));
    if (block_noise > 0.0) {
        color.rgb = color.bgr; // Swap channels
    }
    
    // Scanline distortion
    float scan = sin(pos.y * 50.0 + t) * 0.05 * intensity;
    color += scan;
    
    // Random color boost
    color.r += sin(t * 123.0) * 0.1 * intensity;
    color.b += cos(t * 78.0) * 0.1 * intensity;
    
    return color;
}

// Pulse effect - energy waves
vec3 apply_pulse_color(vec3 color, vec3 pos, float time, float intensity) {
    float dist = length(pos);
    float pulse = sin(dist * 5.0 - time * 8.0) * 0.5 + 0.5;
    pulse *= intensity;
    
    // Energy ring
    vec3 pulse_color = vec3(0.3, 0.5, 1.0) * pulse * 0.5;
    color += pulse_color;
    
    // Core glow
    float core = exp(-dist * 0.5) * sin(time * 3.0) * 0.5 + 0.5;
    color += vec3(1.0, 0.8, 0.5) * core * intensity * 0.3;
    
    return color;
}

// Vortex effect - spiral energy
vec3 apply_vortex_color(vec3 color, vec3 pos, float time, float intensity) {
    float angle = atan(pos.z, pos.x);
    float radius = length(pos.xz);
    float spiral = sin(angle * 3.0 + radius * 5.0 - time * 4.0) * 0.5 + 0.5;
    
    vec3 vortex_color = vec3(0.5, 0.2, 1.0) * spiral * intensity * 0.4;
    color += vortex_color;
    
    // Swirl highlight
    float swirl = sin(angle * 5.0 - time * 2.0) * 0.5 + 0.5;
    color += vec3(0.8, 0.4, 1.0) * swirl * intensity * 0.2;
    
    return color;
}

// Wave effect - energy ripples
vec3 apply_wave_color(vec3 color, vec3 pos, float time, float intensity) {
    float wave1 = sin(pos.y * 3.0 + time * 2.0) * 0.5 + 0.5;
    float wave2 = sin(pos.x * 2.0 + time * 1.5) * 0.5 + 0.5;
    float wave3 = sin(pos.z * 4.0 + time * 2.5) * 0.5 + 0.5;
    
    float combined = (wave1 + wave2 + wave3) / 3.0;
    
    vec3 wave_color = vec3(0.2, 0.6, 1.0) * combined * intensity * 0.4;
    color += wave_color;
    
    return color;
}

// Jello effect - subsurface scatter look
vec3 apply_jello_color(vec3 color, vec3 pos, vec3 normal, float time, float intensity) {
    float subsurface = max(0.0, dot(normal, vec3(0.0, 1.0, 0.0))) * 0.5 + 0.5;
    float wobble = sin(pos.y * 5.0 + time * 2.0) * 0.5 + 0.5;
    
    vec3 jello_color = mix(
        vec3(1.0, 0.3, 0.5),  // Pink
        vec3(0.3, 1.0, 0.5),  // Green
        subsurface * wobble
    );
    
    color = mix(color, color * jello_color, intensity * 0.4);
    color += vec3(1.0, 0.9, 0.95) * subsurface * intensity * 0.2;
    
    return color;
}

// Breath effect - organic glow
vec3 apply_breath_color(vec3 color, vec3 pos, float time, float intensity) {
    float breath = sin(time * 2.0) * 0.5 + 0.5;
    float pulse = sin(length(pos) * 8.0 - time * 4.0) * 0.5 + 0.5;
    
    vec3 breath_color = vec3(1.0, 0.5, 0.2) * breath * intensity * 0.3;
    breath_color += vec3(0.2, 0.5, 1.0) * pulse * intensity * 0.2;
    
    color += breath_color;
    return color;
}

void main() {
    vec4 diffuseColor;
    
    if (fragUniforms.useTriplanarMapping != 0u) {
        diffuseColor = getTriplanarColor(fragWorldPos, normalize(fragWorldNormal));
    } else {
        diffuseColor = texture(diffuseTexture, fragTexCoord);
    }
    
    // Alpha handling
    if (fragUniforms.alphaMode == 0u) { // OPAQUE
        diffuseColor.a = 1.0;
    } else if (fragUniforms.alphaMode == 1u) { // MASK
        if (diffuseColor.a < fragUniforms.alphaCutoff) {
            discard;
        }
        diffuseColor.a = 1.0; // Usually mask implies opaque surface where visible
    }
    // BLEND (2) - keep original alpha, no discard

    vec3 color = diffuseColor.rgb;
    
    // Apply fragment color effects
    float time = fragUniforms.time;
    float intensity = fragUniforms.effectIntensity;
    
    switch (fragUniforms.effectMode) {
        case EFFECT_HOLOGRAPHIC:
            color = apply_holographic_color(color, fragTexCoord, fragLocalPos, time, intensity);
            break;
        case EFFECT_GLITCH:
            color = apply_glitch_color(color, fragTexCoord, fragLocalPos, time, intensity);
            break;
        case EFFECT_PULSE:
            color = apply_pulse_color(color, fragLocalPos, time, intensity);
            break;
        case EFFECT_VORTEX:
            color = apply_vortex_color(color, fragLocalPos, time, intensity);
            break;
        case EFFECT_WAVE:
            color = apply_wave_color(color, fragLocalPos, time, intensity);
            break;
        case EFFECT_JELLO:
            color = apply_jello_color(color, fragLocalPos, normalize(fragLocalNormal), time, intensity);
            break;
        case EFFECT_BREATH:
            color = apply_breath_color(color, fragLocalPos, time, intensity);
            break;
        default:
            break;
    }

    if (fragUniforms.enableLighting == 0u) {
        outColor = vec4(color, diffuseColor.a);
        return;
    }
    
    vec3 normalMapSample = texture(normalTexture, fragTexCoord).rgb;
    vec3 tangentNormal = normalize(normalMapSample * 2.0 - vec3(1.0));
    
    vec3 N = normalize(fragWorldNormal);
    vec3 T = normalize(fragWorldTangent);
    vec3 B = normalize(fragWorldBitangent);
    
    vec3 perturbedNormal = normalize(
        tangentNormal.x * T +
        tangentNormal.y * B +
        tangentNormal.z * N
    );
    
    // Calculate both diffuse and ambient lighting
    float diffuseIntensity = max(dot(perturbedNormal, fragUniforms.lightDir), 0.0);
    float ambientIntensity = 0.5;
    float totalIntensity = diffuseIntensity + ambientIntensity;

    // Clamp to prevent over-brightening
    totalIntensity = min(totalIntensity, 1.0);

    vec3 finalColor = color * totalIntensity;

    // Calculate fog
    float dist = distance(fragWorldPos, fragUniforms.cameraPos);
    float fogFactor = clamp((dist - fragUniforms.fogStart) / (fragUniforms.fogEnd - fragUniforms.fogStart), 0.0, 1.0);
    finalColor = mix(finalColor, fragUniforms.fogColor, fogFactor);

    outColor = vec4(finalColor, diffuseColor.a);
}
