# Brief — claude-main / worker-smoke-test

## Worker 행동 규약 (고정)

- 요청 범위만 최소로. 사변적 추상화·기능 추가 금지
- 외과수술식 수정: 기존 스타일 유지, 무관 코드 비접촉
- 사용자 대화 채널 없음: 가정은 명시하고, 불확실·불일치는 result의 Issues/Caveats에 표면화

## Objective

이 워커가 정상 응답하는지 확인하는 커넥티비티 테스트.

## Input

없음.

## Constraints

- 코드/파일 수정 금지 (읽기·쓰기 어떤 것도 하지 말 것)
- 짧게 답할 것

## Output Format

다음 형식의 텍스트만 반환:
```
role: strategist (claude-main)
status: ok
note: <한 줄 확인 메시지>
```

## Do NOT

- 파일 시스템 접근 금지
- 이 테스트와 무관한 작업 수행 금지
