#version 450

// Push constants for frequently updated per-draw data
layout(push_constant) uniform PushConstants {
    mat4 mvp;
    mat4 model;
    float time;
    uint effectMode;
    float effectIntensity;
    float effectSpeed;
} pushConstants;

// Uniform buffer for bone animation data (less frequently updated)
layout(set = 0, binding = 0) uniform Uniforms {
    mat4 boneMatrices[200];
    uint hasAnimation;
} uniforms;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec3 inTangent;
layout(location = 4) in vec3 inBitangent;
layout(location = 5) in ivec4 inBoneIDs;
layout(location = 6) in vec4 inBoneWeights;

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out vec3 fragWorldNormal;
layout(location = 2) out vec3 fragWorldTangent;
layout(location = 3) out vec3 fragWorldBitangent;
layout(location = 4) out vec3 fragWorldPos;
layout(location = 5) out vec3 fragLocalPos;
layout(location = 6) out vec3 fragLocalNormal;

// Effect modes
const uint EFFECT_NONE = 0u;
const uint EFFECT_WAVE = 1u;
const uint EFFECT_GLITCH = 2u;
const uint EFFECT_HOLOGRAPHIC = 3u;
const uint EFFECT_PULSE = 4u;
const uint EFFECT_VORTEX = 5u;
const uint EFFECT_BREATH = 6u;
const uint EFFECT_JELLO = 7u;

// Simplex noise for vertex displacement
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x*34.0)+1.0)*x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
    const vec2 C = vec2(1.0/6.0, 1.0/3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
    vec3 i  = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;
    i = mod289(i);
    vec4 p = permute(permute(permute(
        i.z + vec4(0.0, i1.z, i2.z, 1.0))
        + i.y + vec4(0.0, i1.y, i2.y, 1.0))
        + i.x + vec4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;
    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x = x_ *ns.x + ns.yyyy;
    vec4 y = y_ *ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0)*2.0 + 1.0;
    vec4 s1 = floor(b1)*2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww;
    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);
    vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;
    vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

vec3 apply_wave_effect(vec3 pos, vec3 normal, float time, float intensity, float speed) {
    float wave = sin(pos.y * 3.0 + time * speed) * intensity;
    wave += sin(pos.x * 2.0 + time * speed * 0.7) * intensity * 0.5;
    wave += sin(pos.z * 4.0 + time * speed * 1.3) * intensity * 0.3;
    return pos + normal * wave * 0.1;
}

vec3 apply_glitch_effect(vec3 pos, float time, float intensity, float speed) {
    float t = time * speed;
    float glitch = step(0.98, sin(t * 50.0)) * intensity;
    vec3 offset = vec3(
        sin(t * 123.456) * glitch,
        cos(t * 789.012) * glitch,
        sin(t * 345.678) * glitch
    );
    // Random vertex displacement based on position hash
    float hash = fract(sin(dot(pos.xz, vec2(12.9898, 78.233))) * 43758.5453);
    if (hash > 0.95) {
        offset += vec3(
            sin(t * 100.0) * intensity * 0.2,
            cos(t * 80.0) * intensity * 0.2,
            sin(t * 120.0) * intensity * 0.2
        );
    }
    return pos + offset * 0.15;
}

vec3 apply_vortex_effect(vec3 pos, float time, float intensity, float speed) {
    float t = time * speed;
    float angle = t + length(pos.xz) * 2.0;
    float radius = length(pos.xz);
    float twist = sin(pos.y * 2.0 + t) * intensity;
    float c = cos(twist * 0.2);
    float s = sin(twist * 0.2);
    return vec3(
        pos.x * c - pos.z * s,
        pos.y + sin(radius * 3.0 + t) * intensity * 0.05,
        pos.x * s + pos.z * c
    );
}

vec3 apply_breath_effect(vec3 pos, vec3 normal, float time, float intensity, float speed) {
    float breath = sin(time * speed) * 0.5 + 0.5;
    float scale = 1.0 + breath * intensity * 0.1;
    return pos * scale;
}

vec3 apply_jello_effect(vec3 pos, vec3 normal, float time, float intensity, float speed) {
    float t = time * speed;
    float wobble = sin(pos.y * 5.0 + t * 2.0) * cos(pos.x * 3.0 + t * 1.5);
    wobble += sin(pos.z * 4.0 + t * 1.8) * 0.5;
    return pos + normal * wobble * intensity * 0.08;
}

vec3 apply_pulse_effect(vec3 pos, vec3 normal, float time, float intensity, float speed) {
    float pulse = sin(time * speed * 5.0) * 0.5 + 0.5;
    return pos + normal * pulse * intensity * 0.05;
}

vec3 apply_holographic_wobble(vec3 pos, vec3 normal, float time, float intensity, float speed) {
    float wobble = sin(pos.y * 10.0 + time * speed * 3.0) * intensity * 0.02;
    wobble += sin(pos.x * 8.0 - time * speed * 2.0) * intensity * 0.01;
    return pos + normal * wobble;
}

void main() {
    vec4 localPosition;
    vec3 localNormal;
    vec3 localTangent;
    vec3 localBitangent;

    if (uniforms.hasAnimation == 1u) {
        // GPU skinning
        mat4 boneTransform = mat4(0.0);
        for (int i = 0; i < 4; i++) {
            if (inBoneIDs[i] >= 0) {
                boneTransform += uniforms.boneMatrices[inBoneIDs[i]] * inBoneWeights[i];
            }
        }

        localPosition = boneTransform * vec4(inPosition, 1.0);
        localNormal = mat3(boneTransform) * inNormal;
        localTangent = mat3(boneTransform) * inTangent;
        localBitangent = mat3(boneTransform) * inBitangent;
    } else {
        // Static model
        localPosition = vec4(inPosition, 1.0);
        localNormal = inNormal;
        localTangent = inTangent;
        localBitangent = inBitangent;
    }

    vec3 pos = localPosition.xyz;
    vec3 norm = normalize(localNormal);
    float time = pushConstants.time;
    float intensity = pushConstants.effectIntensity;
    float speed = pushConstants.effectSpeed;

    // Apply procedural effects
    switch (pushConstants.effectMode) {
        case EFFECT_WAVE:
            pos = apply_wave_effect(pos, norm, time, intensity, speed);
            break;
        case EFFECT_GLITCH:
            pos = apply_glitch_effect(pos, time, intensity, speed);
            break;
        case EFFECT_HOLOGRAPHIC:
            pos = apply_holographic_wobble(pos, norm, time, intensity, speed);
            break;
        case EFFECT_PULSE:
            pos = apply_pulse_effect(pos, norm, time, intensity, speed);
            break;
        case EFFECT_VORTEX:
            pos = apply_vortex_effect(pos, time, intensity, speed);
            break;
        case EFFECT_BREATH:
            pos = apply_breath_effect(pos, norm, time, intensity, speed);
            break;
        case EFFECT_JELLO:
            pos = apply_jello_effect(pos, norm, time, intensity, speed);
            break;
        default:
            break;
    }

    localPosition = vec4(pos, 1.0);

    gl_Position = pushConstants.mvp * localPosition;
    fragTexCoord = inTexCoord;
    fragWorldNormal = (pushConstants.model * vec4(localNormal, 0.0)).xyz;
    fragWorldTangent = (pushConstants.model * vec4(localTangent, 0.0)).xyz;
    fragWorldBitangent = (pushConstants.model * vec4(localBitangent, 0.0)).xyz;
    fragWorldPos = (pushConstants.model * localPosition).xyz;
    fragLocalPos = pos;
    fragLocalNormal = localNormal;
}
