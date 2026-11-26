shader_type spatial;
// A planet (SpaceRun.gd). Synty paints its planets with a custom shader that
// glTF cannot carry, so this rebuilds the look from the pack's two masks: the
// land mask picks between a sea and a ground colour, the cloud mask lays white
// over both, and a rim glow stands in for an atmosphere. Each planet gets its
// own pair of colours, so six meshes make many different worlds.
//
// The debris of a smashed planet wears this too, with the colours swapped, so
// the pieces look like they came out of that planet.

uniform sampler2D land_mask : hint_default_white, filter_linear_mipmap;
uniform sampler2D cloud_mask : hint_default_black, filter_linear_mipmap;
uniform vec3 sea : source_color = vec3(0.1, 0.35, 0.85);
uniform vec3 ground : source_color = vec3(0.25, 0.7, 0.3);
uniform float cloud_amount = 0.5;
uniform vec3 rim_color : source_color = vec3(0.55, 0.75, 1.0);
uniform float rim_strength = 0.7;
// 0..1: a wrong planet flashes red when the ship hits it.
uniform float hit_flash = 0.0;

void fragment() {
	float land = texture(land_mask, UV).r;
	vec3 c = mix(sea, ground, land);
	c = mix(c, vec3(1.0), texture(cloud_mask, UV).r * cloud_amount);
	c = mix(c, vec3(1.0, 0.18, 0.12), hit_flash);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color * fres * rim_strength + vec3(1.0, 0.2, 0.1) * hit_flash * 0.6;
}
