# CodeBurn -- Acquisition Semantic Freeze

> Written: 2026-05-21
> Status: **BINDING** -- P4-closeout semantic stabilization layer
> Scope: all CodeBurn acquisition surfaces, past and future
> Depends on: CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md,
>             CODEBURN_CROSS_PROVIDER_COMPARABILITY_BOUNDARY.md,
>             CODEBURN_AUTHORITY_CEILING_CONTRACT.md,
>             CODEBURN_ACQUISITION_AUTHORITY_MODEL.md,
>             CODEBURN_CLAUDE_ARTIFACT_CONTRACT.md,
>             CODEBURN_CLAUDE_REPLAY_PROVENANCE_CONTRACT.md
> Role: binding interpretive constraint -- not spec, not checklist

---

## 이 문서의 역할

이 문서는 사양(spec)이 아니다.

이 문서는 **binding interpretive constraint** 다.

P0-P4 를 통해 구축된 bounded acquisition epistemology 를 보호하기 위해
존재한다. 보호의 대상은 schema 나 schema constraint 가 아니라:

**semantic implication** 이다.

CodeBurn 에서 가장 자주 발생하는 drift 는 schema drift 가 아니다.
가장 자주 발생하는 drift 는:

> 올바른 사실에서 허용되지 않는 추론으로 미끄러지는 것

이 문서는 그 미끄러짐을 명시적으로 차단한다.

이 문서가 가장 필요한 순간은:
시스템이 유용해 보이기 시작하는 순간이다.
유용성이 인식될 때 가장 먼저 침식되는 것은 경계다.

---

## 금지된 의미론적 승격 (Forbidden Semantic Promotions)

아래 각 항목은 CodeBurn 시스템 내에서 영구적으로 금지된 추론이다.

기호 `->/ ` 는 "~에서 ~로의 추론은 허용되지 않는다" 를 의미한다.

### FSP-1: Replay Stability ->/ Provider Correctness

```
replay stability ->/ provider correctness
```

동일한 (artifact_path, line, offset) 에서 동일한 token 값이 재현된다는 것은:
재구성이 결정론적임을 의미한다.

재구성의 결정론성은 provider 가 해당 값을 올바르게 계산했음을 증명하지 않는다.

```
결정론적 재구성 = 재구성이 일관적
결정론적 재구성 != provider 가 올바르게 계산했음
```

### FSP-2: Cross-Run Consistency ->/ Runtime Completeness

```
cross-run consistency ->/ runtime completeness
```

여러 번 ingest 해도 동일한 (line, offset) 쌍이 나타난다는 것은:
provenance identity 가 안정적임을 의미한다.

이것은 log artifact 가 runtime 의 전체 token 사용을 완전히 기록했음을
보장하지 않는다.

```
cross-run consistency = provenance identity stable
cross-run consistency != runtime observation complete
```

### FSP-3: Multiple Class C Sources ->/ Comparability Admissibility

```
multiple Class C sources ->/ comparability admissibility
```

두 개의 Class C evidence source 가 존재한다는 것
(예: Claude session logs + Codex acquisition)은:
그 두 source 를 비교할 수 있다는 것을 의미하지 않는다.

```
Class C + Class C != comparability
```

비교 가능성 조건은 CODEBURN_CROSS_PROVIDER_COMPARABILITY_BOUNDARY.md
에 정의된 4개 전제조건을 모두 충족해야 한다.

### FSP-4: Provider-Reported Usage ->/ Provider-Actual Computation

```
provider-reported usage ->/ provider-actual computation
```

log artifact 에 기록된 input_tokens, output_tokens 값은:
provider 가 세션에서 실제로 계산한 값임을 증명하지 않는다.

```
provider-reported = log artifact 에 기록된 값
provider-actual   = provider side 에서 실제 계산된 값 (CodeBurn 접근 불가)
```

이 둘은 다를 수 있으며, CodeBurn 은 그 차이를 감지하거나 교정할 수 없다.

### FSP-5: Acquisition Coverage Growth ->/ Governance Authority Growth

```
acquisition coverage growth ->/ governance authority growth
```

더 많은 provider 를 지원하거나, 더 많은 session 을 ingest 한다는 것은:
CodeBurn 의 governance authority 가 증가했다는 것을 의미하지 않는다.

acquisition coverage 의 확장은 관찰 가능한 evidence 의 범위를 넓힌다.
이것은 evidence 의 epistemic quality 나 governance authority 를 변경하지 않는다.

```
Class C * 100 = Class C * 100 (aggregate 해도 여전히 Class C)
Class C * 100 != Class A/B 승급 근거
```

---

## 재구성 거리 보존 (Reconstruction Distance Preservation)

### 의도적 설계 거리 선언

CodeBurn 의 acquisition 설계에서 다음 거리는 의도적으로 보존된다:

```
runtime (provider computation)
!=
CodeBurn observation surface (log artifact reading)
```

이 거리는 일시적인 한계가 아니다.
이 거리는 **governance constraint** 이다.

### 핵심 선언

> **reconstruction distance is preserved by design**
> **and must not be treated as a temporary limitation**
> **awaiting runtime convergence.**

### 이 선언이 명시적으로 차단하는 주장

다음 형태의 주장은 이 선언에 의해 금지된다:

- "현재는 log ingestion 을 하지만, 나중에 real-time integration 을 해야 한다"
- "log artifact 는 임시 방편이고, 이상적으로는 provider API 에 직접 접근해야 한다"
- "CodeBurn 이 성숙해지면 runtime wrapper 가 당연히 필요해질 것이다"
- "Phase 1 은 log-based, Phase 2 는 real-time 으로 전환 계획"

이러한 주장은 reconstruction distance 를 "제거해야 할 결함" 으로 취급한다.

```
reconstruction distance = epistemic honesty 의 표현
reconstruction distance != 해결해야 할 기술적 부채
```

### 관련 계약

CODEBURN_ACQUISITION_AUTHORITY_MODEL.md 의 Deferred Runtime Authority Principle:

> "runtime wrapper 의 부재는 governance constraint 이며, 기능적 결핍이 아니다."

---

## 중복 Ingestion 의미론 동결 (Duplicate Ingestion Semantics Freeze)

P4 계약 (CODEBURN_CLAUDE_REPLAY_PROVENANCE_CONTRACT.md) 을 이 freeze 에 편입한다.

### 핵심 구분 (동결)

```
duplicate rows in database
!=
duplicate semantic consumption
```

동일한 artifact 를 두 번 ingest 하면:
- Database 관점: 두 배의 rows 생성 (설계 결정, 버그 아님)
- Evidence 관점: 동일한 소스 위치에 대한 두 번의 재구성 -- 독립 증거 아님

### 소비자 의무

중복 rows 를 처리하는 모든 소비자는:
1. 합산하거나 독립 관찰로 취급하는 것을 금지
2. `(source_artifact_path, source_record_line, source_record_offset)` 로 중복 감지
3. `step_id` 는 중복 감지 키가 아님 (매 ingest 마다 새 UUID 생성)

---

## 의도된 Governance Constraint 목록

CodeBurn 의 현재 경계들은 capability gap 이 아니다.
각 경계는 명시적인 governance decision 의 결과다.

| 경계 | 구현 형태 | 근거 문서 |
|---|---|---|
| Class C (observer-reconstructed) | epistemic_class 필드 | CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md |
| real_time_observed = 0 (hard) | schema CHECK (= 0) | CODEBURN_AUTHORITY_CEILING_CONTRACT.md AC1 |
| analysis_safe_for_decision = 0 (hard) | schema CHECK (= 0) | AC4 |
| provider_truthfulness_assumed = 0 (hard) | schema CHECK (= 0) | AC5 |
| total_tokens = NULL (always) | 필드 정책 | CODEBURN_CLAUDE_ARTIFACT_CONTRACT.md |
| cache tokens not stored | 필드 정책 | CODEBURN_CLAUDE_ARTIFACT_CONTRACT.md |
| cross-provider aggregation forbidden | comparability policy | CODEBURN_CROSS_PROVIDER_COMPARABILITY_BOUNDARY.md P1 |
| reconstruction distance preserved | 설계 원칙 | CODEBURN_ACQUISITION_AUTHORITY_MODEL.md |
| duplicate rows != semantic consumption | replay policy | CODEBURN_CLAUDE_REPLAY_PROVENANCE_CONTRACT.md |
| temporal stability ->/ epistemic promotion | Temporal Non-Promotion Rule | CODEBURN_ACQUISITION_SEMANTIC_FREEZE.md (TNP) |

이 목록의 어떤 항목도 "임시로 이렇게 한다" 가 아니다.
모두 "이것이 올바른 접근이기 때문에 이렇게 한다" 다.

---

## 이 시스템이 현재 할 수 없는 것 (What This System Cannot Do)

이것들은 능력의 부재가 아니라, 의도적인 경계다.

**증명할 수 없는 것:**
- provider 가 token 을 올바르게 계산했음
- log artifact 가 runtime 활동을 완전히 기록했음
- 두 provider 의 token 측정이 동일한 basis 를 가짐
- Class C evidence 가 decision 을 내리기에 충분함

**계산할 수 없는 것:**
- cross-provider token 합계
- provider 간 비용 비교
- "AI 총 사용량" 과 같은 cross-session aggregate
- provider efficiency ranking

**승급할 수 없는 것:**
- 어떤 조건에서도 Class C 는 Class A/B 가 될 수 없음
  (이를 위해서는 새로운 constitutional contract 이 필요함)

---

## 핵심 공리: Anti-Collapse Axiom

이것은 FSP-1..FSP-5 의 개별 금지 규칙이 아니다.

이것은 이 문서 전체의 **meta-boundary invariant** 다.

### 공리 선언

> **Stable reconstruction does not collapse observation distance.**

### 이 공리가 보호하는 것

이 공리는 다음의 추론 사슬을 원천 차단한다:

```
replay determinism stable
->/ observation distance collapsed

provenance identity consistent
->/ runtime reality verified

cross-run reconstruction consistent
->/ provider computation confirmed

"모든 것이 안정적이다"
->/ "실제와 동일하다"
```

### 이 공리가 필요한 이유

technical stability 는 epistemic upgrade 의 근거가 아니다.

재구성이 안정적이라는 것은:
- 재구성 방법이 일관적임을 의미한다
- runtime 에서 실제로 일어난 일과 재구성이 일치함을 의미하지 않는다

관찰 거리는 재구성의 품질로 제거되지 않는다.
관찰 거리는 관찰 구조(epistemic position) 로 결정되며,
이것은 CodeBurn 이 log artifact 를 읽는 시점에 이미 확정된다.

```
reconstruction stability  = 재구성 방법이 일관적
observation distance      = CodeBurn 과 runtime 사이의 구조적 간격
reconstruction stability  ->/ observation distance collapse
```

### 이 공리와 FSP 의 관계

FSP-1..FSP-5 는 구체적인 금지 추론의 목록이다.
이 공리는 그 목록을 생성하는 근거다.

FSP 들이 열거하는 것: "이것도 안 되고, 저것도 안 되고"
이 공리가 말하는 것: "왜 안 되는가 -- reconstruction stability 와 observation distance 는 독립적이다"

---

## 시간 비승격 규칙 (Temporal Non-Promotion Rule)

이것은 Anti-Collapse Axiom 의 **시간 축 동반 규칙** 이다.

### Anti-Collapse Axiom 과의 차이

Anti-Collapse Axiom 이 차단하는 것:
> "이 순간 안정적이다 → 관찰 거리가 사라진다"

Temporal Non-Promotion Rule 이 차단하는 것:
> "**오랫동안** 안정적이었다 → 권위가 높아진다 → 더 많은 것이 허용된다"

전자는 **현재의 안정성**을 epistemic upgrade 의 근거로 사용하는 것을 금지한다.
후자는 **시간의 누적**을 epistemic upgrade 의 근거로 사용하는 것을 금지한다.

두 규칙은 별개의 drift 경로를 차단한다.

### 규칙 선언

```
Replay stability, persistence, or historical consistency
MUST NOT upgrade:
  - provider equivalence,
  - field equivalence, or
  - aggregation admissibility.
```

시간 차원은 독립적인 승격 경로가 아니다.

### 이 규칙이 차단하는 drift 사슬

다음 추론 사슬은 이 규칙에 의해 금지된다:

```
Codex replay 결과가 6개월 동안 일관적이었다
→ historical calibration 이 충분히 이루어졌다
→ Codex 데이터의 가중치를 높여야 한다
→ Claude 와 partial normalize 하는 것이 합리적이다
```

각 단계는 그 자체로 그럴 듯하게 들린다.
단계가 쌓일수록 최초 금지가 보이지 않게 된다.
이것이 시간 차원 drift 의 특성이다.

### 두 개의 명시적 금지 예시

```
FORBIDDEN: replay-consistent ->/ measurement-equivalent
FORBIDDEN: historically-stable ->/ cross-provider-normalizable
```

**첫 번째**: replay 결과가 일치한다는 것은 재구성 방법이 일관적임을 의미한다.
측정 방식이 동일하다는 것을 의미하지 않는다.

**두 번째**: 데이터가 역사적으로 안정적이었다는 것은 재구성이 반복 가능함을 의미한다.
다른 provider 와 normalization 할 수 있다는 것을 의미하지 않는다.

### 금지되는 이유

시간은 epistemic position 을 바꾸지 않는다.

CodeBurn 의 observation distance 는 log artifact 를 읽는 구조에서 발생한다.
이 구조는 observation 횟수나 기간이 늘어난다고 변화하지 않는다.

```
100번의 consistent replay = 재구성 방법이 안정적
100번의 consistent replay != epistemic distance 감소
100번의 consistent replay != calibration authority 증가
```

### 이 규칙과 FSP 및 Anti-Collapse Axiom 의 관계

FSP-1 은 단일 시점의 안정성 →/ correctness 를 차단한다.
Anti-Collapse Axiom 은 안정성 →/ 거리 소멸을 차단한다.
Temporal Non-Promotion Rule 은 **시간 누적** →/ **권위 증가** →/ **추가 허가** 를 차단한다.

셋은 동일한 보호 대상(관찰 거리) 을 서로 다른 drift 경로에서 보호한다.

---

*이 freeze 는 시스템이 유용해 보이기 시작하는 순간을 위한 것이다.*
*유용성이 인식될 때 가장 먼저 침식되는 것은 경계다.*
*이 문서는 그 침식을 사전에 차단한다.*
