// Peripheral vignette flash (M2 Iter 2 swap).
// Подсвечивает периферию экрана на kill, центр оставляет нетронутым.
// vignette_inner..vignette_outer: smoothstep mask по distance(UV, center).
//   inner=0.35 → mask=0 в радиусе ≤35% (центр чистый, aim не страдает)
//   outer=0.75 → mask=1 на углах
// flash_intensity (0..1) тween'ится из vignette_flash.gd: 0→0.4 за 50ms, 0.4→0 за 100ms.
// blend_add: additive — периферия светится поверх сцены без затемнения.
shader_type canvas_item;
render_mode blend_add;

uniform vec3 flash_color : source_color = vec3(0.85, 0.95, 1.0);
uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_inner : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_outer : hint_range(0.0, 1.0) = 0.75;

void fragment() {
	vec2 center = vec2(0.5);
	float dist = distance(UV, center);
	float mask = smoothstep(vignette_inner, vignette_outer, dist);
	float a = mask * flash_intensity;
	COLOR = vec4(flash_color * a, a);
}
