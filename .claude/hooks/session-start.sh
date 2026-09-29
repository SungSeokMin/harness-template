#!/usr/bin/env bash
# SessionStart 훅 — /setup을 아직 실행하지 않았다는 사실을 에이전트(그리고 에이전트를 통해 사용자)에게 알린다.
# SessionStart 훅의 stdout은 세션 컨텍스트에 추가된다.

set -uo pipefail

config="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/harness.json"
[ -f "$config" ] || exit 0
command -v jq >/dev/null 2>&1 || { echo "[harness] jq가 설치되어 있지 않아 훅이 제한된 모드로 동작한다."; exit 0; }

if [ "$(jq -r '.setupCompleted' "$config")" = "true" ]; then
  exit 0
fi

cat <<'EOF'
[harness] 아직 /setup을 실행하지 않았다.
하네스는 기본 모드로 동작한다: 워크플로우와 안전장치는 켜져 있지만, 프로젝트 스펙을 모르기 때문에
자동 검사(lint/test/build)와 frontend/backend 프로필 섹션은 꺼져 있다.
첫 응답의 맨 앞에서, /setup을 실행하면 이것들이 켜진다고 사용자에게 한 줄로 알린다.
EOF
