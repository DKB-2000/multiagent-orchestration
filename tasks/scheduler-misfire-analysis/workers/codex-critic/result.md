## 적대적 재검증 결과

결론: claude-main의 핵심 원인 분석과 주요 바이트코드 인용은 대체로 정확합니다. 다만 수정 후보 2에는 실제 동작을 역전시킬 수 있는 치명적 결함이 있고, "START_DATE가 필요조건"이라는 표현도 조건을 더 엄밀하게 한정해야 합니다.

### 치명적 문제

1. 수정 후보 2는 MINUTE/HOURLY에 즉시 실행을 새로 유발할 수 있음

제안 코드는 공통 블록인 `QuartzScheduleManager.java` 294–297행을 다음처럼 바꿉니다.

```java
if (parsedStart != null && parsedStart.after(new Date())) {
    trigger.setStartTime(parsedStart);
}
```

하지만 이 블록은 CronTrigger뿐 아니라 SimpleTrigger에도 적용됩니다.

현재 MINUTE/HOURLY + 과거 START_DATE의 동작은:
- SimpleTrigger 생성 시 startTime = 지금
- 공통 블록에서 과거 START_DATE로 덮어씀
- 최초 fire time이 과거가 되어 misfire
- SMART_POLICY + repeatCount=-1 → instruction 4
- `getFireTimeAfter(now)`로 다음 미래 슬롯으로 이동
- 따라서 즉시 실행하지 않음

후보 2를 적용하면 과거 START_DATE를 무시하여 생성자의 `startTime=now`가 그대로 유지됩니다. `computeFirstFireTime()`은 그 값을 그대로 nextFireTime으로 사용하므로 MINUTE/HOURLY가 등록·재기동 직후 즉시 실행됩니다.

즉 §6 후보 2의 다음 주장은 틀렸습니다.

> "SimpleTrigger도 L272에서 이미 `new Date()`이므로 의미 손실 없이 문제 경로가 사라진다."

실제로는 §3에서 claude-main 자신이 설명한 비대칭을 뒤집습니다. 후보 2를 적용하려면 최소한 CronTrigger 분기 안으로 한정하거나 타입별 정책을 별도로 정해야 합니다. 따라서 "후보 1 + 2 동시 적용"을 최소 권장안으로 제시한 결론도 그대로 채택하면 안 됩니다.

### 중요하지만 결론을 뒤집지는 않는 문제

2. "START_DATE ≤ 오늘이 필요조건"은 너무 넓고 동시에 절대적임

정확한 조건은 START_DATE의 존재 자체나 단순히 `START_DATE ≤ 오늘`이 아니라:

> `computeFirstFireTime()`이 만든 nextFireTime이 현재시각 − misfireThreshold보다 과거일 것

입니다.

예를 들어 오늘이 START_DATE여도 예약시각이 아직 오지 않았다면 misfire가 아닙니다. WEEKLY는 START_DATE 이후 첫 대상 요일이 아직 미래일 수도 있습니다.

반대로 START_DATE가 없어도 CronTrigger 생성과 실제 등록 사이에 60초를 넘는 정지(장시간 GC, 디버거 정지, 시스템 시계 급변 등)가 발생하면 생성자의 startTime이 과거가 되어 동일 misfire 경로가 가능합니다.

따라서 정상적인 기동 흐름에서 생성 직후 등록된다는 전제 아래에는 "과거 START_DATE로 인해 최초 cron 슬롯이 이미 지났음"이 핵심 입력 조건이 맞지만, 일반적인 논리적 필요조건으로 선언하면 과도합니다.

3. "RAMJobStore가 빈 상태"는 관련 잡에 한정해 표현해야 함

프로세스 재기동으로 이전 런타임 상태가 사라지는 것은 맞습니다. 다만 같은 `AppScheduler`를 플러그인과 다른 리스너가 공유하고, scheduler가 load 전에 시작되므로 `loadActiveSchedules()` 시점에 RAMJobStore 전체가 반드시 비어 있다고 단정할 수는 없습니다.

정확한 표현은 다음에 가깝습니다.

> 이전 프로세스에서 등록된 batchSchedule 잡 상태는 보존되지 않는다. 현재 기동 중 다른 초기화 경로가 이미 등록한 잡은 존재할 수 있다.

이 차이는 근본원인을 뒤집지는 않습니다.

### 경미한 문제

4. t10의 날짜 계산은 예시 시간에 의존함

`triggered()`가 즉시 발화시각을 previousFireTime으로 옮기고 그 뒤의 cron 슬롯을 계산한다는 설명은 맞습니다. 다만 "항상 다음날 09:00"이 아니라 DAILY 14:00 발화 예시에 한정된 결과입니다. WEEKLY나 자정 경계에서는 다른 날짜가 됩니다.

5. 후보 4의 JDBC JobStore 설명은 다소 단순화됨

JDBC JobStore로 바꿔도 현재 코드가 기동 때마다 `deleteJob()` 후 새 트리거를 등록한다면 보존된 트리거 상태를 스스로 삭제합니다. 따라서 단순 전환만으로 "매번 첫 등록 전제가 깨진다"고 보기 어렵습니다. 현재 재등록 구조까지 함께 바꾸지 않는 한 상태 영속화의 효과가 제한됩니다.

"JDBC JobStore 단독으로 불충분"이라는 최종 판단은 맞지만, 그 이유에는 misfire instruction뿐 아니라 명시적인 delete/recreate 구조도 포함해야 합니다.

## 직접 재확인되어 정확한 항목

실제 `quartz-1.6.0.jar`에 `javap -p -c -constants`를 실행해 다음을 확인했습니다.

- `Trigger` 생성자의 `misfireInstruction` 기본값은 0, SMART_POLICY가 맞음.
- `CronTrigger(String,String,String)`은 cron expression 설정 후 `setStartTime(new Date())`를 호출함.
- `CronTrigger.updateAfterMisfire()`는 0을 1로 바꾸고 instruction 1이면 `setNextFireTime(new Date())`를 호출함.
- CronTrigger instruction 2는 DO_NOTHING이며 다음 미래 cron 시각을 계산함.
- `SimpleTrigger.REPEAT_INDEFINITELY`는 -1이고 SMART_POLICY는 instruction 4로 변환됨.
- SimpleTrigger instruction 4는 `getFireTimeAfter(new Date())`를 사용하므로 다음 미래 반복 시각으로 이동함.
- SimpleTrigger instruction 2는 CronTrigger의 2와 의미가 다르며 "NOW" 계열로 재스케줄함. 따라서 후보 1의 상수 오적용 경고는 정확함.
- `RAMJobStore.acquireNextTrigger()`는 `applyMisfire()`가 true이면 갱신된 트리거를 다시 TreeSet에 넣고 루프 처음으로 돌아감.
- `QuartzScheduler.scheduleJob()`은 저장 전에 `computeFirstFireTime()`을 호출하고 저장 후 scheduler thread를 깨움.
- 실제 애플리케이션 코드는 Cron/Simple 어디에도 `setMisfireInstruction()`을 호출하지 않음.
- 소스 라인과 §4 t0–t9 흐름은 대체로 실제 코드와 대응함.
- `BatchScheduleJob.execute()`에는 중복 실행이나 지연 실행을 거르는 가드가 없음.

## 최종 판정

핵심 원인 규명은 유효합니다.

> 과거 START_DATE 때문에 최초 Cron fire time이 이미 지난 시각으로 계산되고, Quartz 1.6.0 CronTrigger의 기본 SMART_POLICY가 이를 FIRE_ONCE_NOW로 처리하여 즉시 실행한다.

다만 수정안은 후보 1, 즉 CronTrigger에만 `MISFIRE_INSTRUCTION_DO_NOTHING`을 명시하는 방향까지는 바이트코드와 논리가 견고합니다. 후보 2는 현재 형태로 적용하면 MINUTE/HOURLY 동작을 바꾸므로 권장안에서 제외하거나 CronTrigger 전용으로 재설계해야 합니다.

---

**[Orchestrator 재검증 2026-08-12]**: 치명적 문제 1을 `QuartzScheduleManager.java` 262-309행 직접 재확인 — 294-297행(parsedStart 처리 블록)이 268-289행의 if/else(SimpleTrigger·CronTrigger 분기) **바깥, 공통 경로**에 위치함을 확인. codex-critic 지적이 정확함.
