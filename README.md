# QuizRunDualGate — 그레이박스 프로토타입

국기 탐험 모드 하드 난이도 그레이박스 프로토타입. 상세 기획은
[듀얼게이트_퀴즈러너_기획서_v2.md](듀얼게이트_퀴즈러너_기획서_v2.md) 참고.

메인 로직: [scripts/Main.gd](scripts/Main.gd) · 씬: [scenes/Main.tscn](scenes/Main.tscn)

## 튜닝 기본값 (2026-08-20 기준)

> **임시 기본값 — 추후 실제 플레이테스트 후 재조정 예정.**
> 아래 값들은 `Main` 노드 인스펙터에서 `@export` 슬라이더로 라이브 조정하며
> 감으로 잡은 값이며, 최종 밸런스가 아닙니다. Phase 임계값(게이트 통과 개수)
> 등 다른 수치들도 아직 미확정이므로, 실제 플레이테스트 데이터가 쌓이면
> 이 값들부터 다시 검토해야 합니다.

| 항목 (인스펙터 표시명) | 값 | 코드 위치 |
|---|---|---|
| Flap Velocity (탭 1회 상승 임펄스) | `-300` px/s | [Main.gd:12](scripts/Main.gd:12) |
| Gravity (중력가속도) | `1000` px/s² | [Main.gd:13](scripts/Main.gd:13) |
| Max Fall Speed (최대 낙하속도) | `300` px/s | [Main.gd:14](scripts/Main.gd:14) |
| Base Gate Spacing (게이트 스폰 거리) | `600` px | [Main.gd:15](scripts/Main.gd:15) |
| Max Move Ratio Early (Phase 1~2 게이트 간 이동거리 상한) | `0.5` (화면 높이 비율) | [Main.gd:20](scripts/Main.gd:20) |
| Max Move Ratio Late (Phase 3~4 게이트 간 이동거리 상한) | `0.65` (화면 높이 비율) | [Main.gd:21](scripts/Main.gd:21) |

이 값들은 스크립트의 `@export` 기본값으로도 반영되어 있어서, 씬을 새로
플레이해도 동일하게 시작합니다. 인스펙터에서 슬라이더를 움직이면 그
자리에서 바로 다시 조정해 테스트할 수 있습니다.
