# Worker Smoke Test

## 메타

```yaml
status: done
created: 2026-08-10
updated: 2026-08-10
priority: low
```

## Goal

담당 워커(claude-main, codex-main, codex-critic, ollama, gemini)가 실제로 이 환경에서 응답하는지 커넥티비티 확인.

## Constraints

- 실제 작업 산출물 없음 — 단순 응답/식별 확인용
- 각 워커에 "자기 role과 상태를 한 줄로 답하라"는 최소 프롬프트만 전달
- gemini는 사전 점검 결과 이 환경에 `agy` CLI 미설치 + `GEMINI_API_KEY` 미설정 → 테스트 제외 (사용자 확인됨)

## Acceptance Criteria

- [x] claude-main 응답 확인
- [x] codex-main 응답 확인 (codex.exe 전체경로 호출, PATH 미등록 상태 — 사용자 승인된 방식)
- [x] codex-critic 응답 확인 (동일 방식)
- [x] ollama 응답 확인 (call_worker.sh 디스패처)
- [x] gemini는 사유 기록 후 스킵

## Worker Plan

```yaml
workers_approved:
  - worker: claude-main
    approved_at: 2026-08-10
    purpose: 스모크테스트 — 응답 확인
    approved_by: user
  - worker: codex-main
    approved_at: 2026-08-10
    purpose: 스모크테스트 — 응답 확인 (codex.exe 전체경로 직접 호출)
    approved_by: user
  - worker: codex-critic
    approved_at: 2026-08-10
    purpose: 스모크테스트 — 응답 확인 (codex.exe 전체경로 직접 호출)
    approved_by: user
  - worker: ollama
    approved_at: 2026-08-10
    purpose: 스모크테스트 — 응답 확인
    approved_by: user

planned_workers:
  - role: claude-main
    purpose: 응답 확인
  - role: codex-main
    purpose: 응답 확인
  - role: codex-critic
    purpose: 응답 확인
  - role: ollama
    purpose: 응답 확인
```

## Context Snapshot

사전 점검(2026-08-10): mcp__codex__codex MCP 도구 이 환경에 미등록. codex CLI는
`<codex-install-dir>\codex.exe`에 설치·로그인 완료
확인(codex-cli 0.144.2)되었으나 세션 PATH 미등록 — 사용자 승인 하에 이번 테스트는 전체경로로 직접
호출. ollama 원격 호스트(`http://<ollama-host>:11434`) 응답 200 확인. gemini는 `agy` CLI 없고
`GEMINI_API_KEY`도 없어 primary/fallback 모두 불가 — 제외.

## Notes

target_repo: N/A (분석/테스트 전용, 외부 산출물 없음)
