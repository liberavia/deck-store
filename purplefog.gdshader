// Shader für wabernden Nebel (Godot 4.x) - Dezenter mit mehr Kontrast
shader_type canvas_item;

// Konfigurierbare Parameter
uniform vec4 fog_color : source_color = vec4(0.627, 0.125, 0.941, 1.0); // #a020f0
uniform float speed : hint_range(0.0, 1.0) = 0.05;
uniform float scale : hint_range(1.0, 20.0) = 8.0; // Noch etwas größer für weniger feine Schwaden
uniform float brightness : hint_range(0.0, 1.0) = 0.25; // Evtl. leicht erhöhen, da pow() abdunkelt
uniform int octaves : hint_range(1, 8) = 3;          // Reduziert für einfachere Muster
// NEU: Kontraststeuerung
uniform float contrast_power : hint_range(1.0, 5.0) = 2.0; // Werte > 1 erhöhen Kontrast

// Funktion für 2D-Zufallszahlen
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Noise-Funktion (Value Noise)
float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Fraktales Brownian Motion (FBM)
float fbm(vec2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Fragment-Shader
void fragment() {
    vec2 scaled_uv = SCREEN_UV * scale;

    // Animation
    vec2 motion = vec2(TIME * speed, TIME * speed * 0.7);
    float noise_value = fbm(scaled_uv + motion);
    vec2 motion2 = vec2(-TIME * speed * 0.5, TIME * speed * 1.1);
    float noise_value2 = fbm(scaled_uv * 1.5 + motion2);

    // Kombinieren
    float final_noise = (noise_value + noise_value2) * 0.5;

    // NEU: Kontrastanpassung
    // Wende die Potenzfunktion an. Höhere Werte für contrast_power erhöhen den Kontrast.
    final_noise = pow(final_noise, contrast_power);

    // Additiver Nebel über dem dunklen Hintergrund des ColorRect
    // Multipliziere mit brightness, um die Gesamtintensität zu steuern.
    COLOR = COLOR + fog_color * final_noise * brightness;
    COLOR.a = 1.0; // Stelle sicher, dass der Hintergrund voll deckend ist
}