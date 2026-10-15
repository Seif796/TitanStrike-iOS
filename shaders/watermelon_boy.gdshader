shader_type spatial;
render_mode cull_disabled, depth_draw_always, diffuse_burley, specular_schlick_ggx;

// Watermelon Boy 3D Shader
// Strictly opaque (ALPHA = 1.0) with double-sided rendering to prevent any transparency or backface culling issues.
// Renders the model's baked vertex colors with customizable tint and emission.

uniform vec4 base_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_vertex_color = true;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 15.0) = 0.0;

void fragment() {
	vec3 col = base_tint.rgb;
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	ALBEDO = col;
	ALPHA = 1.0; // 100% OPAQUE - Never transparent!
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission_color.rgb * emission_energy;
}
