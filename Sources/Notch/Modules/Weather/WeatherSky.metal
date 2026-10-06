#include <metal_stdlib>
using namespace metal;

// Небо модуля погоды: градиент, солнце с засветкой и облака из шума.
//
// Облака — не круги, а плотность: фрактальный шум, искажённый другим
// шумом (так получаются рваные края и завихрения), срезанный по порогу
// покрытия. Объём даёт свет: плотность сравнивается с плотностью чуть
// ближе к солнцу — где к солнцу облако тоньше, там оно светлее.

static float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + float2(1, 0));
    float c = hash(i + float2(0, 1));
    float d = hash(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    // Поворот между октавами прячет сетку шума: без него видны
    // горизонтальные и вертикальные полосы.
    const float2x2 rotate = float2x2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p);
        p = rotate * p * 2.03 + 17.1;
        amplitude *= 0.5;
    }
    return value;
}

// Плотность облаков в точке. `stretch` вытягивает шум вдоль ветра —
// перистые облака (большое значение) против кучевых (единица).
static float density(float2 p, float t, float stretch, float cover) {
    // Облако шире, чем выше: по горизонтали шум растянут всегда, а у
    // перистых — ещё и сжат по вертикали в тонкие пряди.
    float2 q = float2(p.x / (stretch * 1.3), p.y * stretch * 1.6);
    q.x += t * 0.018;
    float2 warp = float2(fbm(q * 0.9 + float2(0.0, t * 0.01)),
                         fbm(q * 0.9 + float2(5.2, 1.3) - t * 0.008));
    float n = fbm(q + warp * 0.75);
    float edge = 1.0 - cover;
    return smoothstep(edge, edge + 0.45, n);
}

// Мягкое пятно света: блик объектива и призраки от солнца.
static float spot(float d, float radius) {
    return exp(-d * d / (radius * radius));
}

[[ stitchable ]] half4 weatherSky(
    float2 position,
    half4 color,
    float2 size,
    float time,
    half4 skyTop,
    half4 skyBottom,
    half4 horizon,
    half4 cloudTint,
    float cover,
    float darkness,
    float stretch,
    float2 sun,
    float sunStrength,
    float sunWarm,
    float flash
) {
    float2 uv = position / size;
    // Координаты по высоте: облака и солнце не сплющиваются на широкой панели.
    float aspect = size.x / size.y;
    float2 p = position / size.y;
    float2 sunP = sun * float2(aspect, 1.0);

    // Небо: верх, низ и полоса у горизонта — на закате она оранжевая,
    // в сумерках розовая, днём почти не видна.
    float3 sky = mix(float3(skyTop.rgb), float3(skyBottom.rgb), smoothstep(0.0, 1.0, uv.y));
    sky = mix(sky, float3(horizon.rgb), float(horizon.a) * smoothstep(0.45, 1.05, uv.y));

    // Цвет солнца: белое днём, золотое низко над горизонтом.
    float3 sunTint = mix(float3(1.0, 0.96, 0.88), float3(1.0, 0.62, 0.3), sunWarm);

    float2 toSunVec = p - sunP;
    float d = length(toSunVec);
    float angle = atan2(toSunVec.y, toSunVec.x);

    // Засветка неба вокруг — мягкая, небо остаётся синим уже рядом.
    sky += sunTint * sunStrength * (0.32 * exp(-d * d * 5.0) + 0.3 * exp(-d * 14.0));

    // Облака.
    float2 cp = p * 1.7;
    float dens = density(cp, time, stretch, cover);
    float2 toSun = normalize(sunP - p + float2(0.0001, -0.3));
    float lit = density(cp + toSun * 0.09, time, stretch, cover);
    float shade = clamp(0.6 + (dens - lit) * 1.5, 0.0, 1.0);

    float3 bright = mix(float3(0.97, 0.97, 0.97), float3(0.48, 0.5, 0.56), darkness) * float3(cloudTint.rgb);
    float3 dark = mix(float3(0.6, 0.65, 0.74), float3(0.12, 0.13, 0.17), darkness);
    dark = mix(dark, dark * float3(cloudTint.rgb), 0.5);
    float3 cloud = mix(dark, bright, shade);
    // Край облака рядом с солнцем светится на просвет.
    cloud += sunTint * sunStrength * 0.7 * exp(-d * 4.0) * (1.0 - dens);
    cloud += float3(0.75, 0.72, 1.0) * flash * 0.6 * dens;

    float3 result = mix(sky, cloud, clamp(dens * 1.05, 0.0, 1.0));

    // Всё, что дальше, — свет самого солнца и то, что с ним делает
    // объектив. Облако перед солнцем гасит его, и эффекты гаснут вместе.
    float clear = 1.0 - clamp(dens * 1.3, 0.0, 1.0);
    float s = sunStrength * clear;

    // Диск: чёткий край, середина ярче края.
    float radius = 0.045;
    float diskMask = smoothstep(radius, radius * 0.82, d);
    float limb = 1.0 - 0.35 * pow(clamp(d / radius, 0.0, 1.0), 2.0);
    result = mix(result, sunTint * 1.25 * limb + 0.25, diskMask * s);

    // Дыхание всего свечения: две несоизмеримые частоты, чтобы ритм не
    // угадывался. Воздух между нами и солнцем неспокоен — яркость ореола
    // плывёт на несколько процентов.
    float breathe = 1.0 + 0.07 * sin(time * 0.63) + 0.04 * sin(time * 1.71 + 1.3);

    // Ореол сразу у диска.
    result += sunTint * s * 0.75 * breathe * exp(-max(d - radius, 0.0) * 22.0);

    // Лучи — рассеяние в оптике глаза и объектива. Физически они не
    // вращаются колесом, а мерцают: турбулентность воздуха (сцинтилляция)
    // зажигает и гасит отдельные лучи вразнобой, и их длина дышит.
    // Направление берём точкой на окружности, а не углом: у угла шов на
    // ±π, и там лучи обрывались бы. Поверх — едва заметный дрейф.
    float spin = angle + time * 0.012;
    float2 ring = float2(cos(spin), sin(spin));
    float coarse = noise(ring * 7.0 + float2(time * 0.45, -time * 0.3));
    float fine = noise(ring * 21.0 + float2(-time * 1.1, time * 0.8));
    float flicker = noise(ring * 4.0 + float2(time * 1.9, time * 1.4));
    float rays = pow(coarse, 3.0) * 1.1 + pow(fine, 5.0) * 0.9;
    rays *= 0.65 + 0.7 * flicker;
    float reach = 6.8 - 1.8 * coarse;
    result += sunTint * s * rays * 0.42 * breathe * exp(-d * reach) * smoothstep(radius * 0.9, radius * 1.6, d);

    // Шестилучевая звезда — дифракция на лепестках диафрагмы. Она
    // привязана к объективу и потому не вращается, только чуть мерцает
    // вместе с солнцем.
    float spikes = pow(abs(cos(angle * 3.0 + 0.3)), 260.0);
    result += float3(1.0) * s * spikes * 0.6 * (0.85 + 0.15 * flicker) * exp(-d * 6.5) * smoothstep(radius, radius * 1.4, d);

    // Горизонтальная вытянутая полоса блика.
    result += float3(0.75, 0.85, 1.0) * s * 0.28 * exp(-abs(toSunVec.y) * 70.0) * exp(-abs(toSunVec.x) * 3.2);

    // Гало в 22°: кольцо с радужной кромкой — красное внутри, синее снаружи.
    float haloR = 0.46;
    float w = 0.018;
    float3 halo = float3(spot(d - (haloR - 0.012), w), spot(d - haloR, w), spot(d - (haloR + 0.014), w));
    result += halo * s * 0.1 * (1.0 - sunWarm * 0.6);

    // Призраки объектива — на линии от солнца через центр кадра.
    float2 center = float2(aspect * 0.5, 0.5);
    float2 axis = center - sunP;
    result += float3(0.45, 1.0, 0.6) * s * 0.07 * spot(distance(p, sunP + axis * 0.7), 0.05);
    result += float3(1.0, 0.7, 0.4) * s * 0.1 * spot(distance(p, sunP + axis * 1.05), 0.025);
    result += float3(0.6, 0.55, 1.0) * s * 0.06 * spot(distance(p, sunP + axis * 1.4), 0.09);
    float ringD = distance(p, sunP + axis * 1.75);
    result += float3(0.5, 0.85, 1.0) * s * 0.07 * spot(ringD - 0.06, 0.012);

    result += float3(0.7, 0.7, 0.85) * flash * 0.12;
    return half4(half3(clamp(result, 0.0, 1.0)), 1.0) * color.a;
}
