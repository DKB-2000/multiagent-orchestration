#!/usr/bin/env bash
# 전환 모드: Claude Code ↔ Codex 오케스트레이터 flavor 전환.
#
# 반드시 사용자의 명시적 지시가 있을 때만 실행한다 (CLAUDE.md/AGENTS.md 참조).
# Orchestrator가 스스로 판단해서(예: "쿼터가 낮은 것 같으니") 실행해서는 안 된다.
#
# 동작:
#   1. 현재 flavor의 _shared/_templates/(공용 루트 파일)을 _local/flavor-backup-<현재>/ 에 스냅샷.
#   2. 대상 flavor의 백업(_local/flavor-backup-<대상>/)이 있으면 그걸 복원(과거 커스터마이징 보존).
#      없으면(최초 전환) 공식 생성기로 stock 템플릿을 설치.
#   3. tasks/, _local/ 은 항상 보존(생성기 자체 보장 + 이 스크립트는 애초에 건드리지 않음).
#
# 사용법: _shared/switch-flavor.sh <claude|codex> [--yes] [--dry-run]

set -euo pipefail

GEN="${MULTIAGENT_GENERATOR:-$HOME/.claude/plugins/marketplaces/multi-agent-starter/plugins/multi-agent-starter/skills/configure-multiagent/generator/init.py}"
BACKUP_ITEMS=(".gitignore" "README.md" "CHANGELOG.md" "KNOWN_ISSUES.md" "NOTICE" "_shared" "_templates")

TARGET=""
YES=""
DRY=""
for arg in "$@"; do
  case "$arg" in
    claude|codex) TARGET="$arg" ;;
    --yes) YES="1" ;;
    --dry-run) DRY="1" ;;
    *) echo "[error] 알 수 없는 인자: $arg"; exit 1 ;;
  esac
done
if [ -z "$TARGET" ]; then
  echo "사용법: $0 <claude|codex> [--yes] [--dry-run]"
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CURRENT="$(python -c "import json;print(json.load(open('_shared/backends.json'))['flavor'])" 2>/dev/null || echo "unknown")"

if [ "$CURRENT" = "$TARGET" ]; then
  echo "이미 $TARGET flavor 입니다. 변경 없음."
  exit 0
fi

echo "현재 flavor : $CURRENT"
echo "전환 대상   : $TARGET"
[ -n "$DRY" ] && echo "[dry-run] 실제 변경 없음"

if [ -z "$YES" ] && [ -z "$DRY" ]; then
  read -r -p "진행할까요? [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "취소됨"; exit 1 ;;
  esac
fi

CUR_INSTR=$([ "$CURRENT" = "codex" ] && echo "AGENTS.md" || echo "CLAUDE.md")
TGT_INSTR=$([ "$TARGET" = "codex" ] && echo "AGENTS.md" || echo "CLAUDE.md")

BACKUP_DIR="_local/flavor-backup-$CURRENT"
echo "[1/2] 현재($CURRENT) 상태 백업 -> $BACKUP_DIR"
if [ -z "$DRY" ]; then
  rm -rf "$BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  for item in "${BACKUP_ITEMS[@]}" "$CUR_INSTR"; do
    [ -e "$item" ] && cp -r "$item" "$BACKUP_DIR/"
  done
fi

RESTORE_DIR="_local/flavor-backup-$TARGET"
if [ -d "$RESTORE_DIR" ]; then
  echo "[2/2] 이전 $TARGET 백업 복원 <- $RESTORE_DIR (커스터마이징 보존됨)"
  if [ -z "$DRY" ]; then
    for item in "${BACKUP_ITEMS[@]}"; do
      if [ -e "$RESTORE_DIR/$item" ]; then
        rm -rf "$item"
        cp -r "$RESTORE_DIR/$item" "$item"
      fi
    done
    [ -e "$RESTORE_DIR/$TGT_INSTR" ] && cp "$RESTORE_DIR/$TGT_INSTR" "$TGT_INSTR"
  fi
else
  echo "[2/2] $TARGET 최초 전환 -> 공식 생성기로 stock 템플릿 설치"
  if [ -z "$DRY" ]; then
    python "$GEN" --flavor "$TARGET" --target . --yes
  fi
fi

echo
echo "완료. flavor = $TARGET"
echo "되돌리려면: $0 $CURRENT --yes"
