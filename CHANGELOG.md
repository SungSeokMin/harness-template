# 변경 이력

템플릿에 추가되거나 삭제된 섹션·규칙과 그 이유를 기록합니다.

## [0.1.0] - 2026-09-29

### 추가
- 공통 워크플로우 스킬 `harness`: planner → plan-critic → 사용자 승인 → developer → reviewer, `_workspace/` 산출물 저장
- `/setup` 스킬: 프로젝트 형태, 패키지별 프로필과 검사 명령, 한국어가 아닌 대화에서 번역 제안
- `frontend`, `backend` 프로필 (플랜 섹션 + 리뷰 체크리스트, UI 가이드 템플릿)
- 훅: 세션 시작 알림, 시크릿 파일·위험 명령 가드, 종료 전 패키지별 검사
- 문서 템플릿: PRD, ARCHITECTURE, ADR, lessons
- 훅 회귀 테스트 `.claude/hooks/tests/` (guard, run-checks)

### 변경 (v0.1 도그푸딩 반영)
- `_workspace/` 산출물은 작성 에이전트의 원문 그대로 남긴다. planner·plan-critic·reviewer에 Write를 주고, guard 훅이 이들의 `_workspace/` 밖 쓰기를 막는다. 보강은 `## 보강`에 덧붙인다 — 오케스트레이터가 원문을 요약해 저장해서 재개·감사가 불가능했다
- guard 시크릿 차단: 명령어 목록 대신 명령 전체의 시크릿 파일 토큰을 찾고, Grep·Glob도 검사한다. `permissions.deny`와 `.gitignore`에 시크릿 규칙 추가 — sed/awk/python/Grep glob 등으로 새어 나갔다
- guard 파괴적 명령: `rm -r -f`, `find -delete`, `git checkout/restore .`, `git branch -D`, `+ref`/`--force-with-lease` push, WHERE 없는 DELETE 추가. 따옴표 안 문자열로 인한 오탐 제거. 확인 전에 다른 명령으로 같은 효과를 내지 말라고 명시. bypass 모드에서는 확인을 건너뛴다(시크릿 차단은 유지) — 누락·오탐이 있었고, bypass에서도 확인 창이 떴으며, 거부되자 rmdir로 우회했다
- Stop 훅: `*.md`만 바뀌면 검사하지 않는다. 결과를 `_workspace/checks_last.txt`에 남기고, 실패 시 연속 2회까지 막은 뒤 사용자에게 경고한다 — 문서만 바꿔도 매 턴 테스트가 돌았고, 두 번째 종료는 실패해도 조용히 통과했다
- 응답 언어 설정(`responseLanguage`)을 없앤다. 에이전트는 사용자가 대화에서 쓰는 언어를 따르며, 이 규칙을 명령형으로 `CLAUDE.md`와 harness 스킬 첫머리에 둔다 — 한국어 대화인데 최종 응답이 영어로 시작했다
- `/setup`은 질문 도구를 쓸 수 없으면 추정값을 `(추정)`으로 표시한다 — 헤드리스에서 추정값이 확정값처럼 기록됐다
- harness 3단계 승인 요청에 "비판 지적 → 반영" 표와 "승인 전에 정해 주세요" 목록을 고정 형식으로 넣는다
- 경량 트랙은 planner 없이 오케스트레이터가 짧은 플랜을 쓰고, reviewer가 트랙 판정을 다시 확인한다 — 한 줄 변경에 약 $1.5가 들었다
- 플랜 템플릿: `기능` 행(수용 기준)과 `[기존 결함]` 표시 규칙 추가. reviewer 판정값에 `기존 결함(승인됨)`, `미검증` 추가
- plan-critic은 프로필 추가 트랙 기준의 "예" 행마다 깨지는 시나리오를 찾는다. backend B3에 재시도 응답 질문 추가
- frontend 리뷰 체크리스트에 실제 렌더 확인(못 하면 미검증) 추가
