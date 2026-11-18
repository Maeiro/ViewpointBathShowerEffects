#version 330

in vec2 vUv;
out vec4 fragColor;
uniform sampler2D uColor;
uniform sampler2D uDepth;
uniform mat4 uInvViewProjection;
uniform vec3 uEye;
uniform vec3 uSceneOrigin;
uniform float uAddon_maeiro_bath_shower_effects_clock;
uniform int uAddon_maeiro_bath_shower_effects_count;
uniform vec4 uAddon_maeiro_bath_shower_effects_position0;
uniform vec4 uAddon_maeiro_bath_shower_effects_position1;
uniform vec4 uAddon_maeiro_bath_shower_effects_position2;
uniform vec4 uAddon_maeiro_bath_shower_effects_position3;
uniform vec4 uAddon_maeiro_bath_shower_effects_effect0;
uniform vec4 uAddon_maeiro_bath_shower_effects_effect1;
uniform vec4 uAddon_maeiro_bath_shower_effects_effect2;
uniform vec4 uAddon_maeiro_bath_shower_effects_effect3;
uniform vec4 uAddon_maeiro_bath_shower_effects_tub0;
uniform vec4 uAddon_maeiro_bath_shower_effects_tub1;
uniform vec4 uAddon_maeiro_bath_shower_effects_tub2;
uniform vec4 uAddon_maeiro_bath_shower_effects_tub3;
uniform vec4 uAddon_maeiro_bath_shower_effects_color0;
uniform vec4 uAddon_maeiro_bath_shower_effects_color1;
uniform vec4 uAddon_maeiro_bath_shower_effects_color2;
uniform vec4 uAddon_maeiro_bath_shower_effects_color3;

#ifndef OPTION_BATH_WATER
#define OPTION_BATH_WATER 1
#endif
#ifndef OPTION_BATH_STEAM
#define OPTION_BATH_STEAM 1
#endif
#ifndef OPTION_BATH_WATER_STRENGTH
#define OPTION_BATH_WATER_STRENGTH 1.0
#endif
#ifndef OPTION_BATH_STEAM_STRENGTH
#define OPTION_BATH_STEAM_STRENGTH 1.0
#endif
#ifndef OPTION_BATH_QUALITY
#define OPTION_BATH_QUALITY 1
#endif
#ifndef OPTION_BATH_HEIGHT
#define OPTION_BATH_HEIGHT 1.9
#endif
#ifndef OPTION_BATH_TUB_HEIGHT
#define OPTION_BATH_TUB_HEIGHT 0.52
#endif
#ifndef OPTION_BATH_TUB_DEPTH
#define OPTION_BATH_TUB_DEPTH 0.34
#endif

const int JETS = 6 + OPTION_BATH_QUALITY * 4;
const int STEPS = 8 + OPTION_BATH_QUALITY * 4;
const float PI = 3.14159265;

vec3 scenePosition(float depth) {
    vec4 position = uInvViewProjection * vec4(vUv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    return position.xyz / position.w;
}

float hash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
                   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
                   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

bool intersectBox(vec3 origin, vec3 direction, vec3 lower, vec3 upper, float stop,
        out float nearPoint, out float farPoint) {
    vec3 safe = mix(vec3(-0.000001), vec3(0.000001), greaterThanEqual(direction, vec3(0.0)));
    vec3 inverseDirection = 1.0 / mix(safe, direction, greaterThan(abs(direction), vec3(0.000001)));
    vec3 a = (lower - origin) * inverseDirection, b = (upper - origin) * inverseDirection;
    vec3 low = min(a, b), high = max(a, b);
    nearPoint = max(0.0, max(low.x, max(low.y, low.z)));
    farPoint = min(stop, min(high.x, min(high.y, high.z)));
    return farPoint > nearPoint;
}

float jet(vec3 origin, vec3 direction, float stop, vec3 top, vec3 bottom, float seed) {
    vec3 segment = bottom - top, offset = origin - top;
    float lengthSquared = dot(segment, segment);
    float alignment = dot(direction, segment);
    float projection = dot(segment, offset);
    float denominator = max(lengthSquared - alignment * alignment, 0.00001);
    float rayT = clamp((alignment * projection - lengthSquared * dot(direction, offset)) / denominator, 0.0, stop);
    float segmentT = clamp((projection + rayT * alignment) / lengthSquared, 0.0, 1.0);
    rayT = clamp(dot(top + segment * segmentT - origin, direction), 0.0, stop);
    vec3 point = origin + rayT * direction;
    float distanceToJet = length(point - (top + segment * segmentT));
    float radius = mix(0.006, 0.011, segmentT);
    float edge = max(fwidth(distanceToJet), 0.002);
    float coverage = 1.0 - smoothstep(radius, radius + edge, distanceToJet);
    float phase = fract(segmentT * 12.0 - uAddon_maeiro_bath_shower_effects_clock * 5.0 + seed);
    float drops = 0.12 + 0.88 * (1.0 - smoothstep(0.10, 0.34, phase));
    float softEnds = smoothstep(0.0, 0.02, segmentT) * (1.0 - smoothstep(0.96, 1.0, segmentT));
    return coverage * drops * softEnds;
}

vec4 shower(vec4 location, vec4 effect, vec3 direction, float stop) {
    // Scene axes are west/up/north; TABAS coordinates are east/south/storeys.
    vec3 center = vec3(-location.x, location.z * sqrt(6.0), -location.y) - uSceneOrigin;
    vec2 inward = location.w < 0.5 ? vec2(0, -1) : location.w < 1.5 ? vec2(1, 0)
        : location.w < 2.5 ? vec2(0, 1) : vec2(-1, 0);
    vec3 top = center + vec3(-inward.x * 0.30, float(OPTION_BATH_HEIGHT), -inward.y * 0.30);
    vec3 fogCenter = center + vec3(-inward.x * 0.08, 1.05, -inward.y * 0.08);
    float nearPoint, farPoint;
    if (!intersectBox(uEye, direction, center + vec3(-0.70, 0.02, -0.70),
            center + vec3(0.70, float(OPTION_BATH_HEIGHT) + 0.55, 0.70), stop, nearPoint, farPoint)) return vec4(0.0);
    float brightness = mix(0.08, 1.0, effect.z);
    float water = 0.0;
#if OPTION_BATH_WATER
    if (effect.x > 0.0) {
        for (int i = 0; i < JETS; i++) {
            float seed = float(i) * 0.6180339;
            float angle = float(i) * 2.3999632;
            vec2 radial = vec2(cos(angle), sin(angle));
            vec3 start = top + vec3(radial.x, 0, radial.y) * 0.055;
            vec3 end = center + vec3(radial.x * 0.28, 0.04, radial.y * 0.28)
                + vec3(inward.x, 0, inward.y) * 0.08;
            water += jet(uEye, direction, stop, start, end, seed);
        }
    }
#endif
    float steam = 0.0;
#if OPTION_BATH_STEAM
    if (effect.y > 0.001) {
        float stepLength = (farPoint - nearPoint) / float(STEPS);
        for (int i = 0; i < STEPS; i++) {
            vec3 point = uEye + direction * (nearPoint + (float(i) + 0.5) * stepLength);
            vec3 local = (point - fogCenter) / vec3(0.62, 1.15, 0.62);
            float shape = max(0.0, 1.0 - dot(local, local));
            float fade = smoothstep(0.03, 0.22, point.y - center.y);
            vec3 drift = (point - center) * 4.0 - vec3(0.12, 0.45, -0.08) * uAddon_maeiro_bath_shower_effects_clock;
            steam += shape * shape * fade * (0.35 + 0.65 * noise(drift)) * stepLength;
        }
    }
#endif
    float waterAlpha = clamp(water * 0.52 * effect.x * float(OPTION_BATH_WATER_STRENGTH), 0.0, 0.80);
    float steamAlpha = 1.0 - exp(-steam * effect.y * 0.72 * float(OPTION_BATH_STEAM_STRENGTH));
    vec3 steamColor = vec3(0.64, 0.68, 0.70) * brightness;
    vec3 waterColor = vec3(0.65, 0.79, 0.86) * brightness;
    float alpha = waterAlpha + steamAlpha * (1.0 - waterAlpha);
    vec3 color = waterColor * waterAlpha + steamColor * steamAlpha * (1.0 - waterAlpha);
    return vec4(color, alpha);
}

vec4 bathtub(vec4 location, vec4 effect, vec4 tub, vec4 tint, vec3 direction, float stop) {
    vec3 center = vec3(-location.x, location.z * sqrt(6.0), -location.y) - uSceneOrigin;
    vec2 forward = location.w < 0.5 ? vec2(0, -1) : location.w < 1.5 ? vec2(1, 0)
        : location.w < 2.5 ? vec2(0, 1) : vec2(-1, 0);
    vec2 across = vec2(-forward.y, forward.x);
    bool eastWest = abs(forward.x) > 0.5;
    vec2 extent = eastWest ? vec2(0.92, 0.42) : vec2(0.42, 0.92);
    float height = float(OPTION_BATH_TUB_HEIGHT) - float(OPTION_BATH_TUB_DEPTH) * (1.0 - effect.x);
    float nearPoint, farPoint;
    if (!intersectBox(uEye, direction, center + vec3(-extent.x, 0.02, -extent.y),
            center + vec3(extent.x, height + 1.2, extent.y), stop, nearPoint, farPoint)) return vec4(0.0);
    float brightness = mix(0.08, 1.0, effect.z);
    float waterAlpha = 0.0;
    vec3 waterColor = vec3(0.0);
#if OPTION_BATH_WATER
    if (effect.x > 0.0 && abs(direction.y) > 0.00001) {
        float distance = (center.y + height - uEye.y) / direction.y;
        vec3 point = uEye + direction * distance;
        vec2 delta = point.xz - center.xz;
        vec2 local = vec2(dot(delta, across), dot(delta, forward));
        vec2 halfSize = vec2(0.34, 0.84) * mix(0.78, 1.0, effect.x);
        float radius = 0.20;
        vec2 edge = abs(local) - halfSize + radius;
        float boundary = length(max(edge, 0.0)) + min(max(edge.x, edge.y), 0.0) - radius;
        float coverage = 1.0 - smoothstep(-max(fwidth(boundary), 0.001), 0.0, boundary);
        if (distance > 0.0 && distance < stop) {
            float clock = uAddon_maeiro_bath_shower_effects_clock;
            float ripple = sin(local.x * 30.0 + clock * 1.8) * sin(local.y * 24.0 - clock * 1.2);
            float fresnel = pow(1.0 - abs(direction.y), 3.0);
            waterColor = mix(vec3(0.30, 0.64, 0.73), vec3(0.35, 0.32, 0.21), tub.y);
            if (tint.w > 0.5) waterColor = tint.rgb;
            waterColor = (waterColor + vec3(0.035 * ripple + fresnel * 0.12)) * brightness;
            waterAlpha = coverage * smoothstep(0.0, 0.02, effect.x)
                * clamp((0.48 + fresnel * 0.25) * float(OPTION_BATH_WATER_STRENGTH), 0.0, 0.90);
        }
    }
    if (tub.x > 0.0) {
        vec3 spout = center - vec3(forward.x, 0, forward.y) * 0.65 + vec3(0, max(0.76, height + 0.10), 0);
        vec3 landing = spout; landing.y = center.y + height;
        float stream = jet(uEye, direction, stop, spout, landing, 0.0);
        float streamAlpha = clamp(stream * 0.65 * float(OPTION_BATH_WATER_STRENGTH), 0.0, 0.8);
        waterColor = (waterColor * waterAlpha * (1.0 - streamAlpha)
            + vec3(0.65, 0.79, 0.86) * brightness * streamAlpha) / max(0.0001, waterAlpha + streamAlpha * (1.0 - waterAlpha));
        waterAlpha += streamAlpha * (1.0 - waterAlpha);
    }
#endif
    float steam = 0.0;
#if OPTION_BATH_STEAM
    if (effect.y > 0.001) {
        float stepLength = (farPoint - nearPoint) / float(STEPS);
        for (int i = 0; i < STEPS; i++) {
            vec3 point = uEye + direction * (nearPoint + (float(i) + 0.5) * stepLength);
            vec3 delta = point - center;
            vec3 local = vec3(dot(delta.xz, across) / 0.40, (delta.y - height - 0.38) / 0.65,
                dot(delta.xz, forward) / 0.90);
            float shape = max(0.0, 1.0 - dot(local, local));
            float fade = smoothstep(height, height + 0.12, delta.y);
            vec3 drift = delta * 4.5 - vec3(0.10, 0.32, -0.06) * uAddon_maeiro_bath_shower_effects_clock;
            steam += shape * shape * fade * (0.35 + 0.65 * noise(drift)) * stepLength;
        }
    }
#endif
    float steamAlpha = 1.0 - exp(-steam * effect.y * 1.25 * float(OPTION_BATH_STEAM_STRENGTH));
    float alpha = waterAlpha + steamAlpha * (1.0 - waterAlpha);
    vec3 color = waterColor * waterAlpha + vec3(0.70, 0.73, 0.75) * brightness * steamAlpha * (1.0 - waterAlpha);
    return vec4(color, alpha);
}

void main() {
    vec4 source = texture(uColor, vUv);
    if (uAddon_maeiro_bath_shower_effects_count <= 0) { fragColor = source; return; }
    vec3 target = scenePosition(texture(uDepth, vUv).r);
    vec3 ray = target - uEye;
    float stop = length(ray);
    if (stop < 0.0001) { fragColor = source; return; }
    vec3 direction = ray / stop;
    vec4 locations[4] = vec4[4](uAddon_maeiro_bath_shower_effects_position0, uAddon_maeiro_bath_shower_effects_position1,
        uAddon_maeiro_bath_shower_effects_position2, uAddon_maeiro_bath_shower_effects_position3);
    vec4 effects[4] = vec4[4](uAddon_maeiro_bath_shower_effects_effect0, uAddon_maeiro_bath_shower_effects_effect1,
        uAddon_maeiro_bath_shower_effects_effect2, uAddon_maeiro_bath_shower_effects_effect3);
    vec4 tubs[4] = vec4[4](uAddon_maeiro_bath_shower_effects_tub0, uAddon_maeiro_bath_shower_effects_tub1,
        uAddon_maeiro_bath_shower_effects_tub2, uAddon_maeiro_bath_shower_effects_tub3);
    vec4 tints[4] = vec4[4](uAddon_maeiro_bath_shower_effects_color0, uAddon_maeiro_bath_shower_effects_color1,
        uAddon_maeiro_bath_shower_effects_color2, uAddon_maeiro_bath_shower_effects_color3);
    vec3 color = source.rgb;
    for (int i = 0; i < min(uAddon_maeiro_bath_shower_effects_count, 4); i++) {
        vec4 layer = effects[i].w > 0.5
            ? bathtub(locations[i], effects[i], tubs[i], tints[i], direction, max(0.0, stop - 0.01))
            : shower(locations[i], effects[i], direction, max(0.0, stop - 0.01));
        color = color * (1.0 - layer.a) + layer.rgb;
    }
    fragColor = vec4(color, source.a);
}
