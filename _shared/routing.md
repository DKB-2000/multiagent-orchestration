# Worker Routing Rules

## 2층 라우팅 — 안정층/가변층

이 파일의 decision tree는 **작업 유형 → 능력 슬롯**을 정한다(안정층 — 모델 세대가 바뀌어도 유효).
**슬롯 → 담당 배정**의 정본은 `_shared/capability-profile.md`(가변층)다.
신모델 출시·판정 변경 시 **프로필만 갱신**한다 — 이 파일의 슬롯 정의는 손대지 않는다.
아래 트리의 담당명은 현 프로필 배정의 병기(편의 사본)다 — 프로필과 어긋나면 **프로필이 이긴다**.

## Decision Tree

```
작업 성격 파악 → 능력 슬롯 → 담당 (배정 정본: capability-profile.md)
│
├── [engineer·computer-use] 구현 · 테스트 · 로컬 검증 · 브라우저 조작?
│   └── worker 호출 없이 Orchestrator가 직접 진행 (두 슬롯의 기본 담당 = Orchestrator 자신)
│
├── [strategist] 설계 · 아키텍처 · UI/UX 디자인 · 전략 · 문체가 중요한 산출물 · 디버깅 원인 분석?
│   └── claude-main
│
├── [reviewer] 산출물의 독립 리뷰 / 비판적 검증?
│   └── codex-critic (벤더 쿼터 없이 보조 검증만 필요하면 ollama)
│      (critic은 리뷰 대상 산출물이 먼저 있어야 함 — 최초 생성에 직접 라우팅 금지)
│
├── [multimodal] 이미지 · 스크린샷 분석 / 50페이지+ 문서 / 제3자 시각의 검토?
│   └── gemini
│
└── 판단 어려움?
    └── Orchestrator가 먼저 범위를 좁히고, 필요한 worker만 사용자 승인 후 추가
```

## 복합 작업 우선순위

1. **Orchestrator 우선**: 별도 worker 호출 전에 현재 Claude Code 세션의 추론·로컬 도구로 해결 가능한지 판단한다.
2. **최소 worker set**: 필요한 worker만 고른다. 모든 worker를 기본 호출하지 않는다.
3. **선행 의존성 우선**: `codex-critic`은 리뷰 대상 산출물 경로가 먼저 있어야 한다.
4. **검증은 한 번만**: `codex-critic`은 작업당 1회 원칙. 재호출은 검증 실패나 입력 변경 시만.
5. **gemini는 명시적 트리거 시만**: 멀티모달, 긴 문서, 또는 제3자 관점 필요가 명확할 때만.

## 토폴로지 패턴

| 패턴 | 언제 | 이 시스템에서 |
|------|------|---------------|
| Pipeline (순차) | 앞 결과가 뒤 입력 | claude-main -> codex-critic -> Orchestrator 반영 |
| Fan-out/Fan-in (병렬→통합) | 서로 독립된 산출물 여럿을 통합 | claude-main(설계) ∥ gemini(이미지 분석). 통합은 Orchestrator |
| Expert Pool (전문가 선택) | 작업 성격에 맞는 worker만 | decision tree + 최소 worker set |
| Producer-Reviewer (생성+게이트) | 산출물 품질 검증 필요 | claude-main 또는 Orchestrator 생성 -> codex-critic |

**금지**: 같은 입력에 같은 종류 worker 동시 호출.
**배제**: 별도 long-lived supervisor worker나 worker가 worker를 부르는 재귀 위임 계층은 쓰지 않는다. 단일 Orchestrator, worker간 무통신, file-as-memory 원칙과 충돌한다.

### Fan-in 규칙

1. 각 worker 원문을 `result.md`에 그대로 보존한다.
2. 결과가 충돌하면 삭제하지 말고 양쪽 출처를 병기한 뒤, 권위 우선순위와 사실검증으로 해소한다.
3. 통합 결론 한 줄을 `context.md`에 기록하고, 근거를 `log.md` `[DECISION]`에 남긴다.

## Worker 역할 상세

### claude-main

- **슬롯**: strategist
- **용도**: 기획, 설계 문서, 아키텍처, 전략 수립, UI/UX 디자인 방향, 문체가 중요한 글쓰기, 디버깅 원인 분석.
- **결과물**: 설계 문서, 계획, 분석 텍스트, 텍스트로 반환된 코드·diff.
- **호출 방식**: `_shared/backends.json`의 `claude-main`(native) — Claude Code 서브에이전트(`.claude/agents/claude-main.md`)에 brief를 prompt로 전달.
- **쓰기 권한**: 없음. Orchestrator가 응답을 `result.md`에 기록한다.

### codex-critic

- **슬롯**: reviewer
- **용도**: Orchestrator 또는 `claude-main` 산출물의 독립 리뷰·비평. 실현 가능성, 테스트 커버리지, 사이드 이펙트, 누락 요구사항을 adversarial하게 점검한다.
- **선행 조건**: 리뷰 대상 산출물 경로가 존재해야 한다. 대상은 `claude-main result.md`, Orchestrator 작성 문서, 기존 코드·문서·소스 등 brief에 명시된 파일일 수 있다.
- **결과물**: 중요도별 비평 리스트, 수정 제안, 수락/보류 판단 근거.
- **호출 방식**: `_shared/backends.json`의 `codex-critic` — MCP `mcp__codex__codex`(read-only sandbox). MCP 연결 실패 시 `codex exec --sandbox read-only -`(stdin으로 brief)로 Orchestrator가 직접 호출.
- **쓰기 권한**: 없음. Orchestrator가 응답을 `result.md`에 기록한다.
- **brief 필수 필드**: `target_repo` 또는 리뷰 대상 경로, `write_scope: none`, "비평 모드" 명시.

### ollama

- **슬롯**: reviewer (보조)
- **용도**: 벤더 쿼터 없이 돌리는 셀프 호스팅 보조 검증. codex-critic을 대체하는 주 리뷰어가 아니다.
- **호출 방식**: `bash _shared/adapters/call_worker.sh ollama <brief-file>` → JSON envelope. 백엔드는 `adapters/ollama_api.sh`(env `OLLAMA_HOST`·`OLLAMA_MODEL`).
- **쓰기 권한**: 없음. Orchestrator가 envelope를 `result.md`에 기록한다.

### gemini

- **슬롯**: multimodal
- **용도**: 이미지/스크린샷/다이어그램 분석, 50페이지 이상 문서 스캔, 제3자 시각의 검토.
- **결과물**: 분석 텍스트, 요약, 검토 의견.
- **호출 방식**: `_shared/backends.json`의 `gemini`가 정본 — 백엔드 = Antigravity `agy` CLI, 디스패처 `bash _shared/adapters/call_worker.sh gemini <brief-file>`(결과 JSON envelope). 기본 `gemini-3.1-pro-high`, 빠른 경로 `gemini-3-flash`/`pro-low`, 폴백 없음(아래 폴백 조건). 옛 `mcp__gemini-pro__*` 프록시 브리지 폐기.
- **소스·다중파일 검토는 packet 동봉 필수**: 소스 코드 발굴·검토를 시킬 땐 **디렉토리나 다수 파일 순회를 시키지 말 것** — agy 헤드리스가 300s 타임아웃(exit 124)으로 실패한다(2026-07-04 실측, 자료 동봉 재호출 = 27s exit 0). 필요한 스니펫은 brief에 인라인하지 말고(brief 한도·inline 금지 유지) `tasks/<task>/sources/gemini-packet.md`에 담아 **디스패처 3번째 인자로 동봉**한다: `call_worker.sh gemini <brief> <packet>` — 디스패처가 brief 뒤에 "동봉 자료" 헤더로 결합(`--merged-preview`로 사전 확인). brief에는 "동봉 자료만 사용, 파일 열지 말 것"을 명시. 단일 이미지/PDF 경로 참조는 예외. 시간 제한 작업에서 gemini에 의존하기 전 경량 스모크 1회로 가용성부터 확인.
- **폴백 조건**: api 폴백 슬롯(`adapters/gemini_api.sh`)은 **미구현·비활성**(키가 있어도 무조건 exit 4). backends.json `fallbacks`에서 제거됨(거짓 안전신호 방지). agy(primary) 실패 시 폴백 없이 실패한다(사유는 envelope `stderr_sanitized`). Gemini REST 호출 구현 후에만 fallbacks 재등록.
- **쓰기 권한**: 없음. Orchestrator가 응답을 `result.md`에 기록한다.

## 모델 정책

- **Claude Code Orchestrator**: 현재 세션의 모델과 설정을 따른다.
- **claude-main**: 서브에이전트 정의의 별칭 모델(`opus`)을 사용한다. repo 문서에 버전 문자열을 핀하지 않는다.
- **codex-critic**: 현재 Codex 환경의 기본 모델을 사용한다. 버전 문자열은 환경 소유 사실이므로 repo에 핀하지 않는다.
- **ollama**: `OLLAMA_MODEL` env(기본 `gemma3`)를 따른다.
- **gemini**: 백엔드 = Antigravity `agy` CLI(`backends.json` 정본), 기본 `gemini-3.1-pro-high`(agy에선 정상 — 옛 프록시 400은 비해당), 빠른 경로 `gemini-3-flash`/`pro-low`. agy 모델은 전역·계정단위(`/model`)라 gemini 전용 전역을 pro-high로 둔다. 옛 `mcp__gemini-pro__*` 브리지 폐기.

## 최소 Worker Set

| 작업 유형 | 권장 최소 set |
|-----------|---------------|
| 작고 명확한 구현/문서 | worker 없음, Orchestrator 직접 처리 |
| 설계·전략·문체 중심 산출물 | claude-main |
| 설계 + 독립 비평 | claude-main -> codex-critic |
| Orchestrator 산출물 리뷰 | codex-critic |
| 대용량 문서/이미지 분석 | gemini |
| 전체 검토 | codex-critic, 필요 시 gemini |

## Worker 추가 조건

- 기존 결과로 해결 가능하면 추가 호출 금지.
- 이전 결과가 검증 미통과이거나 입력이 바뀐 경우에만 동일 worker 재호출.
- `codex-critic`과 `gemini`는 외부/유료 모델이므로 매 호출 전 승인 경계를 분명히 한다.

## write_scope 값

`none | tasks-only | "src/**, tests/**" 같은 패턴`. `tasks-only`는 `tasks/<task>/` 내부만 쓰는 값이다. 이 공개 워커 풀은 모두 `none`(Orchestrator가 결과를 기록)이며, 외부 repo 쓰기 4조건은 `CLAUDE.md`가 정본이다.
