#!/usr/bin/env bash
# guard.sh 회귀 테스트. 합성 PreToolUse JSON을 넣고 결과를 단정한다. bash와 jq만 필요하다.
#   차단 = exit 2, 확인 = permissionDecision "ask", 허용 = exit 0이고 출력 없음.
# 실행: bash .claude/hooks/tests/guard.test.sh

set -uo pipefail

guard="$(cd "$(dirname "$0")/.." && pwd)/guard.sh"
root="/tmp/proj"
pass=0
fail=0

# check <기대값> <설명> <tool_name> <tool_input JSON> [agent_type]
check() {
  local want="$1" name="$2" tool="$3" tin="$4" agent="${5:-}" out code got
  out="$(jq -n --arg t "$tool" --argjson i "$tin" --arg a "$agent" \
    '{tool_name: $t, tool_input: $i} + (if $a == "" then {} else {agent_type: $a} end)' \
    | CLAUDE_PROJECT_DIR="$root" bash "$guard" 2>/dev/null)"
  code=$?
  if [ "$code" -eq 2 ]; then got="차단"
  elif [ "$code" -eq 0 ] && printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null 2>&1; then got="확인"
  elif [ "$code" -eq 0 ] && [ -z "$out" ]; then got="허용"
  else got="예상 밖(exit $code)"
  fi
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  %-40s 기대=%s 실제=%s\n' "$name" "$want" "$got"
  fi
}

bash_cmd() { jq -n --arg c "$1" '{command: $c}'; }

# --- 시크릿: 파일 도구 ---
check 차단 "Read .env"                 Read '{"file_path":"/tmp/proj/.env"}'
check 차단 "Read .env.local"           Read '{"file_path":"/tmp/proj/.env.local"}'
check 차단 "Read *.pem"                Read '{"file_path":"/tmp/proj/cert.pem"}'
check 차단 "Edit .env"                 Edit '{"file_path":".env","old_string":"a","new_string":"b"}'
check 허용 "Read .env.example"         Read '{"file_path":"/tmp/proj/.env.example"}'
check 허용 "Read .env.sample"          Read '{"file_path":".env.sample"}'
check 허용 "Read .env.template"        Read '{"file_path":".env.template"}'
check 허용 "Read src/env.ts"           Read '{"file_path":"src/env.ts"}'
check 허용 "Read .envrc 아님(.environment)" Read '{"file_path":"src/.environment.ts"}'
check 차단 "Grep glob .env"            Grep '{"pattern":"KEY","glob":".env"}'
check 차단 "Grep path .env"            Grep '{"pattern":"KEY","path":"/tmp/proj/.env"}'
check 허용 "Grep pattern만 .env"       Grep '{"pattern":"\\.env","path":"src"}'
check 허용 "Grep pattern process.env"  Grep '{"pattern":"process.env"}'
check 차단 "Glob **/.env"              Glob '{"pattern":"**/.env"}'
check 차단 "Glob *.pem"                Glob '{"pattern":"**/*.pem"}'
check 허용 "Glob *.ts"                 Glob '{"pattern":"src/**/*.ts"}'

# --- 시크릿: Bash ---
check 차단 "cat .env"                  Bash "$(bash_cmd 'cat .env')"
check 차단 "cat < .env"                Bash "$(bash_cmd 'cat < .env')"
check 차단 "sed -n 1p .env"            Bash "$(bash_cmd 'sed -n 1p .env')"
check 차단 "awk 1 .env"                Bash "$(bash_cmd 'awk 1 .env')"
check 차단 "nl .env"                   Bash "$(bash_cmd 'nl .env')"
check 차단 "xxd .env"                  Bash "$(bash_cmd 'xxd .env')"
check 차단 "strings .env"              Bash "$(bash_cmd 'strings .env')"
check 차단 "base64 .env"               Bash "$(bash_cmd 'base64 .env')"
check 차단 "python open('.env')"       Bash "$(bash_cmd "python3 -c \"print(open('.env').read())\"")"
check 차단 "node readFileSync('.env')" Bash "$(bash_cmd "node -e \"require('fs').readFileSync('.env','utf8')\"")"
check 차단 "cat *.pem"                 Bash "$(bash_cmd 'cat *.pem')"
check 차단 "cat ~/.ssh/id_rsa"         Bash "$(bash_cmd 'cat ~/.ssh/id_rsa')"
check 차단 "cat secrets.key"           Bash "$(bash_cmd 'cat secrets.key')"
check 차단 "cat config/.env.production" Bash "$(bash_cmd 'cat config/.env.production')"
check 차단 "파이프 뒤 .env"            Bash "$(bash_cmd 'ls && cat .env | head')"
check 허용 "cat .env.example"          Bash "$(bash_cmd 'cat .env.example')"
check 허용 "cp .env.example 없이 비교"  Bash "$(bash_cmd 'diff .env.example .env.sample')"
check 허용 "cat id_rsa.pub"            Bash "$(bash_cmd 'cat ~/.ssh/id_rsa.pub')"
check 허용 "process.env.HOME"          Bash "$(bash_cmd 'node -e "console.log(process.env.HOME)"')"
check 허용 "jq '.key'"                 Bash "$(bash_cmd "jq -r '.key' data.json")"
check 허용 "obj.keys()"                Bash "$(bash_cmd 'node -e "Object.keys(x)"')"
check 허용 "git commit -m .env"        Bash "$(bash_cmd 'git commit -m "chore: .env를 gitignore에 추가"')"
check 허용 "npm test"                  Bash "$(bash_cmd 'npm test')"

# --- 읽기 전용 에이전트의 쓰기 ---
check 허용 "planner → _workspace"      Write '{"file_path":"/tmp/proj/_workspace/01_plan.md","content":"x"}' planner
check 허용 "reviewer → 상대경로 _workspace" Write '{"file_path":"_workspace/05_review_round1.md","content":"x"}' reviewer
check 차단 "planner → src"             Write '{"file_path":"/tmp/proj/src/a.js","content":"x"}' planner
check 차단 "plan-critic Edit src"      Edit '{"file_path":"/tmp/proj/src/a.js","old_string":"a","new_string":"b"}' plan-critic
check 차단 "reviewer → 루트 파일"      Write '{"file_path":"/tmp/proj/README.md","content":"x"}' reviewer
check 허용 "developer → src"           Write '{"file_path":"/tmp/proj/src/a.js","content":"x"}' developer
check 허용 "메인 스레드 → src"         Write '{"file_path":"/tmp/proj/src/a.js","content":"x"}'

# --- 파괴적 명령: 확인 ---
check 확인 "rm -rf"                    Bash "$(bash_cmd 'rm -rf node_modules')"
check 확인 "rm -fr"                    Bash "$(bash_cmd 'rm -fr build')"
check 확인 "rm -r -f"                  Bash "$(bash_cmd 'rm -r -f build')"
check 확인 "rm --recursive --force"    Bash "$(bash_cmd 'rm --recursive --force build')"
check 확인 "sudo rm -Rf"               Bash "$(bash_cmd 'sudo rm -Rf /opt/x')"
check 확인 "find -delete"              Bash "$(bash_cmd 'find . -name "*.log" -delete')"
check 확인 "find -exec rm"             Bash "$(bash_cmd 'find . -type f -exec rm {} \;')"
check 확인 "git push --force"          Bash "$(bash_cmd 'git push --force origin main')"
check 확인 "git push -f"               Bash "$(bash_cmd 'git push -f')"
check 확인 "git push --force-with-lease" Bash "$(bash_cmd 'git push --force-with-lease origin main')"
check 확인 "git push +main"            Bash "$(bash_cmd 'git push origin +main')"
check 확인 "git reset --hard"          Bash "$(bash_cmd 'git reset --hard HEAD~1')"
check 확인 "git clean -fd"             Bash "$(bash_cmd 'git clean -fd')"
check 확인 "git checkout ."            Bash "$(bash_cmd 'git checkout .')"
check 확인 "git checkout -- ."         Bash "$(bash_cmd 'git checkout -- .')"
check 확인 "git restore ."             Bash "$(bash_cmd 'git restore .')"
check 확인 "git restore -SW ."         Bash "$(bash_cmd 'git restore --staged --worktree .')"
check 확인 "git branch -D"             Bash "$(bash_cmd 'git branch -D feature/x')"
check 확인 "psql DROP TABLE"           Bash "$(bash_cmd 'psql -c "DROP TABLE orders"')"
check 확인 "TRUNCATE TABLE"            Bash "$(bash_cmd 'mysql -e "truncate table orders"')"
check 확인 "DELETE FROM (WHERE 없음)"  Bash "$(bash_cmd 'psql -c "DELETE FROM orders"')"
check 확인 "bash -c rm -rf"            Bash "$(bash_cmd 'bash -c "rm -rf build"')"
check 확인 "&& 뒤 rm -rf"              Bash "$(bash_cmd 'cd app && rm -rf dist')"

# --- 파괴적 명령: 오탐 없음 ---
check 허용 "commit 메시지 drop table"  Bash "$(bash_cmd 'git commit -m "remove drop table docs"')"
check 허용 "echo rm -rf"               Bash "$(bash_cmd 'echo "rm -rf 는 조심"')"
check 허용 "DELETE ... WHERE"          Bash "$(bash_cmd "psql -c \"DELETE FROM orders WHERE id = 1\"")"
check 허용 "rm -r (강제 아님)"          Bash "$(bash_cmd 'rm -r build')"
check 허용 "rm -f (재귀 아님)"          Bash "$(bash_cmd 'rm -f a.txt')"
check 허용 "git push"                  Bash "$(bash_cmd 'git push origin main')"
check 허용 "git restore --staged ."    Bash "$(bash_cmd 'git restore --staged .')"
check 허용 "git checkout -b"           Bash "$(bash_cmd 'git checkout -b feature/x')"
check 허용 "git branch -d"             Bash "$(bash_cmd 'git branch -d feature/x')"
check 허용 "find -name"                Bash "$(bash_cmd 'find . -name "*.js"')"

# --- bypass 모드: 확인은 건너뛰고 시크릿 차단은 유지 ---
bypass() {
  local want="$1" name="$2" c="$3" out code got
  out="$(jq -n --arg c "$c" '{tool_name: "Bash", tool_input: {command: $c}, permission_mode: "bypassPermissions"}' \
    | CLAUDE_PROJECT_DIR="$root" bash "$guard" 2>/dev/null)"
  code=$?
  if [ "$code" -eq 2 ]; then got="차단"; elif [ -z "$out" ]; then got="허용"; else got="확인"; fi
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL  %-40s 기대=%s 실제=%s\n' "$name" "$want" "$got"; fi
}
bypass 허용 "bypass: rm -rf"           'rm -rf node_modules'
bypass 허용 "bypass: git push --force" 'git push --force'
bypass 차단 "bypass: cat .env"         'cat .env'

echo "guard.sh: 통과 $pass, 실패 $fail"
[ "$fail" -eq 0 ]
