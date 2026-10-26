# FlowView/RuleRef 소스보기 라인 하이라이트 개선

## 메타

```yaml
status: done  # codex-main 리뷰 완료 + 발견사항 중 사용자 선택 항목(1,2,6) 반영 완료
created: 2026-09-17
updated: 2026-09-18
priority: medium
```

## Goal

FlowView(노드 우클릭 "소스 보기")·RuleRefControl("연관맵" 소스보기)의 소스 라인 하이라이트를 정확한 한 줄만, 포커스 여부와 무관하게, 보기 좋은 스크롤 위치로 표시되게 하고, RuleRefControl 소스보기가 초기 상태에서 동작하지 않던 버그를 고친다.

## Constraints

- 외과수술식 수정 — 무관 코드·주석·포맷 비접촉
- 빌드/컴파일 검증 금지 (CLAUDE.md 규칙) — 사용자가 직접 빌드해 확인
- git 액션 금지 (`git diff` 외)
- `<repo-v2>`와 `<repo>`(비-V2, 사용자가 실제 빌드/사용 중인 쪽 — 2026-09-17 사용자 직접 확인) 두 체크아웃에 동일하게 적용

## Acceptance Criteria

- [x] `QueryEditorControl.SelectLine`: `SetSelection` 컬럼 오프바이원 수정(윗줄까지 같이 잡히던 문제) → 이후 전체를 `SetLineBackColor` 기반 "줄 배경색 강조" 방식으로 통일(포커스/캐럿과 색이 섞이는 문제 회피)
- [x] 디버그 소스보기 강조색: `#D8F3DC` → `#EEC8BD` → 최종 `#EEC8BD` 유지, 일반/RuleRef/인코딩변경 강조색: `#D9F0FF` → `#E1EEF7` → 최종 `#C9E5F7`
- [x] 하이라이트 시 대상 줄이 뷰 맨 위에 붙던 것을 2줄 아래로 내려 보이게 스크롤 조정(`ScrollToLineWithContext`)
- [x] `RuleRefControl.OpenSource`: 라인 파싱 실패해도 패널은 열리도록 예외 처리 분리 (단계별 try/catch 로깅은 사용자가 이후 의도적으로 제거 — 현재는 빈 catch, 최종 확정 상태)
- [x] `RuleRefControl.OpenSource`가 "View 소스보기를 먼저 눌러야만 동작하는" 근본 원인(프로그램 편집기의 `FlowAndSourceContent(true)` 지연 초기화로 `sourceControl`이 null) 규명 및 `EnsureSourceControlReady` 콜백으로 수정
- [x] codex-main 리뷰 반영: `FlowAndSourceContent.Disposed`에서 자신이 가리키는 경우에만 `EnsureSourceControlReady` 정리, `OpenSource`의 콜백 호출 try/catch + `IsDisposed` 가드 추가, `FlowView.cs`의 `SelectLine` 직전 중복 `CurrentLine` 대입 제거
- [x] 위 모든 변경을 V2/비-V2 두 저장소에 동일 적용

## Worker Plan

```yaml
# 구현은 오케스트레이터가 직접 (워커 미사용). 완료 후 사용자 요청으로 리뷰만 워커 호출.
workers_approved:
  - worker: claude-critic
    approved_at: 2026-09-18
    purpose: 오케스트레이터가 직접 구현한 소스 하이라이트/RuleRefControl 수정 리뷰
    approved_by: user
    write_scope: none
    result: 실패 — call_worker.sh 디스패처 인프라 버그(아래 Notes 참조)로 호출 자체가 안 됨
  - worker: codex-main
    approved_at: 2026-09-18
    purpose: claude-critic 실패 후 사용자가 지정한 대체 리뷰어 (mcp__codex__codex 직접 호출, 디스패처 미경유)
    approved_by: user
    write_scope: none

planned_workers:
  - role: codex-main
    purpose: 구현 완료 후 독립 리뷰 (비평 모드, read-only sandbox)
```

## Context Snapshot

target_repo (동일 적용):
- `<repo-v2>`
- `<repo>`(비-V2 — 사용자가 실제 사용 중인 빌드, 2026-09-17 확인)

수정 파일:
- `App.Common/Interface/FlowChartUiContracts.cs`
- `App.Studio/Rule/Query/QueryEditorControl.cs`
- `App.FlowChart/FlowView.cs`
- `App.Studio/Rule/Flow/FlowAndSourceContent.cs`
- `App.Studio/Rule/OtherInfo/RuleRefControl.cs`

## Notes

- **claude-critic 디스패처 실패 원인(2026-09-18)**: (1) `backends.json`의 claude-critic `args_template`이 `["--prompt", @brief_content]`인데 실제 `claude` CLI에는 `--prompt` 플래그가 없음(`-p`/`--print` + positional prompt가 맞음). (2) `call_worker.sh`의 `while IFS= read -r a; do ... done <<<"$args_json"` 루프가 `jq -r` 멀티라인 출력을 줄 단위로 읽는데, 이 환경의 Windows `jq.exe`가 CRLF(`\r\n`)를 내보내는 것을 `xxd`로 직접 확인함 — `read -r`은 `\n`만 구분자로 보고 `\r`은 안 지워서 모든 cli 타입 워커의 모든 args_template 토큰 끝에 `\r`가 붙어버림(claude-critic 한정 아님, gemini 등 cli 타입 전체 영향). 이번 task 범위 밖이라 `_shared/` 인프라 파일은 고치지 않고 사용자에게 보고만 함 — 별도 task로 다룰 것.
- 이 task 폴더는 작업 완료 후 **소급 작성**됨 — 사용자가 "오케스트레이터 직접 호출(워커 미사용)의 경우도 작업 문서를 남겨야 한다"고 2026-09-18에 정책을 확정(기존 메모리의 "문서화 생략" 방침을 뒤집음). `log.md`의 타임스탬프는 실제 발화 시각이 아니라 대화 흐름상 추정치.
- `target_repo`가 V2인지 비-V2인지 세션 내내 혼선이 있었음(사용자가 중간에 "비-V2 쓰고 있어"라고 직접 정정) — 상세 히스토리는 오케스트레이터 메모리 참조.
- **codex-main 리뷰 발견사항 중 미반영(보류) 항목** — `workers/codex-main/result.md` 참조, 필요 시 후속 task로:
  - `_lineHighlightBandLine`이 `SqlText`(문서) 교체 시 초기화 안 됨 — 다른 문서에 대해 `RemoveLineBackColor` 호출될 수 있음
  - `RemoveLineBackColor`가 이 기능이 아닌 다른 기능이 설정한 줄 배경색까지 지울 수 있음(소유권 미구분) — 동일 EditControl 내 다른 `SetLineBackColor` 사용처 전수조사 필요
  - `FormatManager`를 강조할 때마다 새로 생성(캐싱 안 함) — 성능상 치명적은 아니나 불필요한 할당
  - `QueryEditorControl.CurrentLine`의 getter가 `return this.CurrentLine;`으로 자기 자신을 무한 재귀 호출(호출되면 StackOverflow) — **이번 세션 변경과 무관한 기존 버그**, 현재 실사용 호출부는 없어 보이나 공개 인터페이스라 잠재 위험
  - 줄 번호 유효성 검사 부재(0/음수/문서 범위 초과), `TreeListNode tn` null 가드 부재, 버전 목록 순회 중 한 행 오류로 전체 폴백 중단 — 모두 기존 코드, 이번 변경과 무관
