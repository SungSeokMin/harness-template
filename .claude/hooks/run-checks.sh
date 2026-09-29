#!/usr/bin/env bash
# Stop 훅 — 에이전트가 끝내기 전에, 커밋되지 않은 변경이 있는 패키지의 검사 명령을 실행한다.
#
# 검사 명령은 /setup이 기록한 .claude/harness.json(packages[].checks)에서 읽는다.
# /setup 전에는 검사 명령이 비어 있어 이 훅은 아무것도 하지 않는다.
#
# 검사를 실행하면 결과를 _workspace/checks_last.txt에 남긴다(통과도 남긴다 — 오래된 실패가 남지 않게).
# 실패하면 연속 2회까지 종료를 막고, 3회째에는 통과시키되 사용자에게 경고(systemMessage)를 보인다.
# 유래: v0.1 도그푸딩 — stop_hook_active면 무조건 통과해서, 검사 실패 상태로 조용히 끝날 수 있었다
# 수정하면 `bash .claude/hooks/tests/run-checks.test.sh`를 돌린다.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

max_blocks=2

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false')"

root="${CLAUDE_PROJECT_DIR:-$PWD}"
config="$root/.claude/harness.json"
[ -f "$config" ] || exit 0
cd "$root" || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

workspace="$root/_workspace"
counter="$workspace/.checks_blocks"
failed=""
ran=""

while IFS= read -r pkg; do
  path="$(printf '%s' "$pkg" | jq -r '.path')"

  # 변경이 있는 패키지만 검사한다. 하네스·문서(.claude, docs, *.md)와 산출물(_workspace*)만 바뀐 것은 코드 변경으로 보지 않는다.
  # _workspace는 .gitignore에 있지만, 기존 저장소에 복사하며 .gitignore를 합치지 않은 경우를 위해 여기서도 뺀다.
  # 유래: v0.1 도그푸딩 — /setup이 CLAUDE.md를 바꾼 뒤 커밋 전까지 질문만 한 턴에도 매번 테스트가 돌았다
  changed="$(git status --porcelain -- "$path" ':(exclude).claude' ':(exclude)docs' ':(exclude,glob)**/*.md' ':(exclude,glob)_workspace*/**' 2>/dev/null)"
  [ -n "$changed" ] || continue

  while IFS= read -r check; do
    [ -n "$check" ] || continue
    ran+="[$path] $check"$'\n'
    output="$(cd "$root/$path" && bash -c "$check" 2>&1)"
    if [ $? -ne 0 ]; then
      failed+="--- [$path] $check"$'\n'"$(printf '%s\n' "$output" | tail -n 30)"$'\n'
    fi
  done < <(printf '%s' "$pkg" | jq -r '.checks[]?')
done < <(jq -c '.packages[]?' "$config")

[ -n "$ran" ] || exit 0

mkdir -p "$workspace"
{
  echo "시각: $(date '+%Y-%m-%d %H:%M:%S')"
  if [ -n "$failed" ]; then echo "결과: 실패"; else echo "결과: 통과"; fi
  echo "실행한 검사:"
  printf '%s' "$ran"
  [ -z "$failed" ] || printf '\n%s' "$failed"
} > "$workspace/checks_last.txt"

if [ -z "$failed" ]; then
  rm -f "$counter"
  exit 0
fi

# 새로 시작한 종료 시도(stop_hook_active=false)면 횟수를 처음부터 센다.
blocks=0
if [ "$active" = "true" ] && [ -f "$counter" ]; then
  blocks="$(cat "$counter" 2>/dev/null || echo 0)"
fi
blocks=$((blocks + 1))

if [ "$blocks" -le "$max_blocks" ]; then
  echo "$blocks" > "$counter"
  {
    echo "[harness] 검사가 실패했다 ($blocks/$max_blocks). 아직 끝내지 말고, 무엇이 실패했는지 설명한 뒤 작업 범위 안의 것만 고친다."
    printf '%s' "$failed"
  } >&2
  exit 2
fi

rm -f "$counter"
jq -n '{systemMessage: "[harness] 검사가 실패한 상태로 종료됐다. 자세한 내용: _workspace/checks_last.txt"}'
exit 0
