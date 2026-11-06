shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform float presence : hint_range(0.0, 1.0) = 1.0;
varying vec3 face_position;
varying vec3 world_point;
varying vec3 world_normal;

void vertex() {
	face_position = VERTEX;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 axes = abs(world_normal);
	vec2 panel = axes.x > 0.5 ? face_position.zy : (axes.y > 0.5 ? face_position.xz : face_position.xy);
	vec2 border = vec2(0.5) - abs(panel);
	float edge_dist = min(border.x, border.y);
	float aa = max(fwidth(edge_dist), 0.0006);
	float rim = 1.0 - smoothstep(0.001, 0.004 + aa, edge_dist);
	float inner_edge = exp(-abs(edge_dist - 0.0055) * 640.0);
	float bevel = exp(-edge_dist * 100.0);
	vec3 n = normalize(NORMAL);
	float fresnel = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.2);
	vec3 reflected = reflect(normalize(-INV_VIEW_MATRIX[2].xyz), normalize(world_normal));
	// Two tall softbox reflections anchored in the gallery outside the cube.
	// Position-dependent parallax also works with the orthographic camera.
	vec3 r = normalize(reflected + (world_point - vec3(0.,40.,0.)) * 0.006);
	float band = r.x + 0.26*r.y - 0.52*r.z;
	float softbox = (1.0-smoothstep(0.045,0.12,abs(band-0.32))) * smoothstep(-0.65,0.35,r.y);
	float ribbon = (1.0-smoothstep(0.006,0.035,abs(band-0.48))) * smoothstep(-0.6,0.5,r.y);
	// Broad streak across a pane, split by the reflected window frame.
	float window_pos = panel.x + panel.y*.32 + band*.38;
	float window = (1.0-smoothstep(.07,.16,abs(window_pos+.14))) * smoothstep(-.32,.23,panel.y);
	window *= .5 + .5*smoothstep(.006,.022,abs(window_pos+.12));
	vec2 bend = n.xy * (0.0035 + 0.009 * bevel) + panel*0.0012;
	vec3 transmitted = texture(scene_color,clamp(SCREEN_UV + bend * presence,vec2(.001),vec2(.999))).rgb;
	vec3 tint = transmitted * vec3(.90,.981,.984);
	vec3 color = mix(tint,vec3(.85,.97,1.0),clamp(.11+fresnel*.48+softbox*.64+ribbon*.65+window*.76,0.,1.));
	color = mix(color,vec3(.37,.67,.67),rim*.72);
	ALBEDO = mix(color,vec3(.94,1.,.99),inner_edge*.82);
	ALPHA = presence * clamp(.22 + .37*fresnel + .27*window + .4*inner_edge + .22*softbox + .14*ribbon + .62*rim,0.,.96);
}
