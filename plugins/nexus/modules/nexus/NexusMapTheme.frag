#version 440
// Alis Auto-Theme Cartographic LUT Shader for Nexus Globe -> Detailed Map overlay.
// Remaps grayscale CartoDB Dark Matter (@2x) street/building/park/water/label tiles
// cleanly onto the live Alis palette (ccStop 0..13 + accent), supporting both dark
// and light themes automatically at zero CPU cost.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 colWater;  // ocean / lakes / deep water (ccStop 1)
    vec4 colLand;   // landmass / terrain (ccStop 3)
    vec4 colUrban;  // parks / urban footprints / buildings (ccStop 5)
    vec4 colRoad;   // local streets / boundaries (ccStop 7)
    vec4 colMajor;  // highways / arterials / rivers (ccStop 9-10 + accent)
    vec4 colLabel;  // street, district & city labels (ccStop 13)
    vec4 params;    // x = themeMix (1 = themed, 0 = raw color), y = reserved, z = reserved, w = reserved
};

layout(binding = 1) uniform sampler2D source;

vec3 unpremul(vec4 c) {
    return c.a > 0.0001 ? clamp(c.rgb / c.a, 0.0, 1.0) : vec3(0.0);
}

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    float alpha = tex.a;
    if (alpha <= 0.0001) {
        fragColor = vec4(0.0);
        return;
    }

    vec3 rgb = clamp(tex.rgb / alpha, 0.0, 1.0);
    float themeMix = clamp(params.x, 0.0, 1.0);
    if (themeMix <= 0.001) {
        fragColor = vec4(rgb * alpha, alpha) * qt_Opacity;
        return;
    }

    vec3 water = unpremul(colWater);
    vec3 land  = unpremul(colLand);
    vec3 urban = unpremul(colUrban);
    vec3 road  = unpremul(colRoad);
    vec3 major = unpremul(colMajor);
    vec3 label = unpremul(colLabel);

    // CartoDB dark_all luminance bands:
    //   ~0.03-0.06  water/ocean
    //   ~0.08-0.13  land/terrain
    //   ~0.14-0.22  parks, urban areas, building footprints
    //   ~0.23-0.38  minor streets, local roads, boundaries
    //   ~0.39-0.60  primary roads, highways, waterways
    //   ~0.61-1.00  street names, district & city labels
    float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 mapped;
    if (lum < 0.085) {
        mapped = mix(water, land, smoothstep(0.035, 0.085, lum));
    } else if (lum < 0.175) {
        mapped = mix(land, urban, smoothstep(0.085, 0.175, lum));
    } else if (lum < 0.34) {
        mapped = mix(urban, road, smoothstep(0.175, 0.34, lum));
    } else if (lum < 0.56) {
        mapped = mix(road, major, smoothstep(0.34, 0.56, lum));
    } else {
        mapped = mix(major, label, smoothstep(0.56, 0.86, lum));
    }

    vec3 finalRgb = mix(rgb, mapped, themeMix);
    fragColor = vec4(clamp(finalRgb, 0.0, 1.0) * alpha, alpha) * qt_Opacity;
}
