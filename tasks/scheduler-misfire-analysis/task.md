# Scheduler — WAS 재기동 시 지나간 스케줄이 즉시 실행되는 원인 분석

## 메타

```yaml
status: done
created: 2026-08-12
updated: 2026-08-12
priority: high
req_id: N/A
```

## Goal

`<target_repo>`의 Scheduler 기능(`QuartzScheduleManager`/`BatchScheduleJob`)에서, 예약된 실행 시각이 이미 지난 뒤 WAS(톰캣)를 재기동하면 그 지나간 스케줄이 재기동 직후 즉시 실행되는 현상의 원인을 코드·Quartz 1.6.0 실제 동작(가능하면 jar 바이트코드/문서로 근거 확보) 기준으로 규명한다.

**[2026-08-12 후속]** 원인 규명 후 사용자가 "수정 진행해줘" 요청 — 원래 분석 전용이었던 이 태스크에 실제 수정 적용을 추가 진행함(아래 constraints의 "읽기 전용"은 분석 단계 한정, 수정 단계는 별도 승인).

## Constraints

- 분석 전용 — A(`<target_repo>`)는 읽기 전용, 수정하지 않음
- 지어낸 사실 금지 — 실제 코드·Quartz 1.6.0(`WebContent/WEB-INF/lib/quartz-1.6.0.jar`) 동작 근거만 사용. 문서 검색보다 `javap`으로 실제 클래스 동작을 직접 확인하는 걸 우선(이전 두 태스크에서 이 방법이 효과적이었음)
- target_repo 아님(읽기만) — 산출물은 이 repo `tasks/` 내부에만 작성

## Context

- 관련 코드는 전부 이전 태스크(`schedule-feature-port`)에서 B(Repos)로부터 A에 포팅한 것 — `context.md` 참조
- Orchestrator 사전 정찰(가설, 검증 필요): `QuartzScheduleManager.buildTrigger()`가 DAILY/WEEKLY용 `CronTrigger`를 생성할 때 misfire instruction을 명시적으로 세팅하지 않아 기본값(SMART_POLICY)에 의존하고, `loadActiveSchedules()`(WAS 기동 시 1회 호출)가 매번 `scheduleOrReplace()` → 기존 job delete 후 트리거를 완전히 새로 만들어 등록하는 구조라, RAMJobStore가 재기동 시 초기화되는 것과 맞물려 "지나간 시각"이 새 트리거의 최초 계산된 fire time으로 잡히고 misfire 처리(SMART_POLICY→CronTrigger는 FIRE_ONCE_NOW로 알려짐)로 즉시 1회 발화하는 것으로 추정됨. `quartz.properties`엔 `org.quartz.jobStore.misfireThreshold = 60000`(60초)만 설정돼 있고 트리거별 misfire instruction 오버라이드는 코드에 없음. START_DATE(START_DATE_COL)는 선택값이라 비어있는 경우 `trigger.setStartTime()` 자체가 호출 안 됨.

## Acceptance Criteria

- [x] `buildTrigger()`가 만드는 `CronTrigger`(DAILY/WEEKLY)와 `SimpleTrigger`(MINUTE/HOURLY) 각각에 대해, misfire instruction 기본값이 실제로 무엇인지 quartz-1.6.0.jar 바이트코드로 확인 — 0(SMART_POLICY), codex-critic 재확인 완료
- [x] 그 기본 misfire instruction이 실제로 "즉시 1회 발화" 동작인지 확인 — CronTrigger는 그렇고(FIRE_ONCE_NOW로 승격), SimpleTrigger(REPEAT_INDEFINITELY)는 아님(instruction=4, 미래 슬롯) — 이 비대칭이 핵심
- [x] `loadActiveSchedules()` → `scheduleOrReplace()` → `buildTrigger()` 흐름 및 START_DATE 유무별 fire time 계산 분석 — CronTrigger 3-인자 생성자가 이미 안전한 startTime(=지금)을 세팅하는데, START_DATE가 있으면 과거로 덮어씀을 확인
- [x] 재현 시나리오(t0~t10 단계별) 및 A/B 실측 제안(재기동 없이 저장 즉시 재현) 완료
- [x] 근본 원인 요약 + 수정 후보 5개 제시(우선순위 포함) — codex-critic이 후보2의 치명적 결함(SimpleTrigger에도 적용돼 새 버그 유발) 발견, Orchestrator가 코드로 재확인
- [x] codex-critic이 분석 내용을 동일 코드·jar로 재검증 — 핵심 원인규명 유효 확인, 후보1은 견고·후보2는 재설계 필요로 최종 정리

## Worker Plan

```yaml
workers_approved:
- worker: claude-main
  approved_at: 2026-08-12
  purpose: WAS 재기동 시 지나간 스케줄 즉시실행 버그의 근본원인 분석(디버깅 원인분석 — strategist 슬롯에 부합)
  approved_by: user
  write_scope: none (분석 텍스트만 반환)
- worker: codex-critic
  approved_at: 2026-08-12
  purpose: claude-main 분석 결과를 동일 코드·jar로 적대적 재검증
  approved_by: user
  write_scope: none

planned_workers:
- role: claude-main
  purpose: 근본원인 분석
- role: codex-critic
  purpose: 분석 비평
```
