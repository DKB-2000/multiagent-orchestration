# Brief — codex-critic

## Objective
claude-main의 근본원인 분석(`workers/claude-main/result.md`)을 동일 코드·Quartz jar로 적대적 재검증한다. 읽기 전용 — 아무것도 수정하지 말 것.

## Input
- 분석 대상: `tasks/scheduler-misfire-analysis/workers/claude-main/result.md`
- 코드: `<target_repo>\src\com\example\app\schedule\QuartzScheduleManager.java`, `BatchScheduleJob.java`, `src\com\example\app\actions\cobol\ScheduleRegistAction.java`
- jar: `<target_repo>\WebContent\WEB-INF\lib\quartz-1.6.0.jar`

## 확인할 것
1. §2의 바이트코드 인용(특히 `CronTrigger.updateAfterMisfire`, `CronTrigger` 3-인자 생성자가 `setStartTime(new Date())`를 호출한다는 §2-D 주장, `RAMJobStore.applyMisfire`/`acquireNextTrigger`)이 실제 jar와 일치하는지 `javap -p -c -constants`로 직접 재확인
2. "misfire instruction 기본값만으로는 불충분하고 START_DATE 설정이 필요조건"이라는 §1의 핵심 결론이 논리적으로/바이트코드로 맞는지
3. §3 매트릭스, §4 재현 시나리오(t0~t10)의 각 단계가 코드 라인과 실제로 대응하는지
4. §6 수정 후보들(특히 후보1의 "SimpleTrigger에 같은 상수 2를 쓰면 안 된다" 경고)이 정확한지
5. claude-main이 놓쳤을 수 있는 반례나 논리적 허점(예: §5에 명시된 미확인 항목 중 실제로 결론을 뒤집을 만한 것이 있는지)

## Constraints
- 코드/jar 어느 것도 수정 금지, read-only 비평.
- 지어낸 사실 금지 — 실제 재확인 근거로만 지적.

## Output
발견한 문제를 우선순위(치명적/경미)로 정리. 분석이 정확하면 "이상 없음"과 재확인한 항목을 명시.
