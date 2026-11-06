shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D studio : filter_linear, repeat_enable;
uniform float presence : hint_range(0.0, 1.0) = 1.0;
uniform float exposure : hint_range(0.0, 2.0) = 1.0;
varying vec3 local_point;
varying vec3 world_point;
varying vec3 wall_normal;

void vertex() {
	local_point = VERTEX;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wall_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 face = normalize(wall_normal);
	vec3 inset = 0.5 - abs(local_point);
	vec3 lateral = vec3(1.) - abs(face);
	vec3 edge_weight = exp(-max(inset,vec3(0.0)) * 300.0) * lateral;
	float bevel = max(edge_weight.x,max(edge_weight.y,edge_weight.z));
	vec3 n = normalize(face + sign(local_point) * edge_weight * .82);
	vec3 eye = normalize(CAMERA_POSITION_WORLD-world_point);
	float cosine = max(.015,abs(dot(eye,n)));
	float fresnel = .0426 + .9574 * pow(1.0-cosine,5.0); // IOR 1.52.
	vec3 reflected = reflect(-eye,n);
	// Parallax-correct a photographic environment at the walls of a studio.
	vec3 origin = (world_point-vec3(0.,41.4,0.)) / 165.0;
	vec3 wall = (sign(reflected)-origin) / (sign(reflected)*max(abs(reflected),vec3(.0001))+vec3(.00001));
	vec3 r = normalize(origin + min(wall.x,min(wall.y,wall.z))*reflected);
	vec2 pano = vec2(atan(r.z,r.x)/TAU+.72,acos(clamp(r.y,-1.,1.))/PI);
	vec3 radiance = texture(studio,pano).rgb * exposure;
	vec3 view_n = (VIEW_MATRIX * vec4(n,0.)).xyz;
	vec3 transmitted_dir = refract(-VIEW,view_n,1.0/1.52);
	float thickness = .55/max(.20,abs(dot(transmitted_dir,view_n)));
	vec2 bend = (transmitted_dir.xy + VIEW.xy) * thickness * (.009 + .016*bevel) * presence;
	vec2 screen = clamp(SCREEN_UV+bend,vec2(.001),vec2(.999));
	vec3 through = texture(scene_color,screen).rgb;
	if (bevel>.12) {
		through.r = texture(scene_color,clamp(screen+bend*.12,vec2(.001),vec2(.999))).r;
		through.b = texture(scene_color,clamp(screen-bend*.12,vec2(.001),vec2(.999))).b;
	}
	// Two parallel air/glass interfaces and Beer–Lambert edge absorption.
	float reflectance = (2.0*fresnel)/(1.0+fresnel);
	vec3 absorption = exp(-vec3(.095,.024,.036)*thickness*(1.0+3.5*bevel));
	vec3 reflected_color = radiance / (vec3(1.0) + radiance*.48);
	vec3 combined = mix(through*absorption,reflected_color,reflectance);
	ALBEDO = combined;
	ALPHA = presence * (.71 + .28*bevel);
}
