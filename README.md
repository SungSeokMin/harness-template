# harness-template

> **For non-Korean speakers**
> This harness is written in Korean by default. To use it in English (or any other language), open the project with
> Claude Code and ask: **"Translate every harness document in this repository into English."**
> Running `/setup` in a non-Korean conversation also offers the translation.
> File names, JSON keys, and hook scripts stay as they are, so nothing breaks after translation.

스택에 상관없이 쓰는 Claude Code 하네스 템플릿입니다. 이 템플릿으로 프로젝트를 만들고 `/setup`을 실행하면,
에이전트가 **계획 → 비판 → 사용자 승인 → 구현 → 독립 리뷰** 순서로 일하고, 모델의 기억에 기대지 않는 안전장치가 함께 동작합니다.

프론트엔드, 백엔드, 풀스택, 모노레포 모두 쓸 수 있고 언어·프레임워크는 가리지 않습니다.

## 빠른 시작

1. **Use this template → Create a new repository** (또는 기존 저장소에 이 파일들을 복사)
2. Claude Code로 열고 `/setup` 실행
3. `docs/PRD.md`를 채우고(에이전트가 도와줍니다) 첫 기능을 요청

필요한 도구: `git`, `jq`, `bash`. 테스트한 버전: Claude Code 2.1.284 (서브에이전트 쓰기 제한과 deny 목록의 `!` 부정 패턴은 구버전에서 동작하지 않을 수 있습니다)

## `/setup` 전과 후

하네스는 바로 동작합니다. 다만 setup 전에는 덜 정밀합니다.

| | `/setup` 전 (기본 모드) | `/setup` 후 |
|---|---|---|
| 워크플로우 (계획 → 비판 → 승인 → 구현 → 리뷰) | ✅ | ✅ |
| 안전장치 (시크릿 파일, 위험 명령) | ✅ | ✅ |
| 플랜·리뷰 섹션 | 공통 섹션만 | + frontend / backend 프로필 섹션 |
| 에이전트가 끝내기 전 검사 | 건너뜀 | 패키지별 lint / test 명령 실행 |
| 세션 시작 알림 | "/setup을 실행하세요" | 없음 |

## 구조

```
CLAUDE.md                     모든 작업에 적용되는 규칙 (setup이 표시된 블록을 채움)
.claude/
  harness.json                setup 상태: 패키지 → 프로필 + 검사 명령
  settings.json               훅 연결
  skills/setup/               /setup
  skills/harness/             워크플로우
  agents/                     planner · plan-critic · developer · reviewer
  hooks/                      session-start · guard · run-checks
  hooks/tests/                훅 회귀 테스트 (bash + jq)
  templates/plan.md           공통 플랜 형식
  profiles/frontend/          플랜 섹션, 리뷰 체크리스트, UI 가이드 템플릿
  profiles/backend/           플랜 섹션, 리뷰 체크리스트
docs/
  PRD.md  ARCHITECTURE.md  ADR.md    프로젝트 문서 (채우기 전까지는 템플릿)
  lessons/                    무엇이 잘못됐고 → 하네스를 어떻게 바꿨나
```

## 하네스의 네 층

| 층 | 하는 일 | 위치 | 신뢰도 |
|---|---|---|---|
| 규칙 | 항상 지키는 약속 | `CLAUDE.md` | 부탁 — 잊을 수 있음 |
| 절차 | 작업 종류별 순서 | `.claude/skills/` | 부탁, 필요할 때만 로드 |
| 역할 | planner·critic·developer·reviewer의 분리된 컨텍스트 | `.claude/agents/` | 독립 검증 |
| 안전장치 | 기계가 강제하는 검사 | `.claude/hooks/` | 항상 |

규칙은 **어겼을 때 피해가 크고, 기계가 참/거짓을 판정할 수 있을 때만** 안전장치(훅)로 내립니다. 판단이 필요한 것은 절차와 역할에 둡니다.

## 프로필

프로필은 기술 스택이 아니라 **관점**입니다. 프로필은 플랜 섹션과 리뷰 체크 항목을 추가합니다.

- **backend** — 상태 전이, 원자성, 멱등성·동시성, 권한, 입력 검증
- **frontend** — UI 상태, 상태 소유권, 디자인 가이드 준수, 접근성, 반응형

모노레포에서는 패키지마다 프로필과 검사 명령을 따로 가지며, planner는 변경이 닿는 경로의 프로필만 적용합니다.

## 템플릿 키우기

- 무언가 잘못되면 템플릿을 따라 `docs/lessons/<날짜>-<슬러그>.md`를 쓰고, 그 문제를 잡았어야 할 층을 고칩니다.
- 새 섹션·규칙에는 유래를 남깁니다: `<!-- 유래: 무엇이 잘못됐었나 -->`
- 훅(`.claude/hooks/*.sh`)을 수정하면 `for t in .claude/hooks/tests/*.test.sh; do bash "$t"; done`로 회귀 테스트를 돌립니다.
- 모든 프로젝트에 해당하는 교훈이면 이 저장소로 PR을 보냅니다. 추가·삭제는 모두 `CHANGELOG.md`에 기록합니다.
