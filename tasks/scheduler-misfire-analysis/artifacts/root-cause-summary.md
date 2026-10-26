# WAS 재기동 시 지나간 스케줄 즉시 실행 — 근본원인 요약

## 결론

`SCHEDULE_TB`에 **START_DATE(START_DATE_COL)가 설정된 DAILY/WEEKLY 스케줄**이 대상. `QuartzScheduleManager.buildTrigger()`(`QuartzScheduleManager.java` 262행)에서:

1. `new CronTrigger(name, group, cron)`(286행) 생성자가 이미 안전한 `startTime = 생성 시점(=WAS 기동시각)`을 세팅함
2. 그런데 바로 아래 294-297행에서 `START_DATE`가 있으면 `trigger.setStartTime(parsedStart)`로 이걸 **과거 날짜로 덮어씀**
3. Quartz가 계산하는 최초 발화시각이 "과거의 그 예약시각"이 되고, WAS 기동마다 트리거를 완전히 새로 만드는 구조(RAMJobStore + `deleteJob`→`scheduleJob`, 이전 실행 이력이 전혀 안 남음)라 매번 이 계산이 반복됨
4. 트리거에 misfire instruction을 명시적으로 설정한 코드가 없어 기본값 `SMART_POLICY(0)`를 쓰는데, **CronTrigger의 SMART_POLICY는 실제로 "즉시 1회 발화"(FIRE_ONCE_NOW)로 동작**(quartz-1.6.0.jar 바이트코드로 확인) → WAS 기동 직후 지나간 스케줄이 1회 실행되고, 그 다음부터는 정상 주기로 돌아감

**대조 확인**: 같은 클래스의 만료 스윕 잡(`registerExpirySweepJob()`)은 `setStartTime()`을 아예 안 불러서 이 버그에 안 걸림 — START_DATE 유무가 결정적 변수라는 근거.

**MINUTE/HOURLY(SimpleTrigger)는 이 경로에 해당 안 됨** — misfire 시 instruction이 다르게 해석돼(4번, "다음 미래 슬롯으로") 즉시 발화하지 않음.

## 검증

claude-main이 quartz-1.6.0.jar를 `javap -p -c -constants`로 직접 열어 misfire instruction 상수값·`updateAfterMisfire`/`computeFirstFireTime`/`getFireTimeAfter`/`RAMJobStore.applyMisfire` 바이트코드를 전부 확인. codex-critic이 동일 방법으로 재검증해 핵심 결론(위 1~4)이 유효함을 확인.

## codex-critic이 잡은 오류 1건 (중요)

claude-main이 제시한 수정 후보 중 "START_DATE가 미래일 때만 setStartTime 호출"(294-297행 조건 추가)은, 이 코드가 CronTrigger/SimpleTrigger 공통 경로라 **MINUTE/HOURLY에도 똑같이 적용돼 오히려 새로운 즉시실행 버그를 만든다** — 지금은 SimpleTrigger가 과거 START_DATE를 받아도 안전하게 미래로 넘어가는데, 이 수정을 그대로 적용하면 그 안전장치가 사라짐. Orchestrator가 코드를 직접 재확인해 이 지적이 정확함을 확인했습니다.

## 수정 적용 완료 (2026-08-12)

`QuartzScheduleManager.java` `buildTrigger()`의 CronTrigger 분기(`trigger = new CronTrigger(...)` 직후)에 아래 1줄 추가:

```java
trigger.setMisfireInstruction(CronTrigger.MISFIRE_INSTRUCTION_DO_NOTHING);
```

misfire로 판정된 지나간 발화를 버리고 다음 정상 cron 슬롯으로만 넘어가게 함. SimpleTrigger(MINUTE/HOURLY) 분기는 전혀 건드리지 않음 — 후보2(공통 코드 수정)는 codex-critic이 SimpleTrigger에도 적용돼 위험하다고 지적해 채택하지 않음.

codex-critic이 실제 적용된 코드를 직접 읽고 최종 확인: CronTrigger 분기 안에만 있어 SimpleTrigger의 misfire 정책(기존 동작 유지)에 영향 없음, 상수 2의 의미충돌(SimpleTrigger에서는 다른 뜻)도 발생하지 않음.

**한계**: 이 수정은 "misfire threshold(60초)보다 과거가 된 경우"에 대한 해결이다. MINUTE/HOURLY에서 별도의 즉시실행 증상이 보고된다면(사용자가 보고한 증상과는 다름, 아래 참고) 원인이 다르다.

### 참고 — 손대지 않은 별개 사항

MINUTE/HOURLY(SimpleTrigger)는 `new java.util.Date()`를 시작시각으로 쓰는 코드 자체 때문에, 스케줄 저장 직후·WAS 재기동 직후 항상 1회 즉시 실행된다(misfire가 아니라 설계상 동작). 이번에 보고된 "지나간 스케줄이 실행됨" 증상과는 무관하고, "몇 분/시간마다"류 스케줄에서는 오히려 기대되는 동작일 수 있어 이번 수정에서 건드리지 않았다. 필요하면 별도로 확인 요청 바람.

## 미확인 사항 (다음 확인 시 유용)

- 실제 운영 DB에서 문제가 재현된 스케줄들의 START_DATE가 실제로 설정돼 있었는지(`SELECT SCHEDULE_ID, TYPE_COL, TIME_COL, START_DATE_COL FROM SCHEDULE_TB WHERE USE_YN_COL='Y'`)
- MINUTE/HOURLY 스케줄에서도 같은 증상이 있었는지(있다면 이 분석이 전체를 설명 못 함 — 별도 원인)
- 재기동 없이 "START_DATE=오늘, 시각=현재보다 이전"으로 저장만 해도 즉시 1회 실행되는지 실측(재현 확정에 가장 저렴한 방법)
