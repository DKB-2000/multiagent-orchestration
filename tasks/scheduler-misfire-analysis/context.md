# Context — scheduler-misfire-analysis

- 대상 코드: `<target_repo>\src\com\example\app\schedule\QuartzScheduleManager.java`(트리거 생성·기동시 재적재), `BatchScheduleJob.java`(실제 실행 Job), `WebContent\WEB-INF\classes\quartz.properties`(RAMJobStore, misfireThreshold=60000), `WebContent\WEB-INF\lib\quartz-1.6.0.jar`(Quartz 1.6.0 실제 바이너리 — 여기서 CronTrigger/SimpleTrigger의 misfire 기본동작을 javap으로 직접 확인할 것).
- `QuartzScheduleManager.buildTrigger()`(262행 부근): DAILY/WEEKLY는 `new CronTrigger(name, group, cron)` 3-인자 생성자, MINUTE/HOURLY는 `new SimpleTrigger(name, group, new Date(), null, REPEAT_INDEFINITELY, intervalMs)`. 둘 다 misfire instruction을 명시적으로 세팅하는 코드 없음(`setMisfireInstruction` 호출 grep 결과 0건).
- `loadActiveSchedules()`(166행): `contextInitialized()`(WAS 기동시 1회) → `USE_YN='Y'`인 스케줄 전부 조회 → 각각 `scheduleOrReplace()` 호출.
- `scheduleOrReplace()`(218행): `s.deleteJob(...)`으로 기존 등록 삭제 후 `buildTrigger()`로 **완전히 새로운 트리거 객체**를 만들어 `s.scheduleJob()`. 즉 재기동 시 이전 트리거 상태를 이어받는 게 아니라 매번 새로 계산.
- `ScheduleRegistAction.java`: START_DATE(START_DATE_COL)는 선택값, 비어있으면 `""` 그대로 DB에 저장 → `buildTrigger()`의 `parseYyyyMmDd(startDate)`가 null 반환 → `trigger.setStartTime()` 호출 자체가 스킵됨.
- 이 태스크는 순수 분석(원인 규명)만 한다. 수정은 사용자 승인 후 별도 진행.
