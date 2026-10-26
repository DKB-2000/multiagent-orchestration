# MultiAgent Orchestration — Operating Rules

## Architecture

```
Orchestrator (Claude Code session, internal reasoning — not a worker, no approval needed)
└── Worker Pool (모두 외부 호출 — 승인 필요)
    ├── claude-main    [strategist] 기획·설계·아키텍처·전략·디자인 방향·문체 글쓰기·디버깅 원인 분석
    ├── codex-main     [engineer·computer-use] 대규모 구현·코드 분석·테스트·diff·로컬 검증·브라우저 자동화·이미지 생성
    ├── codex-critic   [reviewer] 산출물 리뷰·비평 (Codex의 주된 역할)
    ├── ollama         [reviewer·self-hosted] 벤더 쿼터 없는 보조 검증
    └── gemini         [multimodal] 멀티모달·긴 문서·제3자 시각 검토
```

능력 슬롯→워커 배정 정본: `_shared/capability-profile.md`(가변층 — 신모델 출시 시 프로필만 갱신). claude-main 등 서브에이전트 호출도 별도 모델 호출이라 승인·쿼터 대상.

## 운영 원칙 (Orchestrator 전용)

1. **작업 전 확인**: 가정을 명시하고 불확실하면 묻는다. 해석이 여럿이면 나열하고 조용히 고르지 않는다. 더 단순한 대안이 있으면 말한다.
2. **최소 구현**: 요청 이상의 기능·추상화·유연성·불가능한 상황의 에러처리 금지. 200줄이 50줄로 될 수 있으면 다시 쓴다.
3. **외과수술식 수정**: 무관한 코드·주석·포맷은 안 건드리고 기존 스타일을 유지한다. 내 변경이 만든 고아(import·변수·함수)만 제거하고, 기존 죽은 코드는 삭제 대신 언급만 한다. 모든 변경 줄은 요청과 직결돼야 한다. 주석 작성 규칙은 `_shared/code-comment-policy.md` 참조.
4. **목표 기반 실행**: "버그 수정"처럼 막연한 요청을 "재현 테스트 작성 → 통과"식 검증 가능한 목표로 바꾸고, 다단계 작업은 `단계→검증` 계획을 짧게 제시한 뒤 루프한다.
5. **한국어 응답**: 사용자에게는 항상 한국어로 답변한다.
6. **git 액션 제한**: 조회 전용 git 액션(`diff`/`log`/`show`/`status`/`blame`/`branch -a`/`reflog`(조회만)/`fetch`)만 Orchestrator·worker 모두 허용한다. 그 외 작업 폴더·이력·원격을 바꾸는 액션(`pull`/`merge`/`add`/`commit`/`push`/`checkout`/`restore`/`reset`/`stash`/`rebase`/브랜치 생성·삭제 등)은 진행하지 않고 사용자에게 직접 실행을 안내만 한다.
7. **빌드 테스트 금지**: 모든 솔루션·프로젝트의 빌드/컴파일 검증(MSBuild, javac, npm build 등)은 Orchestrator·worker 모두 진행하지 않는다. 빌드 확인이 필요하면 사용자에게 직접 실행을 요청한다.

사소한 작업엔 판단으로 완화. 워커층 정본은 `_templates/worker-brief.md`의 "Worker 행동 규약" 고정 블록(②·③·⑥·⑦ 동일, ①은 "가정 명시 + 불확실성은 result.md Issues/Caveats로 표면화"로 대체, ④는 Orchestrator 전담, ⑤는 산출물에도 동일 적용). worker brief·agent 정의에 "사용자에게 질문" 지시나 이 규약의 중복 기재 금지.

> 출처: [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) (MIT) — adapted. 상세는 `NOTICE` 참조.

## Task Lifecycle

1. `tasks/<task-name>/task.md` 작성 (status: pending)
2. `_shared/routing.md` 참조 → 최소 worker set 결정
3. **target_repo 확인**: codex-main이 코드·문서·이미지를 만드는 작업이면 사용자에게 `target_repo`를 묻는다("없음"·분석/리뷰/요약만이면 `tasks/<task>/artifacts/`에 diff·patch로 산출). 요청에 경로가 이미 있으면 재질문 안 함
4. 모든 worker(claude-main 포함) 사용 시 `task.md`의 `workers_approved`에 명시적 기록 필요
5. 각 worker의 brief를 **정확히 `tasks/<task>/workers/<role>/brief.md`** 에 작성 (≤ 1200자 한글 / 240단어 영문). 워커별 폴더로 분리할 것 — `<role>_brief.md`처럼 납작하게 만들지 말 것
6. worker 실행 → 원문을 **`tasks/<task>/workers/<role>/result.md`** 에 저장 (같은 워커별 폴더)
7. `result.md`의 Verification Checklist 실행
8. 검증 결과를 `log.md`에 append (`[VERIFICATION]` 태그). 작업이 끝나면 `task.md`의 `status`를 `done`으로 갱신
9. 완료 후 교훈 추가 (분류): **시스템 운영 자체**에 대한 일반 교훈 → `_shared/learnings.md`(추적·공개). **특정 외부 프로젝트 한정**(mat·hwpx 등) → `_local/learnings.md`(git 추적 안 함, 없으면 생성). `_local/learnings.md`는 명시 요청 없이는 로드하지 않는다.

> **기존 작업 재개 시**(새 세션 포함)는 1번부터가 아니라 `_shared/orchestrator-rules.md` §3 **재진입 프로토콜**을 먼저 따른다 (재정박 → 분기 → 에러 후 진행).

## Context Rules

| 파일 | 제한 (측정 가능 기준) | 목적 |
|------|------------------|------|
| `context.md` | ≤ 1500자 (한글) / ≤ 300단어 (영문) | 현재 스냅샷만. 히스토리 아님 |
| `brief.md` | ≤ 1200자 (한글) / ≤ 240단어 (영문) | worker가 실행에 필요한 것만 |
| `sources/`, `artifacts/` | 무제한 | 원본 자료·worker 산출물. brief엔 경로만 참조 |

측정: `wc -m tasks/<task>/context.md`(한글 글자수) / `wc -w tasks/<task>/context.md`(영문 단어수). **초과 시**: 핵심만 남기고 나머지는 `log.md`에 append 후 초기화. **brief 작성 원칙**: 파일 내용을 inline 금지, 경로만 전달.

## Approval Gate

- `workers_approved`에 없는 worker 호출 금지 (claude-main 포함 전체 worker pool 적용)
- 작업당 첫 호출 전 사용자에게 확인 후 `task.md` 업데이트
- 예외: Orchestrator의 내부 추론은 worker 호출이 아니므로 승인 불필요

## Verification (결과물 수락 전 필수)

각 worker `result.md`에 포함된 Verification Checklist를 실행하고, 결과를 `log.md`에 `[VERIFICATION]` 태그로 기록.

기본 항목: output이 `brief.md`의 `output_format`과 일치 / 파일 경로가 실제 존재하는지 확인 / `task.md`의 constraints 충족 / Do NOT 항목 위반 없음

## log.md 규칙

- 원칙은 append-only(작업 진행 중에는 수정/삭제 금지).
- 형식: `[YYYY-MM-DD HH:MM] [ACTION] 내용`
- 기록 대상: worker 호출, 주요 결정, verification 결과, 에러
- **정리(pruning) 예외**: task가 `done`으로 완료되고 최근 10개 task에 더 이상 포함되지 않게 되면, 그 task의 `log.md`는 `[COMPLETE]`/`[FINDING]` 태그 항목(+ 태그 무관하게 항상 보존하는 마지막 항목)만 남기고 나머지(`DECISION`/`VERIFICATION`/`ACTION`/`WORKER_CALL` 등 과정 로그)를 삭제해도 된다. 정리 시 파일 상단에 정리 사실과 근거(원본은 git 히스토리에 보존)를 주석으로 남길 것. `_shared/learnings.md`·`_local/learnings.md`도 같은 기준(최근 10개 task 제외)으로 오래된 항목의 **근거**를 짧은 참조 포인터로 축약할 수 있다 — 단 **교훈** 본문은 축약하지 않는다.

## Worker 파일 쓰기 정책

| Worker | 기본 쓰기 권한 | 외부 repo 쓰기 |
|--------|------------|--------------|
| claude-main | ❌ Orchestrator 경유 | ❌ |
| codex-main | ✅ `tasks/<task>/` 내부 산출물·diff | ⚠️ 조건부 (아래 참조) |
| codex-critic | ❌ Orchestrator 경유 | ❌ |
| ollama | ❌ 디스패처 envelope를 Orchestrator가 기록 | ❌ |
| gemini | ❌ MCP 응답을 Orchestrator가 기록 | ❌ |

### `write_scope` 값

`none`(쓰기 금지, codex-critic 기본) / `tasks-only`(`tasks/<task>/` 내부만, codex-main 기본) / `"src/**, tests/**"`형 경로 패턴(외부 repo 해당 경로만 — 아래 4조건 모두 충족 시에만 유효).

### codex-main 외부 repo 쓰기 조건 (모두 충족 필수)

1. `brief.md`에 `target_repo: <절대 경로>` 명시
2. `brief.md`에 `write_scope: <허용 경로 패턴>` 명시
3. `task.md`의 `workers_approved`에 해당 worker + `write_scope` 승인 기록
4. `log.md`에 `[APPROVAL]` 태그로 외부 쓰기 승인 별도 기록

하나라도 누락 → `tasks/<task>/` 내부에만 diff·patch로 산출(사용자가 직접 적용). 직접 쓰기 가능한 worker도 `_shared/`·`_templates/`·다른 작업 폴더는 쓰지 말 것.

## CLAUDE.md 적용 범위

이 파일은 **Claude Code를 `<설치한-폴더>/` 또는 그 하위에서 실행**할 때만 적용됨 (`cd <설치한-폴더> && claude`). 다른 디렉토리에서 실행 시 적용 안 됨 (의도된 격리). 전역 `~/.claude/CLAUDE.md`에 포함하지 말 것 — orchestration 규칙이 다른 프로젝트로 새어나감.

## Codex 전환 모드 (Claude 세션 사용량 소진 시)

**사용자의 명시적 지시가 있을 때만** `_shared/switch-flavor.sh codex --yes`(복귀는 `claude --yes`)로 전환. Orchestrator가 스스로 트리거 금지. `tasks/`·`_local/`은 항상 보존. Codex flavor의 worker pool은 `codex-main(오케스트레이터 자신)·claude-critic·gemini`(`backend-expert`·`frontend-expert` 미포함 — codex-main이 대행). 메커니즘 상세는 스크립트 주석 참조.

<!-- knot:start -->
## knot — 지식 vault (선택)
환경변수 $KNOT_VAULT 가 설정돼 있고 현재 작업이 거기 저장된 지속가치 지식과 관련될 때만:
먼저 $KNOT_VAULT/wiki/ 의 관련 페이지를 참고하고, 새로 알게 된 지속가치 있는 내용은
$KNOT_VAULT/prompts/ingest.md 규약대로 ingest를 고려한다.
$KNOT_VAULT 미설정이거나 무관한 작업에서는 이 절을 무시한다.
<!-- knot:end -->
