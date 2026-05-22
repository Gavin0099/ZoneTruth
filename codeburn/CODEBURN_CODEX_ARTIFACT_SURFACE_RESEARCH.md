# CodeBurn -- Codex CLI Artifact Surface Research

> Written: 2026-05-21
> Status: P5-admission.0 -- surface research only
> Scope: Codex CLI session artifact format, storage, token structure
> Role: admission evidence preparation -- does NOT authorize ingestion
> Observed version: cli_version=0.130.0-alpha.5, model_provider=openai
> Source: live inspection of ~/.codex/ on local machine

---

## 연구 한계 선언 (Research Scope Declaration)

이 문서는 **admission evidence preparation** 이다.

이 문서의 결과는:
- P5-admission.1 (Codex artifact contract) 의 입력으로 사용될 수 있다
- P5-admission.2 (AG-6 adversarial review) 의 대상이 되어야 한다
- **P5.0 (Codex ingestor) 를 승인하지 않는다**

```
research may inform admission
research does not authorize ingestion
```

---

## 아티팩트 저장 위치 및 구조

### 기본 저장 경로

```
~/.codex/
  session_index.jsonl          -- 세션 목록 인덱스 (경량)
  sessions/
    YYYY/
      MM/
        DD/
          rollout-{timestamp}-{uuid}.jsonl  -- 세션 로그 본체
  logs_2.sqlite                -- 운영 로그 DB
  state_5.sqlite               -- 세션 상태 DB
  config.toml                  -- 설정 파일
  auth.json                    -- 인증 정보
```

### 세션 인덱스 형식 (session_index.jsonl)

각 줄이 하나의 세션을 나타낸다:

```json
{
  "id": "019e4836-53c8-76c3-b394-955438e9cc06",
  "thread_name": "...",
  "updated_at": "2026-05-21T01:20:54.222Z"
}
```

이 파일은 token 데이터를 포함하지 않는다.

### 세션 로그 파일 형식

파일명 패턴:
```
rollout-{ISO8601_timestamp}-{UUID_v7}.jsonl
```

Claude Code 와 동일하게 JSONL 형식이다.
각 줄이 하나의 JSON 레코드이며, line/offset 추적이 기술적으로 가능하다.

---

## 레코드 타입 분류

실제 세션 로그에서 관찰된 레코드 타입:

| type | 설명 | token 데이터 포함 |
|---|---|---|
| `session_meta` | 세션 메타데이터 (cwd, cli_version, model 등) | 아니오 |
| `event_msg` | 이벤트 메시지 (token_count, 기타) | **일부** (`token_count` subtype) |
| `response_item` | 응답 내용 (message content, tool calls 등) | 아니오 |
| `turn_context` | 턴 컨텍스트 정보 | 아니오 |

Claude Code 와의 차이점: token 데이터가 **assistant 레코드가 아닌 별도 event_msg 레코드에** 존재한다.

---

## Token 데이터 구조 (핵심 발견)

### Token 데이터의 위치

token 데이터는 `event_msg` 레코드 중 `payload.type == "token_count"` 인 레코드에 있다:

```json
{
  "timestamp": "...",
  "type": "event_msg",
  "payload": {
    "type": "token_count",
    "info": {
      "total_token_usage": { ... },
      "last_token_usage": { ... },
      "model_context_window": 258400
    },
    "rate_limits": { ... }
  }
}
```

### 두 개의 Token Usage 객체

`token_count` 레코드는 **두 개의 token usage 객체**를 포함한다:

**`total_token_usage`** -- **세션 누적 합계**:
```json
{
  "input_tokens": 19980,
  "cached_input_tokens": 7552,
  "output_tokens": 384,
  "reasoning_output_tokens": 48,
  "total_tokens": 20364
}
```

**`last_token_usage`** -- **직전 turn 의 사용량**:
```json
{
  "input_tokens": 19980,
  "cached_input_tokens": 7552,
  "output_tokens": 384,
  "reasoning_output_tokens": 48,
  "total_tokens": 20364
}
```

이 두 객체는 동일한 필드명을 가지지만 의미가 전혀 다르다.
첫 번째 turn 에서는 두 값이 동일하게 보이지만, 이후 turn 에서는 누적 vs 단위가 분기된다.

### Codex 전용 필드: reasoning_output_tokens

```json
"reasoning_output_tokens": 48
```

Claude Code 의 session log 에는 이 필드가 존재하지 않는다.
이것은 OpenAI reasoning model (o-series, GPT-5 등) 에 특유한 필드다.

---

## SQLite 표면 (보조 데이터)

### state_5.sqlite -- threads 테이블

```sql
threads.tokens_used INTEGER
```

이 필드는 세션 누적 token 수를 저장한다.
이것은 JSONL 의 `total_token_usage` 와 동일한 누적 값으로 추정되며,
JSONL 과 독립적인 두 번째 acquisition surface 다.

### logs_2.sqlite

운영 로그를 저장하며 token 데이터를 포함하지 않는다.
schema: `id, ts, level, target, feedback_log_body, ...`

---

## admissible/inadmissible 필드 예비 분류

이것은 예비 분류이며, P5-admission.1 (artifact contract) 에서 확정되어야 한다.

### Admissible 후보 (제한적)

| 필드 | 위치 | 비고 |
|---|---|---|
| `last_token_usage.input_tokens` | event_msg.payload.info | 단위 turn 입력 -- Claude 의 `input_tokens` 에 대응 가능성 있음 |
| `last_token_usage.output_tokens` | event_msg.payload.info | 단위 turn 출력 |
| timestamp | 레코드 최상위 | 타임스탬프 |
| session id | session_meta.payload.id | 세션 식별자 |

### Inadmissible 후보

| 필드 | 위치 | 이유 |
|---|---|---|
| `total_token_usage.*` | event_msg.payload.info | 세션 누적 값 -- 중복 집계 위험 |
| `reasoning_output_tokens` | last_/total_token_usage | OpenAI 전용 -- Claude 에 동등 개념 없음 |
| `total_tokens` | last_/total_token_usage | 집계 합산 -- CodeBurn 은 집계 계산 비승인 |
| `cached_input_tokens` | last_/total_token_usage | 청구 계산 금지 (CODEBURN_CLAUDE_ARTIFACT_CONTRACT.md 정책과 일치) |
| `model_context_window` | payload.info | 운영 메타데이터 |
| `rate_limits.*` | payload | 운영 메타데이터 (used_percent, resets_at 등) |
| `threads.tokens_used` | state_5.sqlite | SQLite 표면 -- JSONL 과 중복, 다른 acquisition path |
| `cwd`, `cli_version`, `source` | session_meta.payload | 운영 메타데이터 |
| `model_provider`, `originator` | session_meta.payload | 운영 메타데이터 |

---

## Claude Schema Projection Bias 위험

이것이 이 연구에서 가장 중요한 발견이다.

### 위험 1: 동일 필드명, 다른 의미 (누적 vs 단위)

Claude Code:
```json
// type=assistant 레코드의 message.usage
"input_tokens": 10   // 이 turn 의 입력 (단위 turn)
```

Codex:
```json
// token_count 레코드
"total_token_usage": {
  "input_tokens": 19980   // 세션 누적 합계 !!!
}
"last_token_usage": {
  "input_tokens": 19980   // 이 turn 의 입력 (단위 turn)
}
```

Claude 용 ingestor 를 Codex 에 적용하면:
`total_token_usage.input_tokens` 를 읽을 수 있으며, 이것은 누적 값이다.
이것은 단위 turn 값처럼 보이지만 완전히 다른 의미다.

### 위험 2: cached_input_tokens 필드명 차이

Claude:
```json
"cache_read_input_tokens": 9364   // 필드명
```

Codex:
```json
"cached_input_tokens": 7552   // 다른 필드명, 유사한 개념
```

필드명이 다르다. 그러나 의미가 유사하다.
이것은 "같은 개념이므로 합산 가능" 추론을 유발할 수 있다 (FSP-3 위반).

### 위험 3: reasoning_output_tokens 의 비대칭

Claude 에는 `reasoning_output_tokens` 가 없다.
Codex 에는 있다.

이 비대칭을 무시하면:
- Claude session 의 "output tokens" = completion 전체
- Codex session 의 "output tokens" = completion - reasoning

두 값은 동일한 작업에 대해 다른 숫자를 반환한다.
이것은 비교 가능성을 파괴하며, FSP-3 의 schema 차원 표현이다.

### 위험 4: total_tokens 의 가용성 차이

Claude: `total_tokens = NULL` (CodeBurn 정책 -- 집계 계산 비승인)
Codex: `total_tokens = 20364` (명시적으로 기록됨)

Codex 에 `total_tokens` 가 있다고 해서 그것을 저장하거나 사용하는 것이 승인되지 않는다.
그러나 그 존재가 "이번엔 저장해도 되지 않을까" 추론 압력을 생성한다.

### 위험 5: 두 개의 acquisition surface 존재

Codex 는 JSONL + SQLite 두 개의 surface 를 가진다.
두 surface 모두에서 token 데이터를 읽는 것은:
- 서로 다른 acquisition path 에서 동일한 증거를 두 번 추출하는 것
- 두 surface 가 항상 일치하는지 보장되지 않음

---

## Malformed Record 가능성

JSONL 형식이므로 Claude Code 와 동일한 malformed record 위험이 존재한다:
- JSON parse failure
- 필수 필드 부재 (type, payload)
- payload.type 이 "token_count" 가 아닌 event_msg
- 부분 기록 (write 중단으로 인한 truncation)

Line/offset 추적은 기술적으로 가능하며 Claude 와 동일한 방식으로 구현 가능하다.

---

## 이 연구가 답하지 않은 것

다음 질문들은 P5-admission.1 (artifact contract) 에서 결정되어야 한다:

1. `last_token_usage` 가 항상 존재하는가, 아니면 조건부인가?
2. 세션 내 token_count 레코드의 수가 turn 수와 1:1 인가?
3. session_meta 레코드가 항상 첫 번째 줄인가?
4. 다른 event_msg subtype 들이 token 관련 정보를 포함하는가?
5. Codex 의 epistemic class 는 Class C 인가, 아니면 다른 class 인가?
   (Claude 가 Class C 이기 때문에 Codex 도 Class C 라는 추론은 허용되지 않음)

---

## 연구 결론

| 질문 | 답변 |
|---|---|
| Codex CLI 에 session artifact 가 있는가? | 예 (JSONL + SQLite) |
| 주요 artifact 위치 | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` |
| 형식 | JSONL (Claude Code 와 동일) |
| Token usage 가 존재하는가? | 예 (`event_msg` 의 `token_count` subtype) |
| Line/offset 추적 가능한가? | 예 (JSONL 형식) |
| Malformed record 가능성 | 예 (Claude 와 동일) |
| Claude schema 직접 재사용 가능한가? | **아니오** -- 레코드 타입, 필드 위치, 누적/단위 구분이 모두 다름 |
| Claude projection bias 위험 수준 | **높음** -- 동일 필드명에 다른 의미 (특히 누적 vs 단위) |

---

*이 연구는 Codex CLI 의 artifact surface 를 설명한다.*
*이 연구는 Codex acquisition 을 승인하지 않는다.*
*승인은 P5-admission.1 ~ P5-admission.3 을 완료한 후에만 가능하다.*
