# 비평 모드 — 코드 리뷰만, 파일 수정 금지 (write_scope: none)

target_repo(리뷰 대상, 두 체크아웃에 동일 diff 적용됨): `<repo>`(실사용) / `<repo-v2>`

## 리뷰 대상 파일 (비-V2 기준 경로, 직접 Read해서 확인)
- `App.Common\Interface\FlowChartUiContracts.cs` — `ISourceEditor.SelectLine` 시그니처
- `App.Studio\Rule\Query\QueryEditorControl.cs` — `SelectLine`/`HighlightLine`/`HighlightLineBand`/`ScrollToLineWithContext`
- `App.FlowChart\FlowView.cs` — 13460~13530줄 부근 `OpenSource`
- `App.Studio\Rule\Flow\FlowAndSourceContent.cs` — `RuleRefControl` 프로퍼티 세터, `InitSourceControl`/`CreateSourceControl`
- `App.Studio\Rule\OtherInfo\RuleRefControl.cs` — `OpenSource(TreeListNode)`, `EnsureSourceControlReady`

## 배경
Syncfusion EditControl 기반 COBOL 소스뷰어에서 세 가지를 고쳤음:
1. 라인 하이라이트가 대상 줄 윗줄까지 같이 잡히던 버그 → `SetSelection` columnStart 0→1
2. 캐럿 포커스와 하이라이트색이 섞이던 문제 → `SetSelection` 대신 `SetLineBackColor` 기반 줄 배경색 강조로 전환
3. `RuleRefControl` 소스보기가 "플로우차트 노드 소스보기를 먼저 눌러야만 동작"하던 버그 → 원인: 프로그램 편집기는 `FlowAndSourceContent(true)`로 지연 초기화되어 `sourceControl`이 null인 채 방치됨. `RuleRefControl.EnsureSourceControlReady`(Action 델리게이트, 매번 덮어씀 — 공유 싱글턴이라 이벤트 `+=` 누적 방지 목적)를 `FlowAndSourceContent.RuleRefControl` 세터에서 연결해 해결.

## 요청
1. C#/WinForms 관점 로직 정확성 검토 (특히 RuleRefControl↔FlowAndSourceContent 델리게이트 배선, null 가드, Syncfusion EditControl API 사용법)
2. 놓친 엣지케이스·회귀 위험 지적 (예: 다른 FlowAndSourceContent 인스턴스/멀티 MDI 창 간 델리게이트 덮어쓰기 부작용 등)
3. 코드 직접 수정 금지 — 텍스트로만 응답
