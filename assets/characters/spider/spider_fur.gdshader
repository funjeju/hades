shader_type spatial;
// 셸 털: 같은 메시를 노멀 방향으로 조금씩 부풀린 껍질을 여러 장 겹쳐 그린다.
// 껍질마다 털 가닥 자리만 남기고 나머지는 버려서, 겹쳐 보면 짧은 털이 서 있는 것처럼 보인다.
// 가닥 자리는 블렌더에서 UV(xy)와 UV2(z)에 넣어 둔 기본 자세 위치로 정하므로, 애니메이션 중에도 털이 미끄러지지 않는다.
render_mode cull_back, depth_draw_opaque;

// 0 = 몸 표면, 1 = 털 끝 껍질.
uniform float layer : hint_range(0.0, 1.0) = 0.0;
uniform float fur_length = 0.05;
// 1m당 가닥 수.
uniform float density = 70.0;
// 가닥 굵기(칸 크기 대비).
uniform float thickness : hint_range(0.0, 1.0) = 0.75;
// 뿌리 쪽을 얼마나 어둡게 할지.
uniform float root_shade : hint_range(0.0, 1.0) = 0.45;

varying vec3 rest_pos;

void vertex() {
	rest_pos = vec3(UV.x, 1.0 - UV.y, UV2.x);
	VERTEX += NORMAL * fur_length * layer;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	if (layer > 0.0) {
		vec3 cell = floor(rest_pos * density);
		// 가닥마다 길이가 다르다.
		float strand_height = mix(0.35, 1.0, hash(cell));
		if (layer > strand_height) {
			discard;
		}
		// 끝으로 갈수록 가늘어진다.
		vec3 local = fract(rest_pos * density) - 0.5;
		float radius = thickness * 0.5 * (1.0 - layer / strand_height);
		if (length(local) > radius) {
			discard;
		}
	}
	ALBEDO = COLOR.rgb * mix(1.0 - root_shade, 1.15, layer);
	ROUGHNESS = 0.9;
}
