---
name: setup
description: 이 하네스를 프로젝트에 맞게 설정한다 — 프로젝트 형태(frontend / backend / fullstack / monorepo), 패키지별 프로필, 검사 명령. 템플릿으로 프로젝트를 만든 뒤 한 번, 그리고 프로젝트 형태가 바뀔 때마다 다시 실행한다.
disable-model-invocation: true
---

# Setup

기본 하네스를 프로젝트 전용 하네스로 바꾼다. 다시 실행해도 안전하다: `.claude/harness.json`과
`CLAUDE.md`의 `<!-- setup:begin project -->` 블록만 다시 쓰고, 사용자가 이미 채운 문서는 덮어쓰지 않는다.

## 1. 감지

질문하기 전에 저장소를 먼저 훑어서, 질문에 제안 답을 붙일 수 있게 한다.

- 매니페스트: `package.json`, `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `go.mod`, `pyproject.toml`, `requirements.txt`,
  `Cargo.toml`, `build.gradle*`, `pom.xml`, `Gemfile`, `composer.json`, `pubspec.yaml`, `*.csproj`
- 워크스페이스 구조: `apps/*`, `packages/*`, `services/*`, 매니페스트의 workspaces 설정
- frontend 신호: UI 프레임워크, `*.tsx`/`*.vue`/`*.svelte`, CSS/tailwind 설정, 모바일 프레임워크
- backend 신호: HTTP 프레임워크, ORM/마이그레이션, 데이터베이스 클라이언트, 큐/크론 워커
- 스크립트: 이미 정의된 test / lint / typecheck / build 명령과 패키지 매니저(lockfile)

저장소가 비어 있으면 그렇다고 말하고 질문에 의존한다.

## 2. 질문

질문 도구를 쓴다. 감지한 답을 첫 번째 선택지로 두고 "(감지됨)"이라고 표시한다.

1. **프로젝트 형태**: frontend / backend / 한 패키지 안의 fullstack / monorepo
2. **모노레포라면**: 패키지 경로마다 프로필. 공용 라이브러리 경로는 프로필이 없어도 된다.
3. **패키지별 검사 명령**: 에이전트가 끝내기 전에 통과해야 하는 명령 (lint, typecheck, test. build는 빠를 때만).
   검사는 패키지 디렉토리에서 실행된다. 빈 목록도 허용한다 — 그러면 Stop 훅이 그 패키지를 건너뛴다.

감지 결과로 분명히 답이 나온 것은 묻지 않는다 — 결과를 알려주고 사용자가 고칠 수 있게 한다.

질문 도구를 쓸 수 없거나 호출이 실패하면(헤드리스 실행 등) 멈추지 말고 추정값으로 기록한다. 추정한 항목은 `CLAUDE.md` 블록과
보고에 `(추정 — /setup 재실행으로 확정)`을 붙인다.
응답 언어는 묻지 않는다. 에이전트는 사용자가 대화에서 쓰는 언어를 따른다.
<!-- 유래: v0.1 도그푸딩 — 헤드리스에서 질문 0개로 끝났는데, 추정으로 채운 값이 확정값처럼 기록됐다 -->

## 3. 검사 명령 확인

검사 명령을 한 번씩 실행한다. 테스트 실패가 아니라 명령 자체가 틀려서 실패하면, 적기 전에 사용자와 함께 고친다.
손대지 않은 코드에서 이미 실패하는 검사가 있으면 알려 준다 — 그 실패가 Stop 훅을 막게 된다.

## 4. 기록

1. `.claude/harness.json`:
   ```json
   {
     "templateVersion": "<유지>",
     "setupCompleted": true,
     "packages": [
       { "path": "apps/web", "profiles": ["frontend"], "checks": ["pnpm lint", "pnpm test"] },
       { "path": "apps/api", "profiles": ["backend"], "checks": ["pnpm lint", "pnpm test"] }
     ]
   }
   ```
   단일 패키지 프로젝트는 `"path": "."` 항목 하나. 한 패키지 안의 fullstack은 `"profiles": ["frontend", "backend"]`.
2. `CLAUDE.md` — `<!-- setup:begin project -->`와 `<!-- setup:end project -->` 사이만 바꾼다
   (스택, 패키지별 프로필, 검사 명령). 응답 언어 줄은 템플릿 문구 그대로 둔다. 나머지는 그대로 둔다.
3. frontend 프로필이 켜졌고 `docs/UI_GUIDE.md`가 없으면 `.claude/profiles/frontend/UI_GUIDE.md`를 그 위치로 복사한다.
4. `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/ADR.md`는 건드리지 않는다. 아직 템플릿 상태면 다음에 채우자고 제안한다.

## 5. 번역 제안 (대화 언어가 한국어가 아닐 때만)

하네스 문서는 기본적으로 한국어다. 사용자가 한국어가 아닌 언어로 대화하고 있으면, 아래 파일을 그 언어로 번역할지 묻는다.
승인하면 번역한다.

- `CLAUDE.md`, `README.md`, `docs/**/*.md`
- `.claude/skills/**/SKILL.md`, `.claude/agents/*.md`, `.claude/templates/*.md`, `.claude/profiles/**/*.md`
- `.claude/hooks/*.sh`의 출력 메시지 문자열

번역하지 않는 것: 파일명, frontmatter의 `name`, `harness.json` 키, `setup:begin/end` 마커,
`PLAN_OUTPUT` 같은 블록 이름, `CRITICAL` / `Must` / `Must not` 표시, 스크립트의 코드.

## 6. 보고

바뀐 것(파일, 패키지별 프로필, 검사 명령과 현재 상태)과 아직 기본 상태로 남은 것(채우지 않은 문서)을 보여 준다.
커밋하지 않는다.
