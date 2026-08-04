shader_type canvas_item;

// Frosts over whatever has already been drawn this frame rather than painting on
// top of it, so the dish stays readable behind the end screen.
//
// The blur is a mipmap trick: hint_screen_texture hands us the frame so far, and
// reading it back at a lower level of detail averages a wide area for the cost of
// one sample. filter_linear_mipmap is what makes the lod argument mean anything --
// without it every lookup snaps to the full-resolution image and nothing blurs.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 5.0) = 2.5;
/// Darkens the frosted image so white text stays legible over a bright dish.
uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.05, 0.45);

void fragment() {
	vec3 frosted = textureLod(screen_texture, SCREEN_UV, blur).rgb;
	COLOR = vec4(mix(frosted, tint.rgb, tint.a), 1.0);
}
