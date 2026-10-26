# codex-main 리뷰 결과 (mcp__codex__codex, thread 01a0b1ef-caa6-7b72-81a1-d2afdda7132e)

호출 방식: `mcp__codex__codex` 직접 호출(native, `call_worker.sh` 디스패처 미경유), read-only sandbox, `cwd=<repo>`.

1차 호출은 PowerShell 프로세스 생성이 `CreateProcessAsUserW failed: 5 (액세스 거부)`로 막혀 파일을 직접 못 읽었음(배경 설명만으로 일반론적 위험만 답변). `mcp__codex__codex-reply`로 5개 파일의 실제 코드를 프롬프트에 인라인해서 재요청 → 아래는 그 최종 답변 원문.

---

## 종합 판단

변경 의도는 타당하고, 정상적인 단일 UI 스레드·MDI 활성화 흐름에서는 동작할 가능성이 높습니다. 다만 현재 구현은 "활성 MDI 전환 콜백이 언제나 먼저 실행된다"는 외부 불변조건에 크게 의존합니다. 특히 창 종료 시 델리게이트 정리가 없고, 폐기된 컨트롤 검사도 없어 수명 관련 회귀 위험이 있습니다.

## 치명적

### 1. `CurrentLine` getter가 무한 재귀합니다

파일: `QueryEditorControl.cs:296` 부근

```csharp
get { return this.CurrentLine; }
```

호출 즉시 `StackOverflowException`이 발생하며 일반적인 `try/catch`로 복구할 수도 없습니다. 올바른 대상은 명백히 `ecQuery.CurrentLine`입니다.

현재 붙여준 코드에서는 직접적인 getter 호출은 보이지 않습니다. `FlowView`는 setter만 사용합니다. 그러나 다음 경우에는 암묵적으로 getter가 호출될 수 있습니다.

- `ISourceEditor.CurrentLine`을 읽는 다른 구현 독립 코드
- PropertyGrid나 데이터 바인딩
- 디버깅/진단 코드의 속성 평가
- 향후 `CurrentLine += n` 같은 코드
- 리플렉션 기반 상태 저장

이번 변경에서 생긴 회귀는 아니지만, 공개 인터페이스 구현이므로 "현재 호출자가 없어 안전하다"고 간주하기 어렵습니다.

## 높음

### 2. 델리게이트는 누적되지 않지만, 마지막으로 설정된 MDI 창을 가리킬 뿐입니다

파일: `FlowAndSourceContent.cs:148-158`

```csharp
_ruleRefControl.EnsureSourceControlReady = this.InitSourceControl;
```

`+=` 이벤트가 아니라 단일 `Action` 대입이므로 이전 `FlowAndSourceContent` 핸들러가 계속 누적되는 문제는 없습니다. 새 대입이 발생하면 이전 인스턴스에 대한 델리게이트 참조도 해제됩니다. 이 선택 자체는 합리적입니다.

그러나 이것이 "활성 MDI 창을 항상 가리킨다"는 것을 자체적으로 보장하지는 않습니다. 실제 의미는 다음과 같습니다.

> `RuleRefControl`은 가장 최근에 `RuleRefControl` 세터가 실행된 `FlowAndSourceContent`를 가리킨다.

따라서 안전성은 `frmMain`이 아래 모든 상황에서 세터를 정확히 다시 호출하는지에 달려 있습니다.

- MDI 자식 활성화
- 이미 활성화된 창을 다시 선택
- 활성 창 닫힘 후 다음 창으로 전환
- 창 생성 도중 또는 종료 도중 RuleRef 트리 조작
- Rule/PGM처럼 서로 다른 편집기 타입 사이 전환
- 활성 MDI 자식이 없는 상태

일반적인 WinForms UI 이벤트는 같은 UI 스레드에서 순차 실행되므로 두 활성화가 동시에 경합하는 문제는 거의 없습니다. 핵심 위험은 동시성보다 **이벤트 순서와 누락**입니다.

### 3. 닫힌 `FlowAndSourceContent`가 델리게이트에 남을 수 있습니다

파일: `FlowAndSourceContent.cs:148-158`, `RuleRefControl.cs:579`

창이 닫힐 때 다음과 같은 해제가 없습니다.

```csharp
if (_ruleRefControl.EnsureSourceControlReady == ...)
    _ruleRefControl.EnsureSourceControlReady = null;
```

따라서 다음 MDI 활성화가 세터를 덮어쓰기 전까지 싱글턴 `RuleRefControl`이 폐기된 `FlowAndSourceContent`를 강하게 참조할 수 있습니다.

영향은 두 가지입니다.

- 닫힌 편집기 객체가 GC되지 않는 일시적 또는 장기 메모리 보존
- `OpenSource()`가 폐기된 객체의 `InitSourceControl()`을 호출하여 예외 발생

특히 `OpenSource()` 첫 줄의 델리게이트 호출은 `try/catch` 바깥입니다.

```csharp
this.EnsureSourceControlReady?.Invoke();
```

폐기된 `splitContainer.Panel2.Controls`에 새 컨트롤을 추가하려 하거나 이미 폐기 중인 컨트롤을 조작하면 예외가 사용자 동작까지 전파될 수 있습니다.

다음 MDI 창 활성화가 반드시 즉시 세터를 호출한다면 노출 구간은 짧지만, 활성 창이 하나뿐인 상태에서 그 창을 닫거나 애플리케이션 종료 과정이라면 보장이 약합니다.

### 4. 초기화 호출 후 `sourceControl.IsDisposed`를 확인하지 않습니다

파일: `RuleRefControl.cs:579-580`

```csharp
this.EnsureSourceControlReady?.Invoke();
if (this.sourceControl == null) return;
```

null 여부만 확인하며 다음 상태는 통과합니다.

- `sourceControl.IsDisposed == true`
- `sourceControl.Disposing == true`
- 컨트롤은 존재하지만 소유 `FlowAndSourceContent`가 폐기 중
- 콜백과 `sourceControl`이 서로 다른 MDI 인스턴스를 가리키는 상태

이후의 `SqlText`, `HighlightLine` 호출은 각각 빈 catch로 삼켜지지만, 잘못된 창이 표시되거나 아무 일도 일어나지 않는 현상이 생깁니다. `EnsureSourcePaneVisibleAndSplitHalf`와 `focusToFlowAndSourceContent` 역시 같은 MDI 대상을 가리킨다는 보장이 필요합니다.

### 5. `OpenSource()`의 빈 catch들이 실제 실패를 완전히 은폐합니다

파일: `RuleRefControl.cs:611-643`

다음 작업의 실패가 모두 무시됩니다.

- 버전별 소스 조회
- `SqlText` 할당
- 줄 강조
- 소스 패널 표시
- 편집기 포커스 전환

특히 현재 문제처럼 UI 수명과 초기화 순서가 중요한 코드에서 빈 catch는 회귀를 "동작하지 않음"으로만 보이게 만듭니다. `Exception ex` 변수도 사용하지 않으므로 경고 또는 정적 분석 지적 대상입니다.

사용자가 언급한 로깅 제거는 명확한 진단성 회귀입니다. `Console.WriteLine`도 WinForms 배포 환경에서는 보이지 않을 수 있으므로 프로젝트의 기존 로거가 있다면 그것을 사용하는 편이 적합하지만, 적어도 예외를 완전히 버리지는 않아야 합니다.

## 중간

### 6. 문서 교체 시 `_lineHighlightBandLine`은 초기화되지 않습니다

파일: `QueryEditorControl.cs:310-329`, 관련 호출: `RuleRefControl.cs:626-634`

`SqlText`로 새 문서를 넣어도 `_lineHighlightBandLine`에는 이전 문서의 줄 번호가 남습니다. 다음 `HighlightLine()`에서 `ecQuery.RemoveLineBackColor(oldLine)`를 새 문서에 대해 호출하게 됩니다.

가능한 결과는 Syncfusion 버전에 따라 달라집니다.

- 새 문서에도 같은 줄 번호가 있으면 그 줄의 배경 설정을 제거
- 새 문서의 줄 수보다 크면 예외 또는 무시
- 문서 교체로 내부 line-format 테이블이 초기화됐다면 실질적인 no-op

더 중요한 잔존 사례는 새 `SRCPOSITION`의 줄 번호 파싱이 실패하는 경우입니다. `HighlightLine()`이 호출되지 않으므로 기존 필드와 기존 강조가 그대로 남을 수 있습니다.

따라서 현재 필드는 "빠르게 여러 줄을 이동"하는 정상 흐름에서는 잘 정리되지만, 다음 경계에서는 안전하지 않습니다.

- `SqlText` 교체
- 빈 문서 로드
- 줄 수 감소
- 줄 번호 파싱 실패
- 강조 적용 중 예외
- 컨트롤 재생성

### 7. 하이라이트 교체 도중 예외가 나면 상태가 불완전해집니다

파일: `QueryEditorControl.cs:316-329`

현재 순서: (1) 이전 줄 배경 제거 → (2) 필드를 null로 설정 → (3) selection 배경 제거 → (4) 새 줄 배경 설정 → (5) 필드에 새 줄 기록.

실패 시 잘못된 새 줄을 기록하지 않는다는 점에서는 좋지만, `SetLineBackColor`가 실패하면 이전 강조는 이미 사라지고 필드는 null이 됩니다. 호출자가 예외를 빈 catch로 삼키므로 사용자는 아무 강조도 나타나지 않는 이유를 알 수 없습니다.

### 8. 줄 번호 유효성 검사가 없습니다

파일: `QueryEditorControl.cs:312-342`, `RuleRefControl.cs:630-634`

`int.TryParse` 성공만 확인하며 `0`, 음수, 현재 문서의 전체 줄 수보다 큰 값도 통과합니다. `CurrentLine`과 `SetLineBackColor`가 범위를 clamp하는지 예외를 던지는지는 Syncfusion 버전에 의존합니다. `RuleRefControl`에서는 예외가 빈 catch로 사라집니다.

### 9. `RemoveLineBackColor`가 다른 기능의 배경색까지 제거할 수 있습니다

파일: `QueryEditorControl.cs:319`

이 API가 해당 줄에 설정된 "현재 기능의 포맷 하나"가 아니라 줄 배경색 전체를 제거하는 API라면, 디버거 현재 줄/오류·경고 줄/검색 결과/다른 기능이 설정한 줄 배경과 충돌할 수 있습니다. 현재 구현에는 강조 소유권을 구분할 토큰이나 원래 배경 복원이 없습니다. 동일 EditControl에서 다른 코드도 `SetLineBackColor`를 쓰는지 전체 검색 필요.

### 10. `CurrentLine` 중복 할당은 현재 코드에서는 사실상 불필요합니다

파일: `FlowView.cs:13466-13468`

`SelectLine()`이 바로 `ScrollToLineWithContext()`를 호출하므로 최종 위치와 스크롤 처리는 다시 수행됩니다. `QueryEditorControl.CurrentLine` setter 자체도 동일한 +100 트릭을 또 실행합니다. 결과적으로 한 번 열 때 불필요한 라인 이동이 여러 번 발생합니다. 현재 보이는 코드만 기준으로는 앞의 두 `CurrentLine` 대입은 제거해도 최종 동작이 유지됩니다. 다만 `CurrentLine` 변경 이벤트를 다른 코드가 구독하는지, 다른 `ISourceEditor` 구현체가 `SelectLine`에서 스크롤을 보장하지 않을 수 있는지는 확인 필요.

### 11. 소스 조회 중 일부 잘못된 버전 행 하나가 전체 탐색을 중단할 수 있습니다 (기존 코드, 이번 변경과 무관)

파일: `RuleRefControl.cs:600-604` — 한 행이 `DBNull`/비숫자/범위초과면 바깥 catch로 빠져 나머지 정상 버전도 시도 안 함. 최종적으로 실제 원인과 무관하게 `EDITED_PROGRAM_NOT_CONVERTIBLE` 메시지 표시.

### 12. `TreeListNode tn` null 가드가 없습니다 (기존 코드, 이번 변경과 무관)

파일: `RuleRefControl.cs:577-584`

## 낮음

### 13. `FormatManager`를 매번 생성 — 즉각적 누수는 아니나 불필요한 할당

파일: `QueryEditorControl.cs:325` — 일반 클릭 빈도에서는 병목 가능성 낮음. 두 색상이 사실상 고정이므로 캐싱 여지 있음. 단, Syncfusion 포맷 객체가 특정 EditControl/FormatManager에 종속되는지 확인 없이 전역 static 캐싱은 피해야 함.

### 14. `SetLineBackColor` 방식 자체(포커스 독립 강조)는 목적에 적합. 단, bool 두 번째 인수 의미·줄 번호 1-based 여부는 별도 검증 필요

`CurrentColumn=1`이 첫 컬럼이라는 리플렉션 검증은 컬럼 체계만 입증하며, `SetLineBackColor`의 줄 번호 범위·bool 인수 의미까지 입증하지는 않음.

### 15. 인터페이스 시그니처 변경(`SelectLine(int, bool)`)은 전체 구현체·바이너리 호환성 검사 필요

솔루션 전체 재빌드가 성공하면 소스 수준 누락은 잡히지만, 별도 배포되는 구현체가 있다면 런타임 호환성 문제 가능.

## 질문별 결론

- **여러 MDI 창에서 델리게이트 덮어쓰기가 안전한가?** 이벤트 누적/다중 호출 관점에서는 안전. 다만 활성 MDI 전환마다 세터가 반드시 호출된다는 외부 보장 필요 — 창 종료~활성화 사이에는 폐기된 인스턴스를 가리킬 수 있어 자체적으로 완전히 안전한 설계는 아님.
- **폐기된 `FlowAndSourceContent`를 가리킬 수 있는가?** 예. 종료 시 조건부 해제가 없고 델리게이트가 인스턴스 메서드를 강하게 참조하므로 가능.
- **빠른 줄 이동에서 `_lineHighlightBandLine` 정리는 올바른가?** 같은 문서 안에서 UI 스레드 순차 호출이면 올바름.
- **문서 교체 시에도 안전한가?** 아니요 — `SqlText` 변경과 필드 초기화가 연결돼 있지 않음.
- **`FormatManager` 매번 생성이 큰 문제인가?** 일반 빈도에서는 낮은 위험, 불필요한 할당.
- **`FlowView`의 선행 `CurrentLine` 두 줄은 제거 가능한가?** 현재 `QueryEditorControl.SelectLine()` 구현만 놓고 보면 중복, 제거 가능성 높음.
