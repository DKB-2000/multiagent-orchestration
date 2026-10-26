# Log — FlowView/RuleRef 소스보기 라인 하이라이트 개선

<!-- 이 로그는 작업 완료 후 소급 작성됨(2026-09-18) — 시각은 대화 흐름 기준 추정치, 정확한 HH:MM 아님 -->

[2026-09-17 00:00] [DECISION] 사용자 요청: FlowView 소스보기가 대상 라인 윗줄(공백줄)까지 같이 강조되는 버그 수정 + 디버그 소스보기는 #D8F3DC로 강조. 오케스트레이터가 직접 조사(워커 미사용, 비평 생략 지시).
[2026-09-17 00:10] [DECISION] Syncfusion EditControl 리플렉션으로 API 검증(SetSelection 컬럼이 1-based인데 columnStart=0을 줘서 앵커가 윗줄로 밀림) → columnStart=1로 수정.
[2026-09-17 00:30] [DECISION] 디버그 강조 시 캐럿 포커스와 SetSelectionBackColor 색이 섞이는 문제 발견 → SetLineBackColor 기반 "줄 배경색 강조" 방식으로 전환(HighlightLineBand).
[2026-09-17 00:45] [WORKER_CALL] 없음 — 오케스트레이터 직접 편집. 대상: QueryEditorControl.cs, FlowChartUiContracts.cs, FlowView.cs (V2 저장소).
[2026-09-17 01:00] [DECISION] 사용자 요청으로 동일 변경을 FlowAndSourceContent.cs(인코딩변경 재강조), RuleRefControl.cs(룰참조 이동)에도 적용, 색상 #D9F0FF 지정.
[2026-09-17 01:10] [DECISION] 사용자 요청: V2뿐 아니라 비-V2(<repo>) 저장소에도 동일 적용 — 수정 전 두 저장소 파일이 byte-identical함을 확인 후 동일 diff 적용.
[2026-09-17 01:30] [VERIFICATION] 우클릭 "소스 보기" 메뉴(menuItemOpenSource_Click)가 OpenSource(false)→SelectLine 동일 경로를 타는지 호출 체인 확인 — 별도 수정 불필요 확인.
[2026-09-17 02:00] [DECISION] 재빌드 안 된 상태로 테스트 중임을 exe/dll mtime(9/15) vs 소스 mtime(9/17) 비교로 발견 → 사용자에게 재빌드 필요 안내.
[2026-09-17 02:10] [DECISION] 일반(비디버그) 소스보기도 SetSelection 대신 줄 배경색 강조로 통일(포커스 없을 때 하이라이트 안 보이는 문제) — 색상 #D9F0FF로 통일.
[2026-09-17 02:30] [DECISION] 사용자 직접 확인: RuleRefControl.cs 색상이 파일에서 직접 #C9E5F7로 변경돼 있음(세션 외부 편집) — 되돌리지 않고 현재 상태로 채택, V2도 동기화.
[2026-09-18 00:00] [DECISION] 사용자 요청: 하이라이트 대상 줄이 뷰 맨 위에 붙는 문제 → 대상보다 2줄 위를 먼저 스크롤(ScrollToLineWithContext)하는 방식으로 수정. 디버그 색상 #D8F3DC → #EEC8BD 변경.
[2026-09-18 00:20] [DECISION] 디버그색 #EEC8BD 기준 채도 낮춘 갈색 계열 후보 제시(적용 보류 상태로 대화 종료).
[2026-09-18 00:30] [DECISION] #D9F0FF → 채도 통일 계산(#E1EEF7) → 사용자 피드백("너무 옅음, 파란기 더") → #C9E5F7/#B8DFF9 후보 제시.
[2026-09-18 00:40] [DECISION] 사용자 요청: RuleRefControl 소스보기가 "초기 상태"에서 동작 안 하는 이유 분석 + 노드-소스보기처럼 패널이 나타나게 수정.
[2026-09-18 00:50] [DECISION] 1차 진단: pgmId는 decimal.TryParse로 안전 파싱하는데 lineLine은 Convert.ToInt32 무검증 → 빈 값이면 FormatException이 빈 catch{}에 삼켜져 패널 표시 로직(EnsureSourcePaneVisibleAndSplitHalf/focusToFlowAndSourceContent)까지 스킵됨. 각 단계 개별 try/catch + 로깅으로 분리 수정.
[2026-09-18 01:00] [VERIFICATION] 사용자가 재현: NullReferenceException 로그 확인("개체 참조가 개체의 인스턴스로 설정되지 않았습니다") — 1차 진단으로는 불충분함이 드러남.
[2026-09-18 01:10] [DECISION] 근본 원인 재규명: ProgramContentListControl.cs가 FlowAndSourceContent(true)로 지연 초기화 모드 생성 → sourceControl이 null 상태로 남음. View 소스보기(SourceOpen 이벤트)를 먼저 눌러야만 InitSourceControl()이 실행되어 sourceControl이 생성됨. RuleRefControl에는 이 트리거 경로가 없었음.
[2026-09-18 01:20] [DECISION] 수정: RuleRefControl에 EnsureSourceControlReady(Action) 콜백 추가, FlowAndSourceContent.RuleRefControl 세터에서 this.InitSourceControl을 매번 덮어써서 연결(공유 싱글턴 ruleRefCtl이라 이벤트(+=) 대신 단일 델리게이트로 구독 누적/누수 회피). OpenSource() 진입 시 콜백 호출 후 sourceControl null 체크.
[2026-09-18 01:30] [DECISION] 사용자 요청으로 이번 세션 전체(오케스트레이터 직접 호출) 작업 문서화 정책을 "생략"에서 "작성"으로 변경 확정. 이 task 폴더를 소급 작성.
[2026-09-18 01:30] [COMPLETE] FlowView/RuleRefControl 소스보기 라인 하이라이트 개선 완료. 최종 색상: 디버그 #EEC8BD, 일반/RuleRef/인코딩변경 #C9E5F7(파란 채도 상향 후보 #B8DFF9는 미확정). V2/비-V2 두 저장소 동일 적용. 재빌드는 사용자가 직접 진행 예정.
[2026-09-18 09:32] [APPROVAL] claude-critic 사용자 승인(AskUserQuestion, write_scope: none) — 오케스트레이터 직접 구현분 리뷰 목적
[2026-09-18 09:32] [WORKER_CALL] claude-critic 호출 (call_worker.sh, isolated_tmp, timeout 300s) — brief: workers/claude-critic/brief.md
[2026-09-18 09:33] [ERROR] claude-critic 호출 실패(exit 1). stderr: "error: unknown option '--prompt
'". 두 가지 인프라 버그 추정: (1) backends.json의 claude-critic args_template이 ["--prompt", @brief_content]인데 실제 claude CLI에는 --prompt 플래그가 없음(claude --help 기준 -p/--print + positional prompt) (2) call_worker.sh의 while read -r a 루프가 jq -r 출력의 각 줄을 읽는데, Windows jq가 CRLF를 내보내는 것으로 보여 각 arg 끝에 
가 붙어 옵션명이 --prompt
 로 깨짐(모든 cli 타입 워커 args_template 공통 영향 가능). 코드 리뷰 작업과 무관, 사용자에게 보고.
[2026-09-18 09:34] [APPROVAL] codex-main 사용자 승인 — claude-critic 디스패처 실패 후 대체 리뷰어로 지정, mcp__codex__codex 직접 호출(native, 디스패처 미경유)
[2026-09-18 09:38] [VERIFICATION] codex-main 리뷰 완료(1차 read-only 실패 → PowerShell 접근 거부로 파일 직접 못 읽음, 2차 코드 인라인 재요청으로 성공). 치명적 1건(기존 버그: CurrentLine getter 무한재귀, 이번 변경과 무관), 높음 4건(델리게이트 폐기 인스턴스 참조 위험, IsDisposed 미검사, 빈 catch 은폐 - 로깅 제거 회귀 지적), 중간 7건, 낮음 3건. output_format(텍스트 응답, 수정 없음) 준수 확인, write_scope none 준수(코드 수정 안 함) 확인.
[2026-09-18 09:41] [DECISION] 사용자 지시: 리뷰 발견사항 중 1,2,6만 반영(3번 로깅 제거는 사용자가 의도적으로 한 것이라 유지). 적용: (1) FlowAndSourceContent에 Disposed 이벤트 훅 추가 — 자신이 EnsureSourceControlReady를 아직 가리키고 있을 때만 null로 정리(다음 MDI 전환이 이미 덮어썼으면 손 안 댐). (2) RuleRefControl.OpenSource: EnsureSourceControlReady 호출을 try/catch로 감싸고, sourceControl null 체크에 IsDisposed 추가. (6) FlowView.cs node/box 두 분기에서 SelectLine 직전의 중복 CurrentLine 대입 2줄씩 제거(SelectLine이 내부에서 ScrollToLineWithContext로 다시 처리하므로 무의미했음). V2/비-V2 두 저장소 동일 적용.
[2026-09-18 09:41] [COMPLETE] 리뷰 대응 완료(1,2,6 반영 / 3은 사용자 의도 확인되어 미반영 / 4,5,7,9,11,12,13,14,15는 보류 — 필요시 별도 판단). 최종 상태로 task 종료.
[2026-09-18 09:49] [COMPLETE] 사용자 확인으로 task 최종 완료 처리. task.md Acceptance Criteria 전항목 체크, status: done. 보류 항목은 task.md Notes에 목록화(후속 task 필요 시 참조).
