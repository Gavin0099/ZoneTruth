# CodeBurn -- Provider 2 (Codex) Adversarial Review

> Written: 2026-05-21
> Status: P5-admission.2 -- AG-6 fulfillment artifact
> Scope: Codex CLI admission adversarial pressure testing
> Depends on: CODEBURN_CODEX_ARTIFACT_SURFACE_RESEARCH.md (attack surface basis),
>             CODEBURN_CODEX_ARTIFACT_CONTRACT.md (invariant basis),
>             CODEBURN_PROVIDER2_ADMISSION_GATE.md (AG-6 requirements)
> Role: attempted semantic attack -- not review, not verification
> Copy-forward reasoning used: NO (all findings are Codex-surface-specific)

---

## 이 문서의 역할

이 문서는 review 가 아니다.

이 문서는 **attempted semantic attack** 이다.

목표는 "문제가 없음을 확인" 이 아니라:
"미래의 사람이 이 boundary 들을 어떻게 조용히 무너뜨릴 수 있는가" 를 미리 시뮬레이션하는 것이다.

성공 기준:
- 많은 plausible drift route 를 발견한다
- 모두 기존 invariant 에 의해 차단됨을 확인한다
- 차단되지 않는 drift route 가 있다면, 그것은 새로운 invariant 의 필요를 의미한다

리뷰 결과가 너무 깨끗하다면, 그것은 adversarial review 가 아니라 declaration 이다.

---

## 방법론

각 attack 의 기술 형식:

```
[attack name]
공격 벡터:   "..." (구체적인 주장 형태)
드리프트 메커니즘:  X → Y → Z (단계별 추론 슬라이딩)
의미론적 결과:  무엇이 침식되는가
차단 invariant: 어떤 규칙이 이것을 막는가
차단 강도:  [hard/soft] -- hard = schema constraint 등, soft = policy only
```

---

## AR-1: Schema Projection Attacks

이 category 는 **필드명 유사성이 comparability 압력을 생성하는** attack 들이다.

### AR-1a: Field Name Gravity Attack

```
공격 벡터: "두 provider 모두 input_tokens, output_tokens 를 사용한다.
           같은 이름이므로 같은 것을 측정하는 것이다."
드리프트: field name similarity
         → assumed measurement equivalence
         → cross-provider token comparison
         → cost/efficiency narrative
의미론적 결과: FSP-3 위반 (multiple Class C →/ comparability admissibility)
차단 invariant: NST-1, NST-5, FSP-3, CODEBURN_CODEX_ARTIFACT_CONTRACT.md IAF-1
차단 강도: soft (policy-based, schema 는 직접 차단 불가)
```

위험 평가: 가장 쉬운 attack 이며, 가장 자연스럽게 발생한다.
"직관적으로 느껴지는" drift 이기 때문에 특히 위험하다.

### AR-1b: First-Turn Cumulative Camouflage Attack

```
공격 벡터: "첫 번째 turn 에서 total_token_usage 와 last_token_usage 의 값이 동일하다.
           따라서 어느 것을 읽어도 상관없다."
드리프트: first-turn value identity
         → ingestion code uses total_token_usage (simpler access path)
         → second turn: cumulative value ingested as turn-level
         → third turn: values diverge but code is already deployed
         → silent data corruption
의미론적 결과: 세션이 길어질수록 ingested token 수가 exponentially 과장됨
차단 invariant: IAF-1 (total_token_usage.* 는 always inadmissible, turn 수 무관)
차단 강도: soft (code-level enforcement required in ingestor)
```

위험 평가: 매우 위험. 첫 번째 turn 에서는 테스트가 통과하기 때문에 버그를 발견하기 어렵다.
smoke test 와 fixture 설계 시 반드시 multi-turn session 을 포함해야 한다.

### AR-1c: Cache Token Semantic Proxy Attack

```
공격 벡터: "두 provider 모두 cache 관련 token 을 기록한다.
           Claude 는 cache_read_input_tokens, Codex 는 cached_input_tokens.
           이름이 다를 뿐 같은 개념이므로 비교하거나 합산할 수 있다."
드리프트: similar concept (cache hit) recognized across providers
         → treat as comparable operational metric
         → aggregate cache efficiency across providers
         → "Claude caches better than Codex" narrative
의미론적 결과: cross-provider comparison via proxy fields
차단 invariant: NST-2, IAF-4, FSP-3
차단 강도: soft
```

### AR-1d: Class C Convergence Attack

```
공격 벡터: "Claude 도 Class C, Codex 도 Class C.
           같은 epistemic class 이므로 동일한 신뢰도를 가지며 비교 가능하다."
드리프트: same label
         → assumed same epistemic quality
         → comparability
         → cross-provider aggregate
의미론적 결과: FSP-3 의 핵심 위반 (multiple Class C →/ comparability)
차단 invariant: FSP-3, Anti-Collapse Axiom (같은 reconstruction 방식이 같은 관찰 거리를 의미하지 않음)
차단 강도: soft
```

### AR-1e: Token Source Convergence Attack

```
공격 벡터: "두 provider 의 token_source = 'estimated'.
           둘 다 estimated 이므로 동일한 estimation basis 를 가진다."
드리프트: same token_source value
         → assumed same estimation methodology
         → estimated + estimated = double-estimated, comparable
         → cross-provider token confidence assessment
의미론적 결과: token_source 를 comparability basis 로 오용
차단 invariant: FSP-3, NST-1..5
차단 강도: soft
```

---

## AR-2: Completeness Superiority Attacks

이 category 는 **acquisition surface 가 hierarchy 를 형성하는** attack 들이다.

### AR-2a: SQLite Persistence Superiority Attack

```
공격 벡터: "JSONL 파일은 write 중단으로 truncated 될 수 있다.
           SQLite 는 ACID 트랜잭션이 있으므로 더 reliable 하다.
           따라서 SQLite 에서 읽는 것이 더 완전한 증거다."
드리프트: SQLite persistence reliability
         → completeness superiority
         → provenance superiority
         → should switch acquisition surface to SQLite
         → JSONL-based provenance identity is suboptimal
의미론적 결과: Dual Acquisition Surface Rule 위반 + provenance identity 포기
차단 invariant: Dual Acquisition Surface Rule (surface completeness →/ provenance superiority)
차단 강도: soft
비고: JSONL 선택 이유는 truthfulness 가 아니라 line/offset provenance identity 가능성이다.
     SQLite 가 더 reliable 해도 provenance identity 를 지원하지 않는다.
```

### AR-2b: Session Index Verification Attack

```
공격 벡터: "session_index.jsonl 을 통해 모든 세션 ID 를 알 수 있다.
           이를 통해 모든 세션이 ingested 되었는지 검증할 수 있다.
           따라서 우리는 acquisition completeness 를 보장할 수 있다."
드리프트: session index awareness
         → can verify all sessions ingested
         → acquisition completeness claim
         → governance authority expansion ("우리는 완전히 기록했다")
의미론적 결과: FSP-5 위반 (acquisition coverage growth →/ governance authority growth)
차단 invariant: FSP-5, AC1 (Runtime Authority Ceiling)
차단 강도: soft
```

### AR-2c: Cross-Surface Consistency Verification Attack

```
공격 벡터: "JSONL 에서 읽은 token 수와 state_5.sqlite 의 threads.tokens_used 가 일치한다면,
           데이터의 일관성이 검증된 것이다. 이것은 더 신뢰할 수 있는 증거다."
드리프트: cross-surface consistency check
         → verified evidence
         → elevated epistemic status (beyond Class C)
         → "since both sources agree, this is provider-confirmed"
의미론적 결과: Anti-Collapse Axiom 위반 (consistency →/ provider truth)
차단 invariant: Anti-Collapse Axiom, FSP-4 (provider-reported →/ provider-actual)
차단 강도: soft
비고: 두 surface 의 일치는 provider 가 올바르게 계산했음을 증명하지 않는다.
```

### AR-2d: JSONL Line Count Authority Attack

```
공격 벡터: "JSONL 파일의 token_count 레코드 수를 세면 세션의 turn 수를 알 수 있다.
           이를 통해 sesson completeness 를 확인할 수 있다."
드리프트: line counting capability
         → turn count verification
         → completeness verification authority
         → "we can certify this session is complete"
의미론적 결과: CodeBurn 이 session completeness 를 certify 하는 authority 획득
차단 invariant: FSP-5, reconstruction distance preservation
              (CodeBurn 은 log 를 읽는다 -- session 이 완전한지 판단할 수 없다)
차단 강도: soft
```

---

## AR-3: Reasoning Assimilation Attacks

이 category 는 **reasoning_output_tokens 를 일반 token semantics 에 편입하는** attack 들이다.

### AR-3a: "Just Add It Up" Attack

```
공격 벡터: "total_output = output_tokens + reasoning_output_tokens.
           이것이 실제 token 사용량의 전체 그림이다.
           더하면 완전한 값을 얻을 수 있다."
드리프트: arithmetic aggregation desire
         → reasoning + visible output = "real" output
         → total output billing computation
         → cost comparison with Claude
의미론적 결과: IAF-2, IAF-3 위반 + billing computation authorization 주장
차단 invariant: IAF-2 (reasoning_output_tokens inadmissible),
               IAF-3 (total_tokens inadmissible),
               Reasoning Separation Principle
차단 강도: soft
```

### AR-3b: Reasoning as Cache Overhead Attack

```
공격 벡터: "reasoning_output_tokens 는 cache tokens 처럼 '내부 overhead' 다.
           cache tokens 와 동일하게 취급하면 된다 -- 즉, inadmissible 이지만 무해하다."
드리프트: reasoning = overhead category
         → symmetric treatment with cache tokens
         → future admission possible ("cache tokens 도 언젠가 admissible 해질 수 있다")
         → reasoning tokens 에 대한 conditional admission 논의 시작
의미론적 결과: NST-4 위반 + reasoning 에 대한 future admission pressure 생성
차단 invariant: NST-4 (reasoning_output_tokens →/ any Claude token category),
               Reasoning Separation Principle
차단 강도: soft
```

### AR-3c: "Zero Reasoning Turn" Comparability Attack

```
공격 벡터: "reasoning_output_tokens = 0 인 turn 에서는
           Codex 의 output_tokens = Claude 의 output_tokens 와 동일한 의미다.
           non-reasoning turns 에 한해서는 비교할 수 있다."
드리프트: conditional comparability (zero-reasoning turns only)
         → selective cross-provider comparison
         → "at least for simple responses we can compare"
         → erosion of blanket non-comparability rule
의미론적 결과: FSP-3 의 조건부 위반 -- "특별한 경우" 예외가 drift의 시작점이 됨
차단 invariant: NST-5, FSP-3
               (금지는 reasoning_output_tokens 값에 관계없이 적용됨)
차단 강도: soft
비고: "특별한 경우" 예외를 허용하는 것이 가장 흔한 drift pattern 이다.
```

### AR-3d: Provider Efficiency Inference Attack

```
공격 벡터: "reasoning_output_tokens / output_tokens 비율이 높다면
           모델이 더 많이 생각하고 있다는 것이다.
           이 비율이 높은 provider 가 더 sophisticated 하다."
드리프트: token ratio → reasoning quality inference
         → provider sophistication ranking
         → governance claim ("Codex is more capable")
의미론적 결과: AC3 위반 (Evaluative Authority), FSP-3, IAF-2
차단 invariant: AC3, FSP-3, Reasoning Separation Principle
차단 강도: soft
```

### AR-3e: Reasoning Stability Anti-Collapse Attack

```
공격 벡터: "reasoning_output_tokens 가 replay 에서 안정적이라면
           reasoning 이 일관적으로 발생했음을 알 수 있다.
           이것은 provider 의 reasoning 동작을 이해하는 데 유용하다."
드리프트: reasoning token replay stability
         → stable reasoning behavior observation
         → runtime reasoning characterization
         → provider behavioral modeling
의미론적 결과: Anti-Collapse Axiom 위반 (reconstruction stability →/ runtime truth)
차단 invariant: Anti-Collapse Axiom, AC1 (Runtime Authority)
차단 강도: soft
```

---

## AR-4: Replay Stability Inflation Attacks

이 category 는 **결정론적 replay 가 epistemic 승급의 근거가 되는** attack 들이다.
이것들은 Anti-Collapse Axiom 에 대한 직접 공격이다.

### AR-4a: "Stable Telemetry" Attack

```
공격 벡터: "Codex 의 JSONL 은 deterministic 하게 replay 된다.
           이것은 신뢰할 수 있는 telemetry 임을 의미한다.
           신뢰할 수 있는 telemetry = 더 높은 epistemic quality."
드리프트: replay determinism
         → reliable telemetry
         → trustworthy data
         → provider_truthfulness_assumed could be relaxed
의미론적 결과: Anti-Collapse Axiom 의 핵심 violation
차단 invariant: Anti-Collapse Axiom
               ("Stable reconstruction does not collapse observation distance.")
차단 강도: soft (Anti-Collapse Axiom 자체가 이 attack 을 위해 존재)
```

### AR-4b: Cross-Run Verification Attack

```
공격 벡터: "동일한 Codex session 을 두 번 ingest 해서 동일한 (line, offset) 을 얻었다.
           이것은 데이터가 검증되었음을 의미한다.
           검증된 데이터 = 더 reliable = epistemic upgrade"
드리프트: replay stability
         → data verification
         → epistemic upgrade (Class C → Class B or A)
의미론적 결과: CODEBURN_CLAUDE_REPLAY_PROVENANCE_CONTRACT.md Boundary 1 위반
               + Anti-Collapse Axiom 위반
차단 invariant: Anti-Collapse Axiom,
               Replay Provenance Contract Boundary 1
               ("replay stable != runtime observed")
차단 강도: soft
```

### AR-4c: Provenance Identity Truth Attack

```
공격 벡터: "(artifact_path, line, offset) 의 조합이 유일하게 결정된다.
           이 위치에서 추출된 값은 권위 있는 기록이다.
           권위 있는 기록 = provider truth."
드리프트: unique identification
         → authoritative record
         → provider truth
의미론적 결과: FSP-4 위반 (provider-reported →/ provider-actual)
차단 invariant: FSP-4, Anti-Collapse Axiom
차단 강도: soft
```

### AR-4d: Dual Provider Stability Convergence Attack

```
공격 벡터: "Claude 도 replay stable, Codex 도 replay stable.
           둘 다 같은 stability property 를 가지므로 같은 epistemic quality 를 가진다.
           같은 epistemic quality = 비교 가능하다."
드리프트: same stability property
         → same epistemic quality
         → comparability
         → FSP-3 erosion
의미론적 결과: FSP-3 위반, Anti-Collapse Axiom 위반
차단 invariant: FSP-3, Anti-Collapse Axiom, NST-1..5
차단 강도: soft
비고: 이것은 AR-1d (Class C Convergence) 의 replay 차원 변형이다.
     같은 drift 가 다른 각도에서 반복해서 시도된다.
```

### AR-4e: "Growing Confidence" Accumulation Attack

```
공격 벡터: "같은 세션을 1000번 ingesting 해도 같은 결과가 나온다.
           이 정도의 반복이라면 그것은 사실상 검증된 것이나 다름없다."
드리프트: repetition count
         → confidence accumulation
         → de facto verification
         → epistemic class upgrade pressure
의미론적 결과: Anti-Collapse Axiom 의 가장 극단적인 형태 위반
차단 invariant: Anti-Collapse Axiom (반복은 관찰 거리를 줄이지 않는다)
               CODEBURN_CLAUDE_REPLAY_PROVENANCE_CONTRACT.md Boundary 1
차단 강도: soft
비고: 이것은 "무한히 반복하면 확률은 0에 가까워진다" 류의 추론이다.
     관찰 거리는 반복 횟수가 아니라 관찰 구조(epistemic position)로 결정된다.
```

---

## AG-6 Required Outputs

Copy-forward reasoning 사용 여부: **NO**
이 review 는 이전 어떤 provider admission 의 결론도 인용하지 않는다.
모든 발견은 Codex 특유의 artifact surface 에 근거한다.

---

### Output 1: Hidden Comparability Assumptions

이 provider 도입이 암묵적으로 가정하는 비교 가능성:

**발견된 항목:**

1. **Field name gravity** (AR-1a): `input_tokens`/`output_tokens` 필드명이 동일하므로
   직관적으로 "같은 것을 측정한다" 고 가정하게 된다.
   이것은 가장 광범위하게 퍼질 수 있는 숨겨진 가정이다.

2. **Cache token proxy comparability** (AR-1c): 두 provider 모두 cache token 을 기록한다는
   사실이 "cache efficiency 는 비교 가능하다" 는 숨겨진 가정을 생성한다.

3. **Zero-reasoning-turn selective comparability** (AR-3c): reasoning_output_tokens = 0 인 경우
   output_tokens 가 비교 가능하다는 조건부 가정이 숨어있다.
   이것은 "특별한 경우" 예외로 drift 를 시작시키는 가정이다.

4. **Class C equivalence gravity** (AR-1d): 두 provider 가 모두 Class C 이므로
   "같은 신뢰 수준" 이라는 숨겨진 가정이 있다.

5. **Cross-surface consistency as verification** (AR-2c): JSONL 과 SQLite 가 일치하면
   "검증되었다" 는 숨겨진 가정이 있다.

---

### Output 2: Authority Expansion Vectors

이 provider 도입이 CodeBurn 의 authority 를 확장할 수 있는 경로:

**발견된 항목:**

1. **Session completeness authority** (AR-2b): session_index.jsonl 로 모든 세션을 알 수 있으므로
   "모든 세션이 ingested 되었다" 를 claim 하려는 압력이 생긴다.
   이것은 acquisition completeness authority 확장이다.

2. **Replay verification authority** (AR-4b): 두 번 ingest 해서 동일한 결과를 얻으면
   "검증했다" 고 claim 하는 authority 확장이다.

3. **Reasoning behavior characterization authority** (AR-3e): reasoning token 의 재현성을
   근거로 "provider 의 reasoning 동작을 characterize 할 수 있다" 는 authority 확장이다.

4. **Cross-surface consistency certification authority** (AR-2c): 두 surface 가 일치할 때
   "데이터가 certified 되었다" 고 주장하는 authority 확장이다.

5. **Turn count verification authority** (AR-2d): token_count 레코드 수 counting 으로
   "session completeness 를 verify 할 수 있다" 는 authority 확장이다.

이 authority expansion vectors 는 모두 FSP-5 (acquisition coverage →/ governance authority) 와
재구성 거리 보존 원칙으로 차단된다.

---

### Output 3: Semantic Implications Differing from Prior Admissions (Claude)

이 Codex admission 이 Claude admission 과 다른 semantic implications:

**발견된 항목:**

1. **Reasoning token asymmetry** (AR-3): Claude 는 reasoning 전용 token category 를 노출하지 않는다.
   Codex 는 노출한다. 이것은 output_tokens 의 의미를 비대칭적으로 만든다.
   Claude admission 에는 이 asymmetry 가 없었다.
   **Reasoning Separation Principle 이 이 asymmetry 로 인해 Codex admission 에서 처음 도입되었다.**

2. **Dual acquisition surface** (AR-2): Claude 는 JSONL 단일 surface 를 가진다.
   Codex 는 JSONL + SQLite 의 두 surface 를 가진다.
   Claude admission 에는 dual surface drift 가 없었다.
   **Dual Acquisition Surface Rule 이 Codex admission 에서 처음 도입되었다.**

3. **Cumulative vs turn-scoped ambiguity** (AR-1b): Claude 의 token 레코드는 turn-scoped 다.
   Codex 는 동일한 레코드에 cumulative 와 turn-scoped 가 모두 존재한다.
   Claude admission 에는 이 ambiguity 가 없었다.

4. **SQLite as secondary evidence surface** (AR-2): Claude 에는 SQLite 표면이 없다.
   Codex 에는 `threads.tokens_used` 라는 별도 token 표면이 있다.
   이것은 Claude 에 없었던 새로운 surface hierarchy drift vector 다.

5. **`total_tokens` in log** (AR-3a): Claude log 에는 `total_tokens` 가 없다.
   Codex log 에는 있다. 이것이 "이번엔 저장해도 되지 않을까" 압력을 생성한다.
   Claude admission 에서는 이 압력이 없었다.

---

## 차단되지 않는 것 (Open Items)

다음은 현재 invariant 로 **충분히 차단되지 않거나 추가 검토가 필요한** 항목이다:

1. **multi-turn fixture absence**: AR-1b (First-Turn Cumulative Camouflage) 는
   soft policy 로 차단되지만, P5.0 ingestor 구현 시 multi-turn fixture 가 없으면
   이 bug 를 발견하지 못한다.
   **요구**: P5.0 spec/tests 에 반드시 multi-turn session fixture 포함.

2. **reasoning_output_tokens = 0 turn 의 테스트 부재**: AR-3c 의 "zero reasoning turn"
   attack 이 실제 ingestor 에서 발생하지 않는다는 것을 보장하려면
   reasoning = 0 인 fixture 와 reasoning > 0 인 fixture 모두 필요하다.
   **요구**: P5.0 fixture 에 두 케이스 모두 포함.

3. **SQLite surface 의 inadmissibility 가 code 수준에서 강제되지 않음**: IAF-8 은 policy 이며
   schema constraint 가 아니다. ingestor 가 SQLite 를 실수로 읽을 경우 기술적으로 차단되지 않는다.
   **요구**: P5.0 ingestor 가 SQLite 표면을 코드 수준에서 사용하지 않음을 명시적으로 확인.

---

## 리뷰 결론

총 **16개의 plausible drift route** 를 발견하였다.
모두 기존 invariant 에 의해 차단되었음을 확인하였다.

차단 pattern 별 분류:

| 차단 Invariant | 차단한 Attack |
|---|---|
| Anti-Collapse Axiom | AR-4a, AR-4b, AR-4c, AR-4d, AR-4e, AR-2c, AR-3e |
| FSP-3 (Multiple Class C) | AR-1a, AR-1d, AR-1e, AR-3c, AR-4d |
| NST-1..5 | AR-1a, AR-1b, AR-1c, AR-1d, AR-3b, AR-3c, AR-4d |
| Reasoning Separation Principle | AR-3a, AR-3b, AR-3c, AR-3d, AR-3e |
| Dual Acquisition Surface Rule | AR-2a, AR-2c |
| FSP-5 (coverage growth) | AR-2b, AR-2d, AR-4b |
| IAF-1..8 | AR-1b, AR-3a, AR-3d |
| AC3 (Evaluative Authority) | AR-3d |

차단되지 않은 항목: 0개 (그러나 Open Items 3개가 P5.0 구현 시 주의를 요함)

이 review 는 성공적이다.
16개의 drift route 를 발견한 것이 성공이다.
모두 차단된 것이 안전을 의미한다.
Open Items 3개는 P5.0 구현 요구사항으로 전달된다.

---

*이 review 는 "문제가 없다" 를 확인하지 않았다.*
*이 review 는 "문제가 있을 수 있는 곳을 공격하고, 모두 차단됨을 확인" 했다.*
*이 두 가지는 다르다.*
*그리고 두 번째 방식만이 진짜 adversarial review 다.*
