# CodeBurn -- Codex CLI Artifact Contract

> Written: 2026-05-21
> Status: **BINDING** -- P5-admission.1 semantic non-equivalence contract
> Scope: all Codex CLI session log acquisition
> Depends on: CODEBURN_CODEX_ARTIFACT_SURFACE_RESEARCH.md (empirical basis),
>             CODEBURN_ACQUISITION_SEMANTIC_FREEZE.md (constitutional frame),
>             CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md,
>             CODEBURN_AUTHORITY_CEILING_CONTRACT.md
> Authorizes: P5-admission.2 (AG-6 adversarial review)
> Observed version: Codex CLI 0.130.0-alpha.5

---

## 이 문서의 역할

이 문서는 Codex CLI 아티팩트 형식을 설명하는 것이 아니다.

이 문서는 **Codex Semantic Non-Equivalence Contract** 다.

가장 위험한 시나리오는 Codex ingestion 의 기술적 실패가 아니다.
가장 위험한 시나리오는:

> Claude mental model 이 Codex semantic surface 에 투영되는 것

Claude 의 schema 는 CodeBurn 의 default ontology 가 아니다.
Codex 의 필드는 Claude 의 동일 이름 필드와 동일한 의미를 가지지 않는다.

이 문서는 그 투영을 명시적으로 차단한다.

---

## 레코드 타입 분류

실제 관찰 (P5-admission.0) 에서 확인된 레코드 타입:

| type | 설명 | token evidence 포함 |
|---|---|---|
| `session_meta` | 세션 메타데이터 | 아니오 |
| `event_msg` | 이벤트 메시지 | **일부** -- `payload.type == "token_count"` 인 경우만 |
| `response_item` | 응답 내용, tool calls | 아니오 |
| `turn_context` | 턴 컨텍스트 | 아니오 |

### Claude Code 와의 구조적 차이

Claude Code: `type == "assistant"` 레코드의 `message.usage` 에 token 데이터 존재
Codex: `type == "event_msg"` 레코드 중 `payload.type == "token_count"` 인 레코드에 존재

이 두 레코드 타입은 동일한 위치 규칙을 가지지 않는다.
Claude 용 ingestor 의 필터 조건은 Codex 에 직접 적용할 수 없다.

---

## Admissible Fields

### 레코드 선택 조건

```
type == "event_msg"
AND payload.type == "token_count"
```

이 조건을 충족하지 않는 모든 레코드는:
- non-assistant (token evidence 아님) -- skip
- malformed -- quarantine

### Admissible Field 목록

| 필드 경로 | 의미 | 비고 |
|---|---|---|
| `payload.info.last_token_usage.input_tokens` | 이 turn 의 입력 token 수 | turn-scoped 만 admissible |
| `payload.info.last_token_usage.output_tokens` | 이 turn 의 출력 token 수 | Reasoning Separation 원칙 적용 |
| `timestamp` | 레코드 타임스탬프 | |
| `payload` 의 부모 레코드 UUID | 세션 내 레코드 식별 | session_meta 에서 추출 |

### Reasoning Separation 이후 output_tokens 의 의미

`last_token_usage.output_tokens` 는 **visible completion tokens** 을 의미한다.

이것은 `reasoning_output_tokens` 를 포함하지 않는다.
이 contract 에서 output_tokens 는 다음을 의미한다:

```
output_tokens = completion tokens - reasoning tokens
```

이는 Claude Code 의 output_tokens 와 의미가 다를 수 있다.
(Claude Code 의 output_tokens 가 reasoning 을 포함하는지 여부는 이 계약의 범위 밖이다)

---

## Inadmissible Fields

### IAF-1: total_token_usage (세션 누적 금지)

```
INADMISSIBLE: payload.info.total_token_usage.*
```

`total_token_usage` 는 세션 누적 합계다.
`last_token_usage` 는 직전 turn 의 단위 사용량이다.

이 두 객체는 동일한 필드명을 가지지만 의미가 전혀 다르다.
`total_token_usage` 를 ingest 하면:
- 누적 값이 turn-level 증거로 잘못 기록됨
- 세션이 길어질수록 값이 선형 증가하여 의미 없는 데이터 생성
- Claude 의 turn-level token 과 비교 불가능한 데이터 생성

### IAF-2: reasoning_output_tokens (Reasoning Separation)

```
INADMISSIBLE: last_token_usage.reasoning_output_tokens
INADMISSIBLE: total_token_usage.reasoning_output_tokens
```

Claude Code 의 session log 에는 이 필드가 존재하지 않는다.
이 필드를 무시하거나 0 으로 처리하는 것은 두 provider 의 output_tokens 의미를 변경한다.
이 필드를 저장하는 것도 승인되지 않는다 -- 이 필드는 reasoning 에 특유한 개념이며,
reasoning 이 없는 provider 와의 비교를 통한 의미 왜곡을 방지해야 한다.

이유: Reasoning Separation Principle (이 문서의 별도 절) 참조.

### IAF-3: total_tokens (집계 계산 금지)

```
INADMISSIBLE: last_token_usage.total_tokens
INADMISSIBLE: total_token_usage.total_tokens
```

`total_tokens = input_tokens + output_tokens + ...` 는 집계 계산 결과다.
Claude Code 에서와 동일하게, CodeBurn 은 집계 계산을 수행하거나 저장하지 않는다.
total_tokens 가 Codex log 에 명시적으로 존재한다는 사실은
CodeBurn 이 그것을 저장하도록 승인하지 않는다.

### IAF-4: cached_input_tokens (청구 계산 금지)

```
INADMISSIBLE: last_token_usage.cached_input_tokens
INADMISSIBLE: total_token_usage.cached_input_tokens
```

Claude Code 와 동일한 이유로 청구 계산 금지.

### IAF-5: model_context_window (운영 메타데이터)

```
INADMISSIBLE: payload.info.model_context_window
```

### IAF-6: rate_limits (운영 메타데이터)

```
INADMISSIBLE: payload.rate_limits.*
  including: used_percent, window_minutes, resets_at, limit_id
```

### IAF-7: session_meta 운영 필드

```
INADMISSIBLE: payload.cwd
INADMISSIBLE: payload.cli_version
INADMISSIBLE: payload.source
INADMISSIBLE: payload.model_provider
INADMISSIBLE: payload.originator
```

### IAF-8: SQLite acquisition surface (Dual Acquisition Surface Rule)

```
INADMISSIBLE: state_5.sqlite threads.tokens_used
INADMISSIBLE: state_5.sqlite threads.*
INADMISSIBLE: logs_2.sqlite *
```

이유: Dual Acquisition Surface Rule (이 문서의 별도 절) 참조.

---

## Non-Transferable Semantics (금지된 의미론적 이전)

이 절은 이 contract 의 핵심이다.

다음 각 항목은 **forbidden semantic transfer** 다.
"필드명이 같으므로 동일한 의미다" 또는 "유사하므로 비교 가능하다" 라는 추론은
이 계약에서 명시적으로 금지된다.

기호: `!≡` -- "의미론적으로 동일하지 않다"

### NST-1: Claude output_tokens !≡ Codex output_tokens

```
Claude Code output_tokens
!= (semantically equivalent to)
Codex last_token_usage.output_tokens
```

Claude Code 의 output_tokens 는 완성 토큰 전체를 나타낼 가능성이 있다.
Codex 의 output_tokens 는 reasoning_output_tokens 를 제외한 visible completion 이다.

두 값을 비교하는 것은 FSP-3 위반이며, 이 NST-1 로 추가 차단된다.

### NST-2: Claude cache tokens !≡ Codex cached_input_tokens

```
Claude Code cache_read_input_tokens
!= (semantically equivalent to)
Codex cached_input_tokens
```

필드명이 다르다. 그러나 의미가 유사해 보인다.
"유사해 보인다" 는 비교 가능성을 의미하지 않는다.
두 provider 의 cache 구현, cache 경계, cache 만료 정책이 동일하다는 보장이 없다.

이 두 필드는 각각 inadmissible 이다. 비교는 이중으로 불가하다.

### NST-3: Codex total_token_usage !≡ Claude turn token semantics

```
Codex total_token_usage.input_tokens
->/ (cannot be interpreted as)
Claude-style turn-scoped input evidence
```

Codex `total_token_usage` 는 세션 전체의 누적 합계다.
Claude Code 의 token 레코드는 turn 단위다.
이 두 개념은 동일한 필드명에도 불구하고 집계 단위가 다르다.

### NST-4: Codex reasoning_output_tokens !≡ Claude output overhead

```
Codex reasoning_output_tokens
->/ (cannot be treated as)
equivalent to any Claude token category
```

Claude Code 에는 reasoning 전용 token 카테고리가 없다.
Codex 의 reasoning_output_tokens 를 Claude 의 어떤 category 에 맞추는 것은 허용되지 않는다.
이 값은 admissible 하지 않으며, 다른 category 에 편입하는 것도 허용되지 않는다.

### NST-5: Codex `output_tokens` (no reasoning) !≡ Claude `output_tokens`

```
Codex last_token_usage.output_tokens
!= (semantically equivalent to)
Claude Code output_tokens

REASON: Codex output_tokens excludes reasoning_output_tokens
        Claude output_tokens scope is not separately declared
        These values are not comparable without explicit constitutional upgrade
```

---

## Reasoning Separation Principle

### 선언

> **Providers exposing reasoning-specific token categories**
> **must not be normalized into generic output_token semantics**
> **without explicit constitutional upgrade.**

### 이 원칙이 차단하는 것

다음의 암묵적 또는 명시적 행동이 금지된다:

```
reasoning_output_tokens
→ silently fold into output_tokens
→ treat as zero (as if reasoning did not occur)
→ aggregate with output_tokens for "total generation"
→ use to infer reasoning effort or model quality
```

### 이 원칙이 발생하는 이유

reasoning 을 visible output 과 분리하는 것은:
- Codex 가 reasoning token 을 노출한다는 것을 의미하지 않는다
- Claude 가 reasoning 을 사용하지 않는다는 것을 의미하지 않는다

단지: 두 provider 는 다른 수준의 세분성으로 token 을 보고한다.
세분성의 차이는 하나가 더 "완전하다" 는 것을 의미하지 않는다.

```
higher token reporting granularity
->/ more truthful reporting
->/ better comparability
```

모두 금지된 추론이다.

---

## Dual Acquisition Surface Rule

### 선언

Codex CLI 는 두 개의 acquisition surface 를 제공한다:

1. JSONL session log (`~/.codex/sessions/.../*.jsonl`)
2. SQLite state DB (`~/.codex/state_5.sqlite`, `threads.tokens_used`)

이 두 surface 는 독립적이다.

### 금지된 추론

```
SQLite surface completeness
->/ SQLite provenance superiority

JSONL line/offset trackability
->/ JSONL epistemic superiority

surface A data + surface B data
->/ more complete evidence
```

### 이유

두 surface 가 항상 동기화되어 있다는 보장이 없다.
두 surface 에서 동일한 값이 추출된다면:
- 두 개의 독립 증거가 아니라 동일한 소스의 두 표현이다
- 이것은 CODEBURN_CLAUDE_REPLAY_PROVENANCE_CONTRACT.md 의 duplicate semantics 와 동일 구조다

두 surface 에서 다른 값이 추출된다면:
- 어느 것이 "더 맞는가" 는 CodeBurn acquisition 으로 결정할 수 없다
- 이것은 Class C 의 관찰 거리에 의해 이미 결정된다

### CodeBurn 의 선택

CodeBurn 은 JSONL surface 만을 사용한다.
이유: line/offset provenance identity 를 유지하기 위해.
SQLite 는 line/offset 추적이 불가능하다.

이 선택은 JSONL 이 SQLite 보다 더 진실하거나 더 완전하다는 것을 의미하지 않는다.
이 선택은 provenance identity 가 acquisition 설계의 core constraint 이기 때문이다.

```
JSONL selected
!= JSONL is more truthful
!= JSONL is more complete
= JSONL supports provenance identity; SQLite does not
```

---

## Epistemic Invariants

다음 invariants 는 Claude Code 와 동일하게 Codex 에도 적용된다.
이것들은 Claude 로부터 상속된 것이 아니라 독립적으로 결정된다.

### I1: Epistemic Class = Class C (독립적으로 결정됨)

Codex session log 에서 ingest 된 모든 evidence 는 Class C 다.

이유: CodeBurn 은 log artifact 를 읽는다 (observer-reconstructed).
Claude 가 Class C 이기 때문이 아니라, acquisition path 가 Class C 를 결정하기 때문이다.

### I2: real_time_observed = 0 (항상)

CodeBurn 은 Codex runtime 을 관찰하지 않는다. log artifact 를 읽는다.

### I3: analysis_safe_for_decision = 0 (항상)

Class C evidence 는 decision 에 사용하기에 충분하지 않다.

### I4: provider_truthfulness_assumed = 0 (항상)

Codex log 에 기록된 값이 OpenAI provider 가 실제로 계산한 값임을 가정하지 않는다.

### I5: token 부재 = NULL (0 아님)

token 필드가 없거나 integer 가 아닌 경우 NULL 로 기록한다.

### I6: last_token_usage 부재 = NULL (0 아님)

`last_token_usage` 객체가 없는 경우:
token 이 사용되지 않은 것 (0) 이 아니라 데이터가 없는 것 (NULL) 이다.

---

## Schema Extension Authorization

이 contract 는 다음 schema element 를 Codex 지원을 위해 승인한다:

**`step_ingestion_provenance`**: 기존 schema 를 그대로 사용한다.
  - `provider` 값: `"codex"` (Claude 와 구분)
  - `epistemic_class`: `"Class C"` (독립 결정)
  - `acquisition_mode`: `"session_log_ingestion"` (동일 방식)

**`quarantined_records`**: 기존 schema 를 그대로 사용한다.

**`steps`**:
  - `prompt_tokens`: `last_token_usage.input_tokens` (NULL if absent)
  - `completion_tokens`: `last_token_usage.output_tokens` (NULL if absent; Reasoning Separation 적용)
  - `total_tokens`: 항상 NULL (집계 계산 금지 -- Codex log 에 있더라도)
  - `token_source`: `"estimated"` (Class C, 동일)

**승인되지 않는 것:**
- `reasoning_output_tokens` 를 위한 새 컬럼
- `total_token_usage.*` 를 위한 새 컬럼
- SQLite surface 를 위한 새 테이블

---

## 이 Contract 가 남긴 열린 질문

P5-admission.2 (AG-6 adversarial review) 에서 검토해야 할 항목:

1. `last_token_usage` 가 모든 `token_count` 레코드에 항상 존재하는가?
2. session 내 `token_count` 레코드 수가 turn 수와 정확히 1:1 인가?
3. `output_tokens` 가 reasoning 을 포함하지 않음이 공식 문서로 확인 가능한가?
4. Codex 의 JSONL 이 append-only 인지 (mid-session rewrite 가 없는지)?

이 질문들에 대한 불확실성은 Class C 분류를 강화한다.
불확실성이 해소되지 않더라도 ingestion 은 허용된다 (Class C 는 완전성을 요구하지 않는다).
그러나 불확실성이 가정(assumption)으로 대체되어서는 안 된다.

---

*이 contract 는 Codex ingestion 을 허용하는 문서가 아니다.*
*이 contract 는 Codex ingestion 이 발생할 때 지켜야 할 semantic boundary 를 선언한다.*
*boundary 가 없는 ingestion 은 evidence 가 아니라 noise 다.*
