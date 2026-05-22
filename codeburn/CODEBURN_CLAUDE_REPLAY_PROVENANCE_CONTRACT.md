# CodeBurn -- Claude Log Replay / Provenance Verification Contract

> Written: 2026-05-20
> Status: **BINDING** -- P4.0 spec document
> Scope: all Claude .jsonl ingestion via claude_log_ingestor.py
> Depends on: CODEBURN_CLAUDE_ARTIFACT_CONTRACT.md, CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md
> Authorizes: P4.1 provenance identity helper, P4.2/P4.3 replay tests

---

## 핵심 구분: Idempotency vs Provenance Identity

이 문서는 두 개의 서로 다른 개념을 명확히 분리한다.

**Idempotency** -- 동일한 입력에 대해 시스템 상태가 동일하게 유지되는가
**Provenance Identity** -- 동일한 소스 위치에서 추출된 증거 내용이 일관적인가

CodeBurn Claude 인제스터는:
- **Non-idempotent**: 동일 artifact 를 두 번 ingest 하면 두 배의 rows 생성
- **Provenance-identity stable**: 동일한 (artifact_path, line, offset) 위치에서는
  항상 동일한 증거 내용이 추출됨

이 두 속성은 독립적이다. Non-idempotency 는 버그가 아니라 설계 결정이다.

---

## 명시적 Non-Idempotency 계약

**CodeBurn Claude 인제스터는 중복 ingest 를 방지하지 않는다.**

이유:
1. CodeBurn 은 관찰 시스템이다 -- 트랜잭션 시스템이 아니다
2. 중복 방지는 "이전에 이것을 본 적 있다"는 상태를 요구하며, 이는 runtime authority 로의
   첫 번째 이동이다
3. 로그 기반 시스템은 append-only 가 기본이며, 중복 제거는 downstream 의 책임이다
4. 중복 ingest 는 감사 가능성을 파괴하지 않는다 -- 오히려 ingest 이력을 보존한다

**무엇이 보장되지 않는가:**

| 행동 | 보장 여부 |
|---|---|
| 동일 artifact 두 번 ingest = DB 상태 동일 | 보장 안 됨 |
| step_id 가 동일하게 유지 | 보장 안 됨 (UUID 는 매 ingest 마다 새로 생성) |
| 총 row 수가 ingest 횟수에 비례 | 보장됨 |
| quarantine rows 가 중복 생성되지 않음 | 보장 안 됨 |

**소비자에 대한 함의:**
중복 ingestion 여부를 판단해야 하는 소비자는
`source_artifact_path + source_record_line + source_record_offset` 의 조합으로
중복을 감지해야 한다. `step_id` 는 중복 감지 키가 아니다.

---

## 결정론적 Provenance Identity

동일한 소스 위치에서 추출된 증거 내용은 항상 동일하다.

**Provenance Identity 는 세 필드의 조합으로 정의된다:**

```
provenance_identity = (
    source_artifact_path,   # 절대 경로 -- 파일 이동 시 변경됨
    source_record_line,     # 1-indexed 줄 번호
    source_record_offset    # 파일 시작부터의 바이트 오프셋
)
```

이 세 필드가 동일하면, 추출되는 증거 내용은 반드시 동일하다:
- `prompt_tokens` 값
- `completion_tokens` 값
- `epistemic_class` (항상 'Class C')
- `acquisition_mode` (항상 'session_log_ingestion')

**이 안정성은 다음을 전제로 한다:**
- .jsonl 파일 내용이 변경되지 않았다 (append-only 로그 특성)
- 파일 인코딩이 동일하다 (utf-8, errors='replace')
- 줄 구분자 처리가 동일하다 (rstrip '\n\r')

---

## 세 가지 Replay 불변량

### R1 -- source_record_line 안정성

동일한 .jsonl 파일을 여러 번 ingest 할 때,
동일한 레코드는 항상 동일한 `source_record_line` 값을 가진다.

```
ingest(artifact, session, db) 두 번 실행 시:
  1회차 source_record_line=4 인 레코드
  → 2회차에서도 source_record_line=4
```

이것이 실패한다면: 파일 읽기가 결정론적이지 않거나, 줄 계산에 버그가 있음을 의미한다.

### R2 -- source_record_offset 안정성

동일한 레코드는 항상 동일한 `source_record_offset` 값을 가진다.

```
1회차 offset=480 인 레코드 → 2회차에서도 offset=480
```

offset 은 파일 시작부터의 누적 바이트 수이며, utf-8 인코딩 기준으로 계산된다.
파일 내용이 변경되지 않는 한 안정적이어야 한다.

### R3 -- quarantine provenance 안정성

malformed line 에 대한 quarantine record 도 동일한 line/offset 을 가진다.

```
1회차 malformed line 9 → quarantined_records.source_record_line=9
2회차 동일 malformed line 9 → quarantined_records.source_record_line=9
```

quarantine 은 증거의 부재를 기록한다. 부재의 위치는 안정적이어야 한다.

---

## 세 가지 경계 선언

### 경계 1: replay stable != runtime observed

동일한 결과를 반복 재현할 수 있다고 해서
해당 증거가 runtime 에 실시간으로 관찰된 것이 되지는 않는다.

재현 가능성은 데이터 품질의 속성이다.
Class C (observer-reconstructed) 분류는 재현 가능성에 관계없이 유지된다.

```
WRONG:  "동일한 결과를 두 번 얻었으므로 provider-grade 증거와 같다"
RIGHT:  "동일한 재구성을 두 번 수행했다 -- 여전히 Class C"
```

### 경계 2: duplicate allowed != duplicate semantically consumed

중복 row 가 존재한다는 것이 중복 row 가 유효한 독립 증거라는 의미가 아니다.

두 번 ingest 해서 생성된 두 개의 rows 는:
- 데이터베이스 관점: 두 개의 독립 rows
- 증거 관점: 동일한 소스 위치에 대한 두 번의 재구성 -- 독립 증거 아님

소비자는 이 구분을 명시적으로 처리해야 한다.
중복 row 를 합산하거나 독립 관찰로 취급하는 것은 금지된다.

### 경계 3: provenance identity stable != token truth verified

(source_artifact_path, line, offset) 의 안정성은
해당 위치에 기록된 token 값이 provider 가 실제로 계산한 값임을 증명하지 않는다.

안정성은 재구성이 일관적임을 의미한다.
일관적인 재구성은 여전히 Class C 이며, Class A 로 승급되지 않는다.

```
WRONG:  "재현 가능한 token 값 = provider-verified token"
RIGHT:  "재현 가능한 token 값 = 재구성이 일관적 -- 여전히 Class C"
```

---

## Provenance Identity 중복 감지 규칙

중복 ingestion 을 감지하거나 분석해야 하는 경우 사용할 규칙:

```sql
-- 동일 소스 위치에 대해 두 번 이상 ingest 된 레코드 탐지
SELECT
    source_artifact_path,
    source_record_line,
    source_record_offset,
    COUNT(*) as ingest_count
FROM step_ingestion_provenance
GROUP BY source_artifact_path, source_record_line, source_record_offset
HAVING COUNT(*) > 1;
```

이 쿼리의 결과를 "중복 오류" 로 처리해서는 안 된다.
이것은 "동일 위치를 여러 번 재구성했다" 는 관찰이다.

중복 ingestion 이 문제가 되는 경우는:
- aggregate 계산에 포함될 때 (금지됨 -- Comparability Boundary)
- 독립 관찰로 취급될 때 (위 경계 2 위반)

---

## 이 계약이 승인하는 구현

**P4.1** -- `_provenance_identity(artifact_path, line, offset)` 헬퍼
  source_record_line 과 source_record_offset 이 결정론적임을 테스트하기 위한 보조 함수

**P4.2** -- valid record replay 테스트
  동일 artifact 두 번 ingest 후 동일 (line, offset) 쌍이 나타남을 검증

**P4.3** -- quarantine record replay 테스트
  malformed line 두 번 ingest 후 동일 line/offset 으로 quarantine 됨을 검증

**P4.4** -- non-idempotency 명시 테스트
  두 번 ingest 시 row 수가 두 배가 됨을 검증 (이것은 버그가 아님을 확인)

**P4.5** -- replay smoke command
  실제 session log 에 대해 replay 안정성을 확인하는 CLI

---

## 이 계약이 승인하지 않는 것

- 중복 방지 로직 (deduplication at ingestion time)
- "이미 본 레코드" 상태 추적
- Replay 안정성을 근거로 한 epistemic class 승급
- Token 값의 provider-side 검증
- 동일 소스 위치의 두 rows 를 독립 증거로 취급한 aggregation

---

*재구성은 반복될 수 있다.*
*반복 가능한 재구성은 여전히 재구성이다.*
*Class C 는 재현 가능성이 아니라 관찰 거리에 의해 결정된다.*
