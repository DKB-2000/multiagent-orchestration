# Brief — claude-main

## Objective
`tasks/scheduler-misfire-analysis/task.md`, `context.md`를 먼저 읽고, WAS(톰캣) 재기동 시 이미 지나간 예약 스케줄이 즉시 실행되는 버그의 근본 원인을 규명한다. 지어낸 사실 금지 — 코드와 Quartz 1.6.0 실제 동작만 근거.

## Input
- 대상 코드: `<target_repo>\src\com\example\app\schedule\QuartzScheduleManager.java`, `BatchScheduleJob.java`
- Quartz 바이너리: `<target_repo>\WebContent\WEB-INF\lib\quartz-1.6.0.jar` — `javap -p -c`로 `org.quartz.CronTrigger`(또는 `CronTriggerImpl`), `org.quartz.SimpleTrigger`, `org.quartz.Trigger`의 misfire instruction 관련 메서드(`getMisfireInstruction`, `updateAfterMisfire`, `computeFirstFireTime`, `MISFIRE_INSTRUCTION_SMART_POLICY` 등 상수)를 직접 열어 실제 기본값·동작을 확인할 것. 문서/기억에 의존하지 말 것.
- `quartz.properties`: `misfireThreshold = 60000`, `RAMJobStore` 확인됨(context.md 참조)

## 확인할 것
1. `buildTrigger()`의 CronTrigger(DAILY/WEEKLY)와 SimpleTrigger(MINUTE/HOURLY) 각각 misfire instruction을 명시 세팅 안 하면 실제 기본값이 뭔지, 그 기본값의 동작(특히 CronTrigger의 SMART_POLICY가 실제로 "즉시 1회 발화" 인지)을 jar 바이트코드로 확인
2. `loadActiveSchedules()`(WAS 기동 1회) → `scheduleOrReplace()`(delete+새 트리거로 재등록) 구조가 RAMJobStore(재기동시 초기화)와 맞물려 왜 "지나간 시각"을 misfire로 만드는지 단계별 추적
3. START_DATE(START_DATE_COL) 설정 유무가 최초 fire time 계산에 미치는 영향(둘 다 검토 — 있을 때/없을 때)
4. 구체적 재현 시나리오 1개(예: 매일 09:00 DAILY 스케줄, 14:00에 WAS 재기동) 단계별 설명

## Constraints
- A는 읽기 전용, 수정 금지.
- 추측이 아니라 jar 바이트코드/코드 근거로 결론 낼 것. 확신 없는 부분은 "미확인" 명시.

## Output Format
`result.md`에: 1) 근본원인 1~2문장 요약, 2) 근거(jar 바이트코드 확인 결과 포함), 3) 재현 시나리오 단계별 설명, 4) 수정 방향 후보(코드 위치 포함, 실제 수정은 안 함).
