# CodeBurn -- Provider 2 Admission Gate

> Written: 2026-05-21
> Status: **BINDING** -- P5 semantic admissibility gate
> Scope: P5 (Codex CLI) and all future multi-provider acquisition work
> Depends on: CODEBURN_ACQUISITION_SEMANTIC_FREEZE.md,
>             CODEBURN_CROSS_PROVIDER_COMPARABILITY_BOUNDARY.md,
>             CODEBURN_TOKEN_PROVENANCE_ONTOLOGY.md
> Role: admission gate -- P5 cannot begin until all conditions below are met

---

## 이 문서의 역할

이 문서는 project management checklist 가 아니다.

이 문서는 **semantic admissibility gate** 다.

P5 (Codex CLI acquisition) 는 이 문서의 모든 조건이 충족될 때까지 시작할 수 없다.

이것은 engineering 준비 여부의 문제가 아니다.
이것은 **semantic readiness** 의 문제다.

gate 를 통과한 P5 는 더 강하다.
gate 를 우회한 P5 는 더 위험하다.

---

## P5 입장 조건 (Provider 2 Entry Conditions)

**P5 cannot begin until all of the following conditions are met.**

---

### 조건 AG-1: Comparability Boundary Reaffirmation

CODEBURN_CROSS_PROVIDER_COMPARABILITY_BOUNDARY.md 의 영구 금지 항목이
Codex 도입 이후에도 동일하게 적용됨이 reaffirm 되었음:

- [ ] P1 (cross-provider aggregation): 영구 금지 -- Codex 추가 후에도 동일
- [ ] P2 (cross-class comparison): 영구 금지 -- Codex 추가 후에도 동일
- [ ] P3 (unlabeled aggregation): 영구 금지 -- Codex 추가 후에도 동일
- [ ] P4 (normalization for comparison): 영구 금지 -- Codex 추가 후에도 동일
- [ ] P5 (efficiency inference): 영구 금지 -- Codex 추가 후에도 동일

reaffirmation 은 단순 확인이 아니다.
Codex 도입 후 새롭게 발생할 수 있는 비교 압력에 대해
각 금지 항목이 여전히 적용됨을 명시적으로 확인하는 것이다.

---

### 조건 AG-2: Acquisition Non-Equivalence Acknowledgement

다음이 명시적으로 인정되었음:

- [ ] Claude .jsonl ingestion 과 Codex CLI acquisition 은
  서로 다른 acquisition path 를 가질 가능성이 있음
- [ ] 서로 다른 acquisition path 는 epistemically non-equivalent evidence 를 생성함
- [ ] 두 경로가 모두 Class C 를 생성하더라도
  그것이 비교 가능성을 의미하지 않음
- [ ] "둘 다 Class C 이므로 합산할 수 있다" 는 추론은 FSP-3 위반임

---

### 조건 AG-3: Schema Similarity Disclaimer

다음이 명시적으로 확인되었음:

- [ ] Codex artifact 에 `input_tokens`, `output_tokens` 필드가 존재하더라도
  Claude 의 동일 필드와 measurement equivalence 를 가정하지 않음
- [ ] field name similarity ->/ measurement equivalence (명시적 확인)
- [ ] field name similarity ->/ comparability admissibility (명시적 확인)
- [ ] field name similarity ->/ aggregation authorization (명시적 확인)

상세 근거는 이 문서의 "Schema Similarity != Provenance Equivalence" 절 참조.

---

### 조건 AG-4: Semantic Freeze Acknowledgement

- [ ] CODEBURN_ACQUISITION_SEMANTIC_FREEZE.md 가 binding 상태로 존재함
- [ ] FSP-1 (replay stability ->/ provider correctness) 검토 완료
- [ ] FSP-2 (cross-run consistency ->/ runtime completeness) 검토 완료
- [ ] FSP-3 (multiple Class C ->/ comparability admissibility) 검토 완료
- [ ] FSP-4 (provider-reported ->/ provider-actual) 검토 완료
- [ ] FSP-5 (acquisition coverage growth ->/ governance authority growth) 검토 완료
- [ ] Reconstruction Distance Preservation 선언 검토 완료

---

### 조건 AG-5: Codex-Specific Artifact Contract Required

P5 는 사전에 Codex 전용 artifact contract 를 필요로 한다.

- [ ] Codex CLI 의 출력 형식 분석 완료 (P3.0 에서 Claude 를 분석했던 것과 동일하게)
- [ ] Codex artifact 의 admissible fields 정의 완료
- [ ] Codex artifact 의 inadmissible fields 명시 완료
- [ ] Codex 의 epistemic class 가 독립적으로 결정됨
  (Claude 가 Class C 이기 때문에 Codex 도 Class C 라는 추론은 허용되지 않음)
- [ ] Codex 전용 schema extension 이 승인됨
  (Claude 용 schema 를 shared schema 로 재해석하는 것은 허용되지 않음)

---

### 조건 AG-6: Adversarial Re-Interpretation Requirement

이 조건은 다른 조건들과 다르다.

AG-1..AG-5 는 "확인했음" 을 요구한다.
AG-6 은 **"실제로 문제를 찾으려고 시도했음"** 을 요구한다.

absence of detected issues != presence of adversarial search

이 조건은 gate 가 ceremonial authorization 으로 퇴화하는 것을 막기 위해 존재한다.

#### Copy-Forward Reasoning 금지

다음은 AG-6 의 충족 근거로 인정되지 않는다:

- [ ] (이 항목이 채워져 있으면 AG-6 는 통과되지 않음)
  - 이전 provider 입장 시 작성된 review 를 인용하는 것
  - "지난번에 검토했으므로 이번에도 괜찮다" 는 추론
  - 이전 sign-off 를 현재 sign-off 의 근거로 사용하는 것

```
FORBIDDEN: "Prior Provider2 admission conclusions are sufficient
           evidence for current semantic admissibility."
```

이유: semantic novelty 는 precedent 로 평가할 수 없다.
새로운 provider admission 은 새로운 semantic surface 를 도입한다.
이전 review 는 이전 surface 에 대한 review 이며, 현재 surface 에 유효하지 않다.

#### 필수 산출물 (Required Adversarial Outputs)

AG-6 이 충족되려면 다음 세 항목이 실제로 작성되어야 한다.
이 항목들은 "발견되지 않았음" 을 포함해서 명시적으로 기록해야 한다.

**Output 1: Hidden Comparability Assumptions**

- [ ] 이 provider 도입이 암묵적으로 가정하는 비교 가능성이 있는가?
  - 발견된 항목: [기록 필요]
  - "없음" 도 명시적으로 기록되어야 함

**Output 2: Authority Expansion Vectors**

- [ ] 이 provider 도입이 CodeBurn 의 authority 를 확장할 수 있는 경로가 있는가?
  (acquisition coverage growth ->/ governance authority growth 를 유발하는 경로)
  - 발견된 항목: [기록 필요]
  - "없음" 도 명시적으로 기록되어야 함

**Output 3: Semantic Implications Differing from Prior Admissions**

- [ ] 이 provider admission 이 이전 provider admission 과 다른
  semantic implications 를 가지는 부분이 있는가?
  - 발견된 항목: [기록 필요]
  - "없음" 도 명시적으로 기록되어야 함

#### AG-6 의 목적

이 세 Output 이 모두 비어 있다면:

adversarial review 가 수행되었다 (X)
adversarial review 가 시도되었다 (O)

두 outcome 모두 acceptable 하다.
중요한 것은 시도의 흔적 (artifact of attempted semantic attack) 이 남아있는 것이다.

흔적이 없는 review 는 review 가 아니라 declaration 이다.

---

## 금지된 Narrative (Prohibited Narratives)

P5 도입 전후를 막론하고 다음 narrative 는 CodeBurn 내에서 영구 금지된다.
새로운 constitutional upgrade 없이는 해제될 수 없다.

### 비용 비교 금지

다음 형태의 주장은 금지된다:

```
FORBIDDEN: "Provider X is cheaper than Provider Y"
FORBIDDEN: "Codex token cost is lower than Claude token cost"
FORBIDDEN: "Based on token counts, Provider X is more cost-efficient"
FORBIDDEN: "Total AI cost this month is ..."
```

이유: Class C evidence 는 billing computation 에 admissible 하지 않다.
token_source = 'estimated' 이며, provider 가 실제로 청구한 금액과 동일하지 않다.
cross-provider 합산은 CODEBURN_CROSS_PROVIDER_COMPARABILITY_BOUNDARY.md P1 위반이다.

### 완전성 비교 금지

```
FORBIDDEN: "Provider Y logs are more complete than Provider X"
FORBIDDEN: "Claude logs have better coverage than Codex logs"
FORBIDDEN: "Provider X reports more tokens, so it is more transparent"
```

이유: log artifact 의 completeness 는 CodeBurn acquisition 으로 검증할 수 없다.
reconstruction distance 가 그 판단을 구조적으로 불가능하게 한다.

### 진실성 비교 금지

```
FORBIDDEN: "Provider Z is more truthful"
FORBIDDEN: "Codex reports are more accurate than Claude reports"
FORBIDDEN: "Provider X's token counts are more trustworthy"
```

이유: provider_truthfulness_assumed = 0 은 모든 provider 에 동등하게 적용된다.
어떤 provider 도 다른 provider 보다 더 "truthful" 하다고 판단할 수 없다.

### 집계 비교 금지

```
FORBIDDEN: "Cross-provider token totals are decision-safe"
FORBIDDEN: "Combined Claude + Codex usage is X tokens"
FORBIDDEN: "Total AI expenditure across providers is ..."
FORBIDDEN: "If we add up Claude and Codex, the total is ..."
```

이유: CODEBURN_CROSS_PROVIDER_COMPARABILITY_BOUNDARY.md P1, P3 위반.
cross-provider aggregation 은 epistemic class 를 막론하고 영구 금지다.

---

## Schema Similarity != Provenance Equivalence

이 원칙은 다중 provider 환경에서 특별히 강화된다.

### 예측되는 상황

Codex CLI 는 다음과 같은 구조를 가질 가능성이 높다:

```json
{
  "input_tokens": 1234,
  "output_tokens": 56
}
```

Claude .jsonl 도 동일한 필드명을 사용한다:

```json
"usage": {
  "input_tokens": 1234,
  "output_tokens": 56
}
```

### 예측되는 (잘못된) 추론

> "두 provider 모두 input_tokens 와 output_tokens 를 사용하니까
> 같은 방식으로 측정하는 것이고, 비교할 수 있다."

이 추론은 명시적으로 금지된다.

### 금지된 추론 (명시)

```
field name similarity ->/ measurement equivalence
field name similarity ->/ comparability admissibility
field name similarity ->/ aggregation authorization
field name similarity ->/ same counting methodology
field name similarity ->/ same billing alignment
```

### 이유

동일한 필드명이 다음을 보장하지 않는다:
- 동일한 tokenizer 사용
- 동일한 context window counting 방식
- 동일한 cache token 처리
- 동일한 billing precision
- 동일한 acquisition context (streaming vs batch 등)

```
schema field = label
label similarity != measurement equivalence
label similarity != provenance equivalence
```

이것은 FSP-3 (Multiple Class C Sources ->/ Comparability Admissibility) 의
schema 차원 표현이다.

---

## 다중 Provider 환경에서의 Class C 의미 보존

P5 이후 시스템에는 두 개의 Class C evidence stream 이 존재한다:

```
Claude session logs  -> Class C (observer-reconstructed)
Codex CLI acquisition -> Class C (observer-reconstructed)
```

두 stream 이 동일한 epistemic class 를 가지더라도:

**명시적으로 금지되는 것:**

1. 두 stream 을 합산해서 "total AI token usage" 계산
2. 두 stream 을 비교해서 "provider efficiency" 또는 "provider quality" 판단
3. 둘 중 하나가 "더 나은 Class C" 라는 ranking 생성
4. 두 Class C source 가 동일한 measurement basis 를 가진다는 가정

**명시적으로 허용되는 것:**

1. 각 provider 를 독립적으로, within-session 기준으로 분석
2. 각 provider 의 ingestion completeness 를 독립적으로 측정
3. 각 provider 의 data quality 를 독립적으로 report
4. 각 provider 의 quarantine rate 를 독립적으로 관찰
5. 각 provider 의 Class C evidence 를 독립적인 관찰 기록으로 보관

---

## Gate Sign-off

이 gate 의 모든 조건이 충족된 후,
P5 시작을 위해 다음을 명시적으로 기록해야 한다:

```
P5 Admission: GRANTED
Gate conditions: AG-1, AG-2, AG-3, AG-4, AG-5, AG-6 -- all confirmed
Prohibited narratives: acknowledged
Schema similarity disclaimer: acknowledged
Codex artifact contract: [contract document path]
Anti-collapse axiom: acknowledged
Copy-forward reasoning: not used
AG-6 Output 1 (hidden comparability assumptions): [findings or NONE FOUND]
AG-6 Output 2 (authority expansion vectors): [findings or NONE FOUND]
AG-6 Output 3 (semantic diff from prior admissions): [findings or NONE FOUND]
Date: [ISO date]
```

이 기록이 없으면 P5 는 시작할 수 없다.

AG-6 의 세 Output 이 "NONE FOUND" 인 경우도 허용된다.
그러나 Output 자체가 누락된 경우는 AG-6 미충족으로 간주된다.

---

*이 gate 는 P5 를 막기 위한 것이 아니다.*
*이 gate 는 P5 가 올바른 semantic basis 위에서 시작되도록 하기 위한 것이다.*
*gate 를 통과한 P5 는 더 강하다. gate 를 우회한 P5 는 더 위험하다.*
