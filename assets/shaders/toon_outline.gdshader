shader_type spatial;
// 카툰 외곽선 — toon.gdshader 의 next_pass 로 쓴다.
//
// 뒤집은 껍데기(inverted hull): 모델을 법선 방향으로 조금 부풀려 뒷면만 그린다.
// 앞면은 원래 모델이 가리므로, 실루엣 바깥으로 삐져나온 띠만 남는다.
// 색은 검정 한 가지가 아니라 그 자리 텍스처를 어둡게 한 것 — 초록 몸통엔 짙은
// 초록, 붉은 배엔 짙은 갈색 선이 나와 검은 테두리보다 덜 딱딱하다.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// 모델 단위. CHAR3D_ORTHO 1.06 / 256px 에서 1px ≈ 0.0041.
uniform float outline_width = 0.008;
uniform float darken : hint_range(0.0, 1.0) = 0.22;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * darken;
}
