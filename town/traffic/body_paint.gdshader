shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 lacquer : source_color;

void fragment(){
	vec3 base = texture(atlas, UV).rgb;
	// The original body swatch is #4566a9. Chrome, plates and trim use neutral swatches.
	float mask = smoothstep(.06,.22,(base.b-base.g)/max(base.b,.001)) *
		smoothstep(.14,.36,(base.b-base.r)/max(base.b,.001));
	float shade = clamp(base.b/(OUTPUT_IS_SRGB ? .663 : .397), .18, 1.5);
	ALBEDO = mix(base,lacquer.rgb*shade,mask);
	METALLIC = mask*.18;
	ROUGHNESS = mix(.76,.37,mask);
}
