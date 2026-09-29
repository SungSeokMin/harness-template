#!/usr/bin/env bash
# run-checks.sh 회귀 테스트. 임시 git 저장소에서 변경 유형별 exit 코드를 단정한다. bash, git, jq만 필요하다.
# 실행: bash .claude/hooks/tests/run-checks.test.sh

set -uo pipefail

hook="$(cd "$(dirname "$0")/.." && pwd)/run-checks.sh"
pass=0
fail=0

# 새 임시 저장소를 만든다. $1 = 검사 명령(예: "exit 1")
new_repo() {
  repo="$(mktemp -d)"
  cd "$repo" || exit 1
  git init -q
  git config user.email t@t
  git config user.name t
  mkdir -p .claude docs src
  jq -n --arg c "$1" '{setupCompleted: true, packages: [{path: ".", profiles: [], checks: [$c]}]}' > .claude/harness.json
  printf '_workspace/\n' > .gitignore
  echo a > CLAUDE.md; echo a > README.md; echo a > docs/PRD.md; echo a > src/app.js
  git add -A && git commit -qm init
}

# run <active> → 전역 code, out 설정
run() {
  out="$(jq -n --argjson a "$1" '{stop_hook_active: $a}' | CLAUDE_PROJECT_DIR="$repo" bash "$hook" 2>/dev/null)"
  code=$?
}

expect() {
  local name="$1" want="$2"
  if [ "$code" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %-44s 기대 exit=%s 실제=%s\n' "$name" "$want" "$code"
  fi
}

assert() {
  local name="$1"; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL  %s\n' "$name"; fi
}

# --- 변경 유형별 (검사 = exit 1) ---
new_repo "exit 1"
run false; expect "변경 없음" 0
assert "변경 없음 → 결과 파일 없음" test ! -e _workspace/checks_last.txt

echo b >> CLAUDE.md; run false; expect "CLAUDE.md만 변경" 0; git checkout -q -- CLAUDE.md
echo b >> README.md; run false; expect "README.md만 변경" 0; git checkout -q -- README.md
echo b > src/NOTES.md; run false; expect "하위 폴더 *.md 추가" 0; rm src/NOTES.md
echo b >> docs/PRD.md; run false; expect "docs만 변경" 0; git checkout -q -- docs/PRD.md
echo b > .claude/x.md; run false; expect ".claude만 변경" 0; rm .claude/x.md
echo b >> src/app.js; git commit -qam c; run false; expect "커밋까지 끝난 변경" 0
git rm -q --cached .gitignore && rm .gitignore && git commit -qm "no ignore"
mkdir -p _workspace _workspace_20260101_000000; echo x > _workspace/01_plan.md; echo x > _workspace_20260101_000000/state.md
run false; expect "_workspace가 gitignore 안 된 저장소의 산출물만" 0
rm -rf _workspace _workspace_20260101_000000; printf '_workspace/\n' > .gitignore; git add .gitignore; git commit -qm ignore

# --- 실패 → 재시도 제한 ---
echo c >> src/app.js
run false; expect "src 변경 → 1회째 차단" 2
assert "실패 기록" grep -q '결과: 실패' _workspace/checks_last.txt
run true;  expect "stop_hook_active=true → 2회째 차단" 2
run true;  expect "stop_hook_active=true → 3회째 통과" 0
assert "3회째 systemMessage" bash -c "printf '%s' '$out' | jq -e '.systemMessage | test(\"실패\")' >/dev/null"
assert "3회째 뒤 카운터 초기화" test ! -e _workspace/.checks_blocks
run true;  expect "초기화 뒤 stop_hook_active=true → 다시 차단" 2
run false; expect "새 종료 시도는 횟수 초기화 → 차단" 2
assert "새 종료 시도 뒤 카운터 1" grep -qx 1 _workspace/.checks_blocks
cd /; rm -rf "$repo"

# --- 통과 ---
new_repo "true"
echo c >> src/app.js
mkdir -p _workspace; echo 1 > _workspace/.checks_blocks
run true; expect "검사 통과" 0
assert "통과 기록" grep -q '결과: 통과' _workspace/checks_last.txt
assert "통과하면 카운터 삭제" test ! -e _workspace/.checks_blocks
assert "통과 시 출력 없음" test -z "$out"
cd /; rm -rf "$repo"

echo "run-checks.sh: 통과 $pass, 실패 $fail"
[ "$fail" -eq 0 ]
