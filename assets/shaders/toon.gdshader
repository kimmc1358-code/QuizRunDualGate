shader_type spatial;
// 카툰(셀) 셰이딩 — 2.0 의 3D 캐릭터용 (Main.gd 의 CHAR3D_TOON).
//
// 모델 원래 텍스처는 그대로 쓰고, 빛만 몇 단계로 끊는다. 부드러운 명암은 2D 로
// 그린 배경·게이트 사이에서 "3D 모델을 붙여 넣은" 것처럼 보이는데, 끊긴 명암은
// 손으로 칠한 그림의 문법이라 옆의 2D 그림과 어울린다.
//
// 그림자 쪽은 이 셰이더가 아무것도 더하지 않는다 — 환경광(CHAR3D_TOON_AMBIENT)만
// 남는다. 그래서 그림자의 밝기는 Main.gd 쪽 환경광 하나로 정해진다.
render_mode cull_back, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// dot(N, L) 이 이 값을 넘으면 중간 톤, 다음 값을 넘으면 밝은 톤.
uniform float mid_threshold : hint_range(-1.0, 1.0) = 0.1;
uniform float lit_threshold : hint_range(-1.0, 1.0) = 0.6;
uniform float mid_level : hint_range(0.0, 1.0) = 0.55;
// 경계를 이만큼만 부드럽게 — 0 이면 계단이 픽셀 단위로 지글거린다.
uniform float band_softness : hint_range(0.0, 0.2) = 0.03;
// 실루엣 가장자리의 테두리 빛. 빛을 받는 쪽에만 생긴다.
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.68;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.45;

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float s = band_softness;
	float level = mix(0.0, mid_level, smoothstep(mid_threshold - s, mid_threshold + s, ndl));
	level = mix(level, 1.0, smoothstep(lit_threshold - s, lit_threshold + s, ndl));
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim_band = smoothstep(rim_threshold - s, rim_threshold + s, rim) * step(0.0, ndl);
	DIFFUSE_LIGHT += (level + rim_band * rim_strength) * ATTENUATION * LIGHT_COLOR / PI;
}
