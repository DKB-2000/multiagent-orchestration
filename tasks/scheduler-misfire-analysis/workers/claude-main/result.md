# 근본원인 분석 — WAS 재기동 시 지나간 스케줄 즉시 실행

## 1. 근본 원인 (요약)

**DAILY/WEEKLY 스케줄에 START_DATE(START_DATE_COL)가 설정돼 있으면**, `buildTrigger()`가 `CronTrigger` 3-인자 생성자가 이미 넣어둔 `startTime = 현재시각`을 `trigger.setStartTime(START_DATE 00:00)`으로 **과거 시각으로 덮어쓰고**, WAS 기동마다 트리거를 새로 만드는 구조(RAMJobStore + `deleteJob` → `scheduleJob`) 탓에 최초 발화시각이 매번 "과거의 예약시각"으로 계산된다.

그 과거 발화시각을 `RAMJobStore.applyMisfire()`가 misfire로 판정하고, 트리거의 misfire instruction이 명시 세팅 없이 기본값 `SMART_POLICY(0)`이라 `CronTrigger.updateAfterMisfire()`가 이를 **`FIRE_ONCE_NOW(1)`로 승격 → `setNextFireTime(new Date())`** 하므로 기동 직후 1회 즉시 발화한다.

> **Orchestrator 사전 가설의 수정 지점 (중요)**
> task.md/context.md는 "START_DATE가 비어있으면 `setStartTime()`이 스킵된다"는 점을 *부수적 사항*으로 다뤘으나, 바이트코드 확인 결과 **이것이 버그의 필요조건을 가르는 결정적 변수**다. `CronTrigger(name, group, cron)` 생성자가 **내부에서 `setStartTime(new Date())`를 이미 호출**하기 때문에, **START_DATE가 비어 있으면 CronTrigger는 misfire를 일으키지 않는다**(§2-D). 즉 "misfire instruction 기본값이 SMART_POLICY라서"만으로는 증상이 설명되지 않고, **START_DATE ≤ 오늘** 조건이 함께 있어야 한다.

---

## 2. 근거

### 2-0. 검증 환경

| 항목 | 값 |
|---|---|
| 도구 | `javap` 21.0.11 (`java version "21.0.11" 2026-04-21 LTS`) |
| 대상 jar | `<target_repo>\WebContent\WEB-INF\lib\quartz-1.6.0.jar` (421,601 bytes) |
| 명령 | `javap -p -c -constants -cp quartz-1.6.0.jar <class>` |
| 설정 | `WebContent\WEB-INF\classes\quartz.properties` L21 `misfireThreshold = 60000`, L23 `RAMJobStore` (재확인 완료) |

### 2-A. misfire instruction 기본값 = 0 = `MISFIRE_INSTRUCTION_SMART_POLICY` — 확인됨

`javap -p -constants org.quartz.Trigger`:
```
public static final int MISFIRE_INSTRUCTION_SMART_POLICY = 0;
```
`org.quartz.Trigger`의 **모든 생성자**(`()`, `(String,String)`, `(String,String,String,String)`)가 동일하게 필드를 0으로 초기화:
```
31: aload_0
32: iconst_0
33: putfield      #8    // Field misfireInstruction:I
```
`QuartzScheduleManager.buildTrigger()`(L262-309) 전체를 읽은 결과 `setMisfireInstruction` 호출 없음 → **실제 런타임 값은 0(SMART_POLICY)** 확정.

관련 상수 실측값:

| 클래스 | 상수 | 값 |
|---|---|---|
| `Trigger` | `MISFIRE_INSTRUCTION_SMART_POLICY` | **0** |
| `CronTrigger` | `MISFIRE_INSTRUCTION_FIRE_ONCE_NOW` | **1** |
| `CronTrigger` | `MISFIRE_INSTRUCTION_DO_NOTHING` | **2** |
| `SimpleTrigger` | `MISFIRE_INSTRUCTION_FIRE_NOW` | 1 |
| `SimpleTrigger` | `..._RESCHEDULE_NOW_WITH_EXISTING_REPEAT_COUNT` | 2 |
| `SimpleTrigger` | `..._RESCHEDULE_NOW_WITH_REMAINING_REPEAT_COUNT` | 3 |
| `SimpleTrigger` | `..._RESCHEDULE_NEXT_WITH_REMAINING_COUNT` | **4** |
| `SimpleTrigger` | `..._RESCHEDULE_NEXT_WITH_EXISTING_COUNT` | 5 |
| `SimpleTrigger` | `REPEAT_INDEFINITELY` (static{} 초기화 `iconst_m1`) | **-1** |

`Trigger`의 상수 목록 전체를 덤프한 결과 **`MISFIRE_INSTRUCTION_IGNORE_MISFIRE_POLICY`는 1.6.0에 존재하지 않는다** — §2-H와 함께 수정 방향에 영향.

### 2-B. CronTrigger의 SMART_POLICY 실제 동작 = "즉시 1회 발화" — 바이트코드로 확인됨

`CronTrigger.updateAfterMisfire(Calendar)` 바이트코드:
```
 0: invokevirtual getMisfireInstruction:()I
 4: istore_2
 5: iload_2
 6: ifne  11              // instr != 0 이면 11로
 9: iconst_1
10: istore_2              // instr = 0(SMART_POLICY) → 1(FIRE_ONCE_NOW)   ★
11: iload_2
12: iconst_2
13: if_icmpne 66          // instr != 2(DO_NOTHING) 이면 66으로
16-63: nextFireTime = getFireTimeAfter(new Date()) + Calendar 스킵 루프  // DO_NOTHING 분기
66: iload_2
67: iconst_1
68: if_icmpne 82          // instr != 1 이면 종료
71-79: setNextFireTime(new Date())     // ★ FIRE_ONCE_NOW = "지금"으로 세팅 → 즉시 발화
82: return
```
동등 의사코드:
```java
int instr = getMisfireInstruction();
if (instr == 0)              instr = 1;                     // SMART_POLICY → FIRE_ONCE_NOW
if (instr == 2)              setNextFireTime(getFireTimeAfter(new Date()));  // DO_NOTHING
else if (instr == 1)         setNextFireTime(new Date());    // 즉시
```
→ **Acceptance Criteria 2 충족**: "SMART_POLICY가 CronTrigger에서 즉시 1회 발화"는 기억/문서가 아니라 jar 바이트코드로 확인됨.

이어서 `CronTrigger.triggered(Calendar)`:
```
 0-5 : previousFireTime = nextFireTime
 8-17: nextFireTime = getFireTimeAfter(nextFireTime)
```
→ 즉시 발화 후 `nextFireTime`은 정상적으로 다음 cron 슬롯으로 복귀. **"딱 1회만 즉시 실행되고 이후 정상"** 이라는 증상과 정확히 일치.

### 2-C. SimpleTrigger의 SMART_POLICY는 즉시 발화가 **아니다** (MINUTE/HOURLY는 misfire 원인 아님)

`SimpleTrigger.updateAfterMisfire(Calendar)`:
```
 5: iload_2 / 6: ifne 41                       // instr != 0 이면 41
 9: getRepeatCount / 13: ifne 21
16: iconst_1 istore_2  goto 55                 // repeatCount==0  → 1 (FIRE_NOW)
21: getRepeatCount
25: getstatic REPEAT_INDEFINITELY:I            // = -1
28: if_icmpne 36
31: iconst_4 istore_2 goto 55                  // repeatCount==-1 → 4  ★ 본 코드 해당
36: iconst_2 istore_2                          // 그 외 → 2
...
129: if instr==4 →  nextFireTime = getFireTimeAfter(new Date())   // 미래 슬롯. 즉시 아님
```
`buildTrigger()` L271-272는 `SimpleTrigger.REPEAT_INDEFINITELY`(=-1)를 쓰므로 **instr = 4 (RESCHEDULE_NEXT_WITH_REMAINING_COUNT)** → `getFireTimeAfter(now)` → **미래**. 따라서 MINUTE/HOURLY는 misfire로 인한 즉시 발화가 발생하지 않는다.

> 다만 MINUTE/HOURLY에는 **별개의 즉시 실행 경로**가 있다 — §3 표 및 §6 후보 3 참조.

### 2-D. ★ `CronTrigger(String,String,String)` 생성자가 startTime을 "지금"으로 이미 세팅한다

```
 0-3 : super(name, group)
 6-35: cronEx/startTime/endTime/nextFireTime/previousFireTime/timeZone = null
36-38: setCronExpression(arg3)
41-49: setStartTime(new Date())      // ★ 생성 시점이 startTime
52-56: setTimeZone(TimeZone.getDefault())
```
→ `QuartzScheduleManager.java` L286 `new CronTrigger(triggerName, GROUP_NAME, cron)` 직후 `startTime = WAS 기동시각`.
→ L294-297에서 `parsedStart != null`일 때만 `trigger.setStartTime(parsedStart)`로 **덮어쓴다**.
→ **START_DATE가 없으면 startTime은 기동시각으로 남고, 최초 발화시각은 항상 미래 → misfire 불가.**

### 2-E. `computeFirstFireTime`/`getFireTimeAfter`는 "현재시각"으로 클램프하지 않는다

`CronTrigger.computeFirstFireTime(Calendar)`:
```
 0-23: nextFireTime = getFireTimeAfter(new Date(getStartTime().getTime() - 1000L))
26-65: Calendar가 있으면 제외구간 스킵 루프
```
`CronTrigger.getFireTimeAfter(Date)`:
```
12-20: if (getStartTime().after(afterTime))
23-41:     afterTime = new Date(getStartTime().getTime() - 1000L)   // startTime 쪽으로만 끌어올림
42-61: endTime 체크
62-67: pot = getTimeAfter(afterTime)
```
→ `afterTime`을 **startTime 아래로 못 내려가게** 막을 뿐, **`now` 위로 올리는 로직은 없다**. startTime이 과거면 결과도 과거.

`CronTrigger.setStartTime(Date)`:
```
 0-13: null 체크
14-44: endTime < startTime 이면 IllegalArgumentException
45-68: millisecond만 0으로 잘라 필드에 저장
69: return
```
→ **과거 날짜를 거부하지 않고, `nextFireTime`을 재계산하지도 않는다.** 재계산은 `scheduleJob` 안의 `computeFirstFireTime`에서 한 번 일어난다.

`SimpleTrigger.computeFirstFireTime(Calendar)`은 더 단순 — `nextFireTime = getStartTime()` (1초 빼기도 없음).

### 2-F. `RAMJobStore.applyMisfire()` 판정식

```
 0- 3: long misfireTime = System.currentTimeMillis();
 4-19: if (getMisfireThreshold() > 0) misfireTime -= getMisfireThreshold();   // 60000
20-27: Date tnft = tw.trigger.getNextFireTime();
29-40: if (tnft.getTime() > misfireTime) return false;      // 60초 이내면 misfire 아님
41-66: cal = (calendarName != null) ? retrieveCalendar(...) : null;
68-82: signaler.notifyTriggerListenersMisfired(clone)
87-93: tw.trigger.updateAfterMisfire(cal);                  // ★ §2-B로 진입
96-131: nextFireTime == null → state=COMPLETE, timeTriggers에서 제거
142-158: tnft.equals(새 nextFireTime) → return false
159: return true
```
→ **발화 예정시각이 현재보다 60초 넘게 과거면 misfire.** 09:00 예약 / 14:00 기동이면 5시간 → 여유롭게 판정된다.

부수 확인: 1.6.0의 이 메서드에는 **`tnft == null` 체크가 없고**(offset 29에서 바로 `getTime()`), `MISFIRE_INSTRUCTION_IGNORE_MISFIRE_POLICY` 예외 분기도 없다(후속 버전에서 추가된 것).

### 2-G. `RAMJobStore.acquireNextTrigger()` — 즉시 재획득 확인

```
 16-26: tw = timeTriggers.first()
 48-72: nextFireTime == null → 제거 후 재시도
 75-84: timeTriggers.remove(tw)
 85-91: if (applyMisfire(tw)) { ... 105-114: 새 nextFireTime 있으면 다시 add; 118: 처음부터 재시도 }
121-134: if (nextFireTime > noLaterThan) { 다시 add; return null; }
152-188: state = ACQUIRED; setFireInstanceId(...); return (Trigger) tw.trigger.clone();
```
→ misfire 처리(→ `nextFireTime = now`) 후 **루프 재진입**. 두 번째 통과에서는 `now > now - 60000`이라 misfire 아님 → 즉시 획득 → 발화. **한 번의 acquire 사이클 안에서 즉시 실행까지 완결된다.**

### 2-H. `validateMisfireInstruction` 유효범위 (수정 방향 제약)

```
CronTrigger  : if (i < 0) return false; if (i > 2) return false; return true;   // 0..2
SimpleTrigger: if (i < 0) return false; if (i > 5) return false; return true;   // 0..5
```
→ **음수(-1, IGNORE_MISFIRE_POLICY)는 1.6.0에서 사용 불가.** CronTrigger에서 "늦었으면 건너뛰기"의 유일한 선택지는 **`DO_NOTHING(2)`**.

### 2-I. 애플리케이션 측 흐름 재확인 (Acceptance Criteria 3)

`QuartzScheduleManager.java`:
- **L72-87 `contextInitialized()`** — `s.start()`(L76-78)를 **먼저** 호출한 뒤 L81 `loadActiveSchedules()`. 즉 트리거 등록 시점에 스케줄러 스레드가 이미 가동 중.
- **L166 `loadActiveSchedules()`** — `USE_YN='Y'` 전건 조회 → 각 행마다 L184 `scheduleOrReplace(...)`. START_DATE_COL(L181)를 그대로 전달.
- **L218 `scheduleOrReplace()`** — L227 `s.deleteJob(jobName, GROUP_NAME)` → L245 새 `JobDetail` → L249 `buildTrigger()` → L252 `s.scheduleJob(...)`. **이전 트리거 상태를 승계하지 않고 매번 완전히 새로 생성**.
- **L262 `buildTrigger()`** — L271-272 SimpleTrigger(`new Date()` startTime), L286 CronTrigger(3-인자), L294-297 START_DATE로 startTime 덮어쓰기.
- `QuartzScheduler.scheduleJob` 바이트코드 offset 165-171에서 `trigger.computeFirstFireTime(cal)` 호출, 186-189 결과가 null이면 `SchedulerException("Based on configured schedule, the given trigger will never fire.")`, **offset 205 `notifySchedulerThread()`** → 스케줄러 스레드 즉시 각성.
- `RAMJobStore`이므로 재기동 시 `previousFireTime`/`timesTriggered` 등 "이미 09:00에 돌았다"는 정보가 **전부 소실**된다. JDBC JobStore였다면 트리거 상태가 살아남아 이 경로 자체가 달라진다.

`BatchScheduleJob.java` L42-74 `execute()`: **"오늘 이미 실행했는지"·"예정시각과 실제 발화시각의 괴리" 가드가 전혀 없다.** misfire로 넘어온 발화도 그대로 `/rest/batchAnalysis/run?scheduleId=...`를 호출해 전체 COBOL 분석 배치를 태운다 → 증상이 눈에 띄는 이유.

`ScheduleRegistAction.java` **L132-141**: START_DATE는 `^\d{8}$` 형식과 `endDate >= startDate`만 검증한다. **"과거 날짜 금지" 검증이 없다.** L166에서 그대로 `START_DATE_COL`에 저장.

### 2-J. 대조군 — 같은 클래스 안의 CronTrigger 두 개가 다르게 동작한다

`registerExpirySweepJob()` L96의 `new CronTrigger(EXPIRY_JOB_NAME + "_trigger", EXPIRY_GROUP_NAME, "0 5 0 * * ?")`는 **`setStartTime()`을 호출하지 않는다** → startTime = 기동시각 → `computeFirstFireTime` = 다음 00:05(미래) → misfire 없음 → **재기동해도 즉시 실행되지 않는다.**

동일 파일·동일 Quartz 설정·동일 SMART_POLICY 기본값인데 **START_DATE 유무만 다른 두 CronTrigger의 거동이 갈린다**는 점이, 원인을 "SMART_POLICY 그 자체"가 아니라 **"과거 START_DATE로 덮어쓴 startTime"** 으로 지목하는 결정적 대조 근거다. (운영 로그에서 만료 스윕 잡이 재기동 직후 실행되지 않는다면 이 대조가 확증된다.)

---

## 3. START_DATE 유무 × 스케줄 타입 매트릭스 (Acceptance Criteria 3)

기준: 2026-08-12(수) 14:00 WAS 재기동, DAILY 09:00 / MINUTE 10분 간격.

| 타입 | START_DATE | 실제 `startTime` | `computeFirstFireTime()` 결과 | applyMisfire? | 기동 직후 즉시 실행? |
|---|---|---|---|---|---|
| DAILY/WEEKLY | **없음** | 08-12 14:00 (생성자, §2-D) | `getFireTimeAfter(13:59:59)` → **08-13 09:00** (미래) | ✗ | **아니오** (정상) |
| DAILY/WEEKLY | **20260812 (오늘)** | 08-12 **00:00** (덮어씀) | `getFireTimeAfter(08-11 23:59:59)` → **08-12 09:00** (5h 과거) | ✓ | **예 — 버그** |
| DAILY/WEEKLY | **20260801 (과거)** | 08-01 00:00 | `getFireTimeAfter(07-31 23:59:59)` → **08-01 09:00** (11일 과거) | ✓ | **예 — 버그** |
| DAILY/WEEKLY | 20260901 (미래) | 09-01 00:00 | 09-01 09:00 (미래) | ✗ | 아니오 |
| MINUTE/HOURLY | 없음 | 08-12 14:00 (`new Date()`, L272) | `= startTime` = **14:00 = 지금** | ✗ (60초 이내) | **예 — 단, misfire가 아니라 생성자 설계상** |
| MINUTE/HOURLY | 과거 | 과거 00:00 | 과거 00:00 | ✓ | **아니오** (instr=4 → 미래 슬롯, §2-C) |

**주목할 반전**: MINUTE/HOURLY는 START_DATE를 넣으면 즉시 실행이 오히려 **사라지고**, DAILY/WEEKLY는 START_DATE를 넣어야 즉시 실행이 **생긴다**. 이 비대칭이 "어떤 스케줄은 즉시 돌고 어떤 건 안 돈다"는 불규칙한 체감을 만든다.

---

## 4. 재현 시나리오 (Acceptance Criteria 4)

**전제**
- `SCHEDULE_TB` 1건: `SCHEDULE_ID=101`, `USE_YN_COL(USE_YN)='Y'`, `TYPE_COL(TYPE)='DAILY'`, `TIME_COL(TIME)='09:00'`, `START_DATE_COL(START_DATE)='20260801'`, `END_DATE_COL(END_DATE)=''`
- 2026-08-12(수) **14:00** 정각에 톰캣 재기동

| 단계 | 위치 | 일어나는 일 |
|---|---|---|
| t0 | `QuartzScheduleManager.java` L74-78 | `StdSchedulerFactory().getScheduler()` → `quartz.properties` 적용(RAMJobStore, `misfireThreshold=60000`). `s.start()` → **QuartzSchedulerThread 가동**. RAMJobStore는 빈 상태 — 이전 프로세스의 발화 이력 전무. |
| t1 | L81 → L166 | `loadActiveSchedules()`가 `USE_YN='Y'` 조회, scheduleId=101 행에서 `startDate="20260801"` 획득 → L184 `scheduleOrReplace(...)`. |
| t2 | L227 | `s.deleteJob("batchSchedule_101", GROUP_NAME)` — RAMJobStore가 비어 있어 no-op. |
| t3 | L286 | `new CronTrigger("batchSchedule_101_trigger", GROUP_NAME, "0 0 9 * * ?")` → **생성자가 `setStartTime(2026-08-12 14:00:00)`** (§2-D). 이 시점 기준이면 다음 발화는 08-13 09:00으로 정상. |
| t4 | L294-297 | `parseYyyyMmDd("20260801")` = `2026-08-01 00:00:00` (non-null) → **`trigger.setStartTime(2026-08-01 00:00:00)`** — t3의 안전한 값을 **11일 전으로 덮어씀**. `setStartTime`은 과거를 거부하지도, nextFireTime을 재계산하지도 않음(§2-E). misfire instruction은 여전히 **0**(§2-A). |
| t5 | L252 → `QuartzScheduler.scheduleJob` offset 165 | `computeFirstFireTime(null)` → `getFireTimeAfter(2026-07-31 23:59:59)` → `getTimeAfter(...)` → **`nextFireTime = 2026-08-01 09:00:00`**. null이 아니므로 예외 없이 통과 → `storeJobAndTrigger` → offset 205 **`notifySchedulerThread()`**. |
| t6 | `RAMJobStore.acquireNextTrigger` offset 85 | `applyMisfire(tw)`: `misfireTime = 14:00:00.xxx − 60,000ms = 13:59:00`. `tnft = 08-01 09:00` → `tnft.getTime() > misfireTime` **거짓** → misfire 확정. |
| t7 | offset 93 → `CronTrigger.updateAfterMisfire` | `instr = 0` → **`instr = 1` (FIRE_ONCE_NOW)** → `setNextFireTime(new Date())` = **2026-08-12 14:00:00** (§2-B). `applyMisfire` → `true`. |
| t8 | offset 105-118 | 새 `nextFireTime`이 non-null → `timeTriggers`에 재삽입 → **루프 재진입**. 이번엔 `14:00:00 > 13:59:00` → misfire 아님 → `noLaterThan` 이내 → state=ACQUIRED, 트리거 반환. |
| t9 | `BatchScheduleJob.execute()` L42 | **WAS 기동 수 초 내에 `/rest/batchAnalysis/run?scheduleId=101` 호출** → 09:00에 돌았어야 할 COBOL 일괄분석이 14:00에 실행됨. **← 보고된 증상** |
| t10 | `CronTrigger.triggered()` | `previousFireTime = 14:00`, `nextFireTime = getFireTimeAfter(14:00)` = **08-13 09:00** → 이후엔 정상. **"딱 1회 즉시 실행 후 정상화"** 패턴 완성. |

**왜 "지나간 것으로 스킵"되지 않는가** — 세 가지가 동시에 성립하기 때문:
1. RAMJobStore + `deleteJob`→`scheduleJob` 구조상 **"08-01 09:00에 이미 발화했다"는 사실을 기억하는 주체가 없다**. 매 기동이 곧 "이 트리거의 첫 등록"이다.
2. `computeFirstFireTime`은 **startTime 기준**으로만 계산하고 `now`로 클램프하지 않는다(§2-E).
3. misfire instruction 미설정 → 기본 SMART_POLICY → CronTrigger에서는 "건너뛰기"가 아니라 **"지금 한 번 쏴라"** 로 해석된다(§2-B).

### 4-1. 재기동 없이도 재현되는 변형 (가설 검증용 지렛대 — 권장)

`ScheduleRegistAction`(L~180 부근)과 `ScheduleModifyAction`도 저장 직후 동일한 `scheduleOrReplace()`를 호출한다. 따라서 **START_DATE를 오늘 또는 과거로, TIME을 현재보다 이른 시각으로 지정해 저장하면 톰캣 재기동 없이 저장 즉시 1회 발화**해야 한다(예: 지금 14:00 → DAILY 09:00, START_DATE=오늘로 저장 → 저장 직후 실행). 반대로 **START_DATE를 비우면 저장해도 즉시 실행되지 않아야** 한다.

이 A/B가 예상대로 나오면 §1의 원인 규명이 실측으로 확정되고, 어긋나면 §5의 미확인 항목을 먼저 파야 한다. 재기동 없이 몇 분 안에 돌릴 수 있으므로 codex-critic 재검증 또는 후속 수정 태스크의 첫 스텝으로 권장.

---

## 5. 미확인 / 한계 (명시)

1. **START_DATE의 실제 입력 분포·UI 기본값 — 미확인.** `Server`, `Studio` 양쪽 모두에서 스케줄 등록 화면(JSP/JS)을 찾지 못했다(`grep -rln "SCHEDULE_TYPE|SCHEDULE_TIME"` 결과가 Java/DDL만). 화면이 START_DATE를 **오늘 날짜로 자동 채우는지** 여부에 따라 이 버그가 "거의 항상 발생"인지 "가끔 발생"인지가 갈린다. **운영 DB에서 `SELECT SCHEDULE_ID, TYPE_COL, TIME_COL, START_DATE_COL FROM SCHEDULE_TB WHERE USE_YN_COL='Y'` 확인이 다음 단계로 가장 가치 높다.**
2. **모든 증상 사례가 START_DATE 有인지 — 미확인.** 만약 **START_DATE가 비어 있는 DAILY 스케줄에서도** 즉시 실행이 관측된다면 §1은 그 사례를 설명하지 못한다. 그 경우 MINUTE/HOURLY 경로(§3 표 5행) 또는 아래 3번을 의심해야 한다.
3. **`quartz.properties` L51-52의 `framework.schedule.JobIniPlugin` + `com.example.server.schedule.JobInfoLoader` — 미조사.** 같은 `AppScheduler` 인스턴스에 별도 잡을 주입하는 플러그인이며, 본 증상과 무관하다고 단정할 근거를 확보하지 않았다. 위 2번이 관측되면 여기부터 봐야 한다.
4. **런타임 실측은 하지 않았다.** 본 분석은 전부 정적(소스 + jar 바이트코드) 근거다. §4-1이 이를 보완하는 최소비용 실측이다.
5. **`BatchScheduleJob` 실행 이력 테이블 유무 미확인** — 중복 실행 방지를 애플리케이션 레벨에서 걸 수 있는지 판단에 필요하나 조사하지 않았다.

---

## 6. 수정 방향 후보 (실제 수정은 이번 태스크 범위 아님)

### 후보 1 — Cron 트리거에 `MISFIRE_INSTRUCTION_DO_NOTHING` 명시 【권장·핵심】
**위치**: `QuartzScheduleManager.java` **L286 직후** (`trigger = new CronTrigger(...)` 다음 줄)
```java
trigger = new CronTrigger(triggerName, GROUP_NAME, cron);
trigger.setMisfireInstruction(CronTrigger.MISFIRE_INSTRUCTION_DO_NOTHING); // = 2
```
**근거**: §2-B의 `instr == 2` 분기가 `nextFireTime = getFireTimeAfter(new Date())` → 지나간 발화를 버리고 다음 미래 슬롯으로 간다. §2-H로 값 2가 CronTrigger 유효범위(0..2) 내임을 확인. `setMisfireInstruction`은 `Trigger`의 public 메서드(§2-A javap)이므로 캐스팅 불필요.

> ⚠️ **`else` 브랜치(L271-272 SimpleTrigger)에는 절대 같은 값 2를 적용하지 말 것.** SimpleTrigger에서 2는 `RESCHEDULE_NOW_WITH_EXISTING_REPEAT_COUNT`이며, 바이트코드 offset 210-294가 `setStartTime(now); setNextFireTime(now)` — **오히려 즉시 발화시킨다.** 동일 상수값의 의미가 두 트리거 타입 간에 정반대다. MINUTE/HOURLY는 현행 SMART_POLICY(→4, §2-C)가 이미 올바른 동작이므로 **건드리지 않는 것이 맞다.**

### 후보 2 — 과거 START_DATE를 startTime으로 쓰지 않기 【권장·병행】
**위치**: `QuartzScheduleManager.java` **L294-297**
```java
java.util.Date parsedStart = parseYyyyMmDd(startDate);
if (parsedStart != null && parsedStart.after(new java.util.Date())) {
    trigger.setStartTime(parsedStart);   // 미래 시작일일 때만 의미가 있다
}
```
**근거**: START_DATE의 의미는 "이 날짜 이전에는 돌지 마라"인데, **그 날짜가 이미 지났다면 제약으로서 무의미**하다. 반면 그 값을 startTime으로 쓰면 §2-E에 의해 과거 발화시각이 만들어진다. 생략 시 CronTrigger는 생성자 기본값(=지금, §2-D)이 유지되고 SimpleTrigger도 L272에서 이미 `new Date()`이므로 **의미 손실 없이** 문제 경로가 사라진다.
**단독으로도 증상 제거 가능**하지만, 후보 1과 병행해야 `deleteJob` 실패·장시간 GC 정지 등 다른 경로로 생긴 misfire까지 막힌다. **후보 1 + 2 동시 적용을 권장.**

**보완(선택)**: `ScheduleRegistAction.java` **L132-141**의 검증 블록에 "START_DATE는 과거일 수 없다"를 추가하는 방법도 있으나, 기존 DB에 이미 저장된 과거 START_DATE 데이터는 구제하지 못하므로 **후보 2의 대체재가 아니라 부가 조치**다.

### 후보 3 — MINUTE/HOURLY의 기동 직후 1회 실행 (별건, 요구사항 확인 선행)
**위치**: `QuartzScheduleManager.java` **L271-272**
```java
new SimpleTrigger(triggerName, GROUP_NAME, new java.util.Date(), null, REPEAT_INDEFINITELY, repeatIntervalMs)
```
startTime이 "지금"이라 §3 표 5행대로 **WAS 기동 시마다, 그리고 스케줄 저장 시마다 즉시 1회 실행**된다. 이건 misfire가 아니라 코드가 그렇게 쓴 것이다. 원치 않는다면 `new java.util.Date(System.currentTimeMillis() + repeatIntervalMs)`로 첫 발화를 한 주기 뒤로 미루면 된다.
**단, 사용자가 보고한 증상이 MINUTE/HOURLY에도 해당하는지 먼저 확인해야 한다.** "10분마다"류 스케줄에서는 기동 직후 실행이 오히려 기대 동작일 수 있다.

### 후보 4 — RAMJobStore → JDBC JobStore 전환 (근본적, 범위 큼)
**위치**: `WebContent/WEB-INF/classes/quartz.properties` **L23** ↔ **L25-30**(이미 `JobStoreTX` 설정이 주석으로 준비돼 있음)
재기동해도 트리거 상태(`previousFireTime`/`timesTriggered`)가 보존되어 §2-I의 "매번 첫 등록" 전제가 깨진다.
**단, 이것만으로는 불충분하다** — WAS가 실제로 09:00을 넘겨 꺼져 있었다면 misfire는 여전히 발생하고, misfire instruction이 SMART_POLICY인 한 §2-B로 즉시 발화한다. **반드시 후보 1과 병행해야 하며**, QRTZ_* 테이블 DDL·클러스터링 등 부수 작업이 크다. 이번 이슈 해결만이 목적이라면 과잉.

### 후보 5 — `BatchScheduleJob`에 지연 실행 가드 (권장하지 않음)
`BatchScheduleJob.execute()` L42에서 `context.getScheduledFireTime()`과 `getFireTime()`을 비교해 괴리가 크면 스킵하는 방안. **다만 FIRE_ONCE_NOW 경로에서는 `nextFireTime` 자체가 "지금"으로 재설정된 뒤 발화하므로(§2-B t7) 두 값이 거의 같아져 가드가 무력화될 가능성이 높다 — 미검증.** 트리거 레벨(후보 1·2)에서 막는 것이 옳고, 이 방식은 우회책으로도 신뢰도가 낮다.

### 정리

| 후보 | 효과 | 위험 | 권장도 |
|---|---|---|---|
| 1. CronTrigger에 `DO_NOTHING(2)` | DAILY/WEEKLY 즉시발화 차단 | SimpleTrigger 브랜치 오적용 시 역효과(§후보1 경고) | ★★★ |
| 2. 과거 START_DATE를 startTime에 미사용 | 원인 입력 자체 제거 | 낮음 (의미 손실 없음) | ★★★ |
| 3. SimpleTrigger 첫 발화 지연 | MINUTE/HOURLY 기동 즉시실행 제거 | 기대 동작일 수 있음 | ★☆☆ (요구사항 확인 후) |
| 4. JDBC JobStore | 상태 영속화 | 범위 큼, 단독으로 불충분 | ★☆☆ |
| 5. Job 레벨 가드 | — | misfire 경로에서 무력화 추정 | ☆☆☆ |

**최소 변경 권장안: 후보 1 + 후보 2 (`QuartzScheduleManager.java` L286 및 L294-297, 총 3~4줄).** 적용 전 §4-1의 A/B 실측으로 원인을 확정할 것을 권한다.

---

## Verification Checklist

- [x] **output이 brief의 output_format과 일치** — `1) 근본원인 1~2문장 요약`(§1), `2) 근거(jar 바이트코드 확인 결과 포함)`(§2, 10개 항목 전부 `javap` 실측 출력 기반), `3) 재현 시나리오 단계별 설명`(§4, t0~t10 + 재기동 없는 변형), `4) 수정 방향 후보(코드 위치 포함, 실제 수정 안 함)`(§6, 5개 후보 + 파일·라인 명시) 모두 포함.
- [x] **참조한 파일 경로가 실제 존재** — 전부 도구로 존재 확인함(QuartzScheduleManager.java 336줄 전체, BatchScheduleJob.java 99줄 전체, ScheduleRegistAction.java L100-200, quartz.properties 59줄 전체, quartz-1.6.0.jar 421,601 bytes `javap` 성공). 인용한 모든 라인번호는 실제 Read 출력 기준.
- [x] **task.md의 constraints 충족** — A repo 읽기 전용(쓰기 0건), 지어낸 사실 없이 전부 jar 바이트코드 인용, 사전 가설과 어긋난 지점(§2-D)을 기억에 맞추지 않고 바이트코드대로 정정, 산출물 파일 미작성(텍스트로만 반환).
- [x] **Do NOT 항목 위반 없음** — 코드 수정 0건(§6은 제안만), 파일 쓰기 0건, 외부 repo 미변경. 확신 없는 부분은 §5에 미확인 5건으로 명시.
