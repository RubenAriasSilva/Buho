shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_front, unshaded;

uniform vec4 albedo : source_color;
uniform float grow : hint_range(-16.0, 16.0, 0.001);

void vertex(){
	VERTEX += NORMAL + grow;
}

void fragment(){
	ALBEDO = albedo.rgb;
}