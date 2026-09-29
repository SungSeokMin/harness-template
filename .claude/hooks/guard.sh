#!/usr/bin/env bash
# PreToolUse 훅 — 언어와 무관한 안전장치.
#
#   1. 시크릿 파일(.env, .env.*, *.pem, *.key, id_rsa*) — 차단. 예시 파일(.env.example|sample|template)과 *.pub는 허용.
#      Bash는 명령어 종류와 상관없이 명령 문자열 전체에서 시크릿 파일 토큰을 찾는다.
#   2. 읽기 전용 에이전트(planner, plan-critic, reviewer)의 파일 쓰기 — _workspace/ 밖이면 차단.
#   3. 파괴적 명령(재귀 강제 삭제, force push, 로컬 변경 폐기, 파괴적 SQL) — 사용자에게 먼저 확인. bypass 모드에서는 건너뛴다.
#
# 차단 = exit 2 (stderr가 에이전트에게 전달됨). 확인 = permissionDecision "ask".
#
# 한계: 정규식 가드는 실수 방지용이지 적대적 우회 방지가 아니다. 변수로 조합한 경로, 인코딩한 경로,
# 파일을 이름 없이 읽는 명령(예: `grep -r x .`)은 통과한다. 이 층은 settings.json의 permissions.deny와 함께 쓴다.
# 유래: v0.1 도그푸딩 — 명령어 목록 방식이라 sed/awk/python/Grep glob/cat *.pem 등으로 시크릿이 새어 나갔고,
#       따옴표 안의 단어(`git commit -m "drop table"`)만으로 확인 창이 떴다.
# 수정하면 `bash .claude/hooks/tests/guard.test.sh`를 돌린다.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
field() { printf '%s' "$input" | jq -r "$1 // empty"; }

tool="$(field '.tool_name')"
agent="$(field '.agent_type')"
cmd="$(field '.tool_input.command')"
file="$(field '.tool_input.file_path // .tool_input.notebook_path')"

deny() {
  printf '[harness] %s\n' "$1" >&2
  exit 2
}

ask() {
  jq -n --arg reason "$1 사용자가 확인하기 전에는 다른 명령(rmdir, find -delete, mv 등)으로 같은 효과를 내지 않는다. 확인은 사용자가 한다." '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# --- 1. 시크릿 파일 --------------------------------------------------------
# 토큰 앞뒤 경계를 둔다: `process.env.HOME`, `jq '.key'`, `obj.keys()`는 시크릿 파일이 아니다.
pre="(^|[[:space:]/'\"=<(:,{])"
post="([[:space:]'\";|&)>,}]|$)"
secret="$pre(\\.env(\\.[[:alnum:]_.-]+)?|[[:alnum:]_*-][[:alnum:]_.*-]*\\.(pem|key)|id_rsa[[:alnum:]_.-]*)$post"
allowed='\.env\.(example|sample|template)|id_rsa[[:alnum:]_-]*\.pub'

has_secret() {
  printf '%s' "$1" | sed -E "s/$allowed//g" | grep -Eq "$secret"
}

# 파일 경로와 검색 범위. Grep의 pattern은 파일이 아니라 검색할 문자열이므로 검사하지 않는다.
targets=("$file")
case "$tool" in
  Grep) targets+=("$(field '.tool_input.path')" "$(field '.tool_input.glob')") ;;
  Glob) targets+=("$(field '.tool_input.path')" "$(field '.tool_input.pattern')") ;;
esac
for t in "${targets[@]}"; do
  if [ -n "$t" ] && has_secret "$t"; then
    deny "시크릿 파일 접근이 차단됐다: $t. 값이 필요하면 사용자에게 요청하거나 예시 파일(.env.example 등)을 읽는다."
  fi
done

if [ -n "$cmd" ]; then
  # 커밋 메시지(`git commit -m "…​.env…"`)는 파일을 읽지 않으므로 그 조각은 건너뛴다.
  while IFS= read -r seg; do
    printf '%s' "$seg" | grep -Eq '^[[:space:]]*git[[:space:]]+commit([[:space:]]|$)' && continue
    if has_secret "$seg"; then
      deny "명령에 시크릿 파일이 들어 있어 차단됐다. 값이 필요하면 사용자에게 요청한다. 코드에서 '.env' 문자열을 찾으려면 Grep 도구의 pattern을 쓴다."
    fi
  done < <(printf '%s\n' "$cmd" | tr ';|&' '\n\n\n')
fi

# --- 2. 읽기 전용 에이전트의 쓰기 -------------------------------------------
# 이 에이전트들은 자기 산출물(_workspace/)에만 쓴다. 이유: 코드를 바꾸면 계획·리뷰가 독립 검증이 아니게 된다.
case "$agent" in
  planner|plan-critic|reviewer)
    case "$tool" in
      Write|Edit|MultiEdit|NotebookEdit)
        root="${CLAUDE_PROJECT_DIR:-$PWD}"
        rel="${file#"$root"/}"
        case "$rel" in
          _workspace/*) ;;
          *) deny "$agent 에이전트는 _workspace/ 안의 자기 산출물 파일에만 쓸 수 있다: $file" ;;
        esac
        ;;
    esac
    ;;
esac

# --- 3. 파괴적 명령 ------------------------------------------------
[ -n "$cmd" ] || exit 0

# bypass 모드는 사용자가 확인 없이 진행하기로 고른 것이므로 확인을 건너뛴다(시크릿 차단은 위에서 이미 적용됨).
# 유래: v0.1 도그푸딩 — bypass에서도 확인 창이 떴고, 헤드리스에서는 자동 거부되어 rmdir 우회를 불렀다.
[ "$(field '.permission_mode')" = "bypassPermissions" ] && exit 0

# 따옴표 안은 명령이 아니다(`git commit -m "rm -rf 제거"`). 단 sh -c / eval은 따옴표 안이 곧 명령이다.
if printf '%s' "$cmd" | grep -Eq '(^|[[:space:]])((ba|z|da)?sh[[:space:]]+-[a-z]*c|eval)[[:space:]]'; then
  shell_cmd="$(printf '%s' "$cmd" | tr -d "'\"")"
else
  shell_cmd="$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
fi

while IFS= read -r seg; do
  seg=" $seg "
  if printf '%s' "$seg" | grep -Eq '[[:space:]]rm[[:space:]]' \
    && printf '%s' "$seg" | grep -Eq '[[:space:]](-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)[[:space:]]' \
    && printf '%s' "$seg" | grep -Eq '[[:space:]](-[a-zA-Z]*f[a-zA-Z]*|--force)[[:space:]]'; then
    ask "재귀 강제 삭제(rm -rf)다."
  fi
  if printf '%s' "$seg" | grep -Eq '[[:space:]]find[[:space:]]' \
    && printf '%s' "$seg" | grep -Eq '[[:space:]](-delete|-exec[[:space:]]+rm)[[:space:]]'; then
    ask "find로 파일을 삭제한다."
  fi
  if printf '%s' "$seg" | grep -Eq '[[:space:]]git[[:space:]]+push[[:space:]]' \
    && printf '%s' "$seg" | grep -Eq '[[:space:]](--force[a-z-]*|-f|\+[^[:space:]]+)[[:space:]]'; then
    ask "force push는 원격 이력을 덮어쓴다."
  fi
  if printf '%s' "$seg" | grep -Eq '[[:space:]]git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*f)'; then
    ask "로컬 변경을 영구히 버린다."
  fi
  if printf '%s' "$seg" | grep -Eq '[[:space:]]git[[:space:]]+checkout[[:space:]]+(--[[:space:]]+)?\.[[:space:]]'; then
    ask "작업 트리의 변경을 모두 버린다."
  fi
  if printf '%s' "$seg" | grep -Eq '[[:space:]]git[[:space:]]+restore[[:space:]]' \
    && printf '%s' "$seg" | grep -Eq '[[:space:]]\.[[:space:]]' \
    && ! { printf '%s' "$seg" | grep -Eq '[[:space:]](--staged|-S)[[:space:]]' \
           && ! printf '%s' "$seg" | grep -Eq '[[:space:]](--worktree|-W)[[:space:]]'; }; then
    ask "작업 트리의 변경을 모두 버린다."
  fi
  if printf '%s' "$seg" | grep -Eq '[[:space:]]git[[:space:]]+branch[[:space:]]' \
    && printf '%s' "$seg" | grep -Eq '[[:space:]]-[a-zA-Z]*D[a-zA-Z]*[[:space:]]'; then
    ask "병합되지 않은 브랜치를 강제로 삭제한다."
  fi
done < <(printf '%s\n' "$shell_cmd" | tr ';|&' '\n\n\n')

# SQL은 보통 따옴표 안에 있으므로(`psql -c "DROP TABLE x"`) 원문으로 검사한다.
# 문자열만 다루는 명령(git, echo, printf)으로 시작하면 건너뛴다.
if ! printf '%s' "$cmd" | grep -Eq '^[[:space:]]*(git|echo|printf)[[:space:]]'; then
  if printf '%s' "$cmd" | grep -Eiq '(drop[[:space:]]+(table|database|schema)|truncate[[:space:]]+table)'; then
    ask "파괴적인 SQL 문이다."
  fi
  while IFS= read -r stmt; do
    [ -n "$stmt" ] || continue
    if ! printf '%s' "$stmt" | grep -Eiq '[[:space:]]where[[:space:]]'; then
      ask "WHERE 없는 DELETE는 테이블의 모든 행을 지운다."
    fi
  done < <(printf '%s' "$cmd" | grep -oiE 'delete[[:space:]]+from[^;]*' || true)
fi

exit 0
