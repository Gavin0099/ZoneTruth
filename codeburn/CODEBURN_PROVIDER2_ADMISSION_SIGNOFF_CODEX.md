# CodeBurn -- Provider 2 (Codex) Admission Sign-off

> Written: 2026-05-21
> Status: **BINDING** -- P5 admission sign-off
> Scope: P5 (Codex CLI) semantic admissibility gate clearance
> Depends on:
>   CODEBURN_CODEX_ARTIFACT_SURFACE_RESEARCH.md (commit 9882d2b)
>   CODEBURN_CODEX_ARTIFACT_CONTRACT.md (commit d98d21d)
>   CODEBURN_PROVIDER2_ADVERSARIAL_REVIEW_CODEX.md (commit 4a2566b)
>   CODEBURN_PROVIDER2_ADMISSION_GATE.md (gate definition)
>   CODEBURN_ACQUISITION_SEMANTIC_FREEZE.md (semantic freeze)
> Role: gate sign-off -- P5.0 may begin after this document is committed

---

## 이 문서의 역할

이 문서는 project management approval 이 아니다.

이 문서는 **semantic admissibility gate clearance** 다.

P5-admission.0 ~ P5-admission.2 를 완료한 후,
AG-1 ~ AG-6 모든 조건이 충족되었음을 명시적으로 기록하는 문서다.

이 문서 없이 P5.0 (Codex ingestor) 를 시작하는 것은 금지된다.
이 문서가 존재하더라도, 아래 조건들이 모두 [x] 로 표시되지 않으면 P5.0 은 blocked 상태다.

---

## AG-1: Comparability Boundary Reaffirmation

CODEBURN_CROSS_PROVIDER_COMPARABILITY_BOUNDARY.md 의 영구 금지 항목이
Codex 도입 이후에도 동일하게 적용됨을 reaffirm 한다.

각 금지 항목에 대해, Codex 도입이 새롭게 생성하는 비교 압력을 명시한다.

- [x] **P1 (cross-provider aggregation): 영구 금지 -- Codex 추가 후에도 동일**

  Codex 가 추가됨으로써 생기는 신규 압력:
  - "Claude session + Codex session 의 총 token" 을 계산하고 싶은 충동
  - "이번 달 AI token 총합" 을 provider 무관하게 집계하려는 동기
  - AR-1d (Class C Convergence) 공격이 이 경로를 통해 P1 을 침식할 수 있음

  확인: Codex 추가 후에도 P1 은 동일하게 적용된다.
  두 개의 Class C stream 이 존재하더라도 cross-provider aggregation 은 불가능하다.

- [x] **P2 (cross-class comparison): 영구 금지 -- Codex 추가 후에도 동일**

  Codex 가 추가됨으로써 생기는 신규 압력:
  - Codex 와 Claude 가 모두 Class C 이므로 "동일 class 비교는 가능하다" 는 추론
  - FSP-3 의 schema 차원 표현 (AR-1d, AR-1e)

  확인: Class C + Class C →/ cross-class comparison authorization.
  Codex 추가 후에도 P2 는 동일하게 적용된다.

- [x] **P3 (unlabeled aggregation): 영구 금지 -- Codex 추가 후에도 동일**

  Codex 가 추가됨으로써 생기는 신규 압력:
  - JSONL line count 가 aggregation 의 "unit" 으로 사용될 수 있는 경로 (AR-2d)
  - reasoning_output_tokens 를 output_tokens 에 합산하는 경로 (AR-3a)

  확인: Codex 추가 후에도 P3 는 동일하게 적용된다.
  IAF-2 (reasoning_output_tokens inadmissible) 가 AR-3a 를 직접 차단한다.

- [x] **P4 (normalization for comparison): 영구 금지 -- Codex 추가 후에도 동일**

  Codex 가 추가됨으로써 생기는 신규 압력:
  - "reasoning 토큰을 빼면 비교 가능하다" 는 normalization 시도 (AR-3c)
  - "zero-reasoning turn 에서만 비교" 라는 selective normalization (AR-3c)

  확인: Codex 추가 후에도 P4 는 동일하게 적용된다.
  Reasoning Separation Principle 이 이 경로를 차단한다.

- [x] **P5 (efficiency inference): 영구 금지 -- Codex 추가 후에도 동일**

  Codex 가 추가됨으로써 생기는 신규 압력:
  - reasoning_output_tokens / output_tokens 비율로 "모델 효율성" 을 추론하는 경로 (AR-3d)
  - dual-provider replay stability 로 "비교 가능한 품질" 을 주장하는 경로 (AR-4d)

  확인: Codex 추가 후에도 P5 는 동일하게 적용된다.
  IAF-2 와 Anti-Collapse Axiom 이 이 경로를 차단한다.

---

## AG-2: Acquisition Non-Equivalence Acknowledgement

- [x] Claude .jsonl ingestion 과 Codex CLI acquisition 은
  서로 다른 acquisition path 를 가진다

  Claude: type=assistant 레코드의 message.usage 필드
  Codex: type=event_msg + payload.type==token_count 레코드의 last_token_usage 필드
  레코드 타입 자체가 다르며, token 데이터의 위치도 다르다.

- [x] 서로 다른 acquisition path 는 epistemically non-equivalent evidence 를 생성한다

  두 경로 모두 JSONL 형식을 사용하지만:
  - 필드 명칭이 유사해도 측정 기준이 다름 (NST-1..5)
  - acquisition path 의 차이가 epistemic non-equivalence 를 생성함
  - path similarity →/ epistemic equivalence

- [x] 두 경로가 모두 Class C 를 생성하더라도 그것이 비교 가능성을 의미하지 않는다

  Codex 의 epistemic class 는 CODEBURN_CODEX_ARTIFACT_CONTRACT.md 에서
  독립적으로 결정되었다 (Claude 가 Class C 이기 때문이 아님).

- [x] "둘 다 Class C 이므로 합산할 수 있다" 는 추론은 FSP-3 위반임

  이 문서에서 이 추론이 명시적으로 금지됨을 확인한다.
  AR-1d (Class C Convergence Attack) 가 이 경로를 문서화하고 차단했다.

---

## AG-3: Schema Similarity Disclaimer

- [x] Codex artifact 에 `input_tokens`, `output_tokens` 필드가 존재하더라도
  Claude 의 동일 필드와 measurement equivalence 를 가정하지 않는다

  NST-1: Claude output_tokens ≠ Codex output_tokens (reasoning scope 차이)
  NST-2: Claude cache_read_input_tokens ≠ Codex cached_input_tokens (필드명도 다름)
  NST-3: Codex total_token_usage →/ Claude-style turn token semantics
  NST-4: reasoning_output_tokens →/ any Claude token category
  NST-5: Codex output_tokens (reasoning 제외) ≠ Claude output_tokens

- [x] field name similarity →/ measurement equivalence (명시적 확인)

  동일한 필드명은 동일한 tokenizer, context counting, billing alignment 를 보장하지 않는다.
  schema field = label; label similarity ≠ measurement equivalence.

- [x] field name similarity →/ comparability admissibility (명시적 확인)

  AR-1a (Field Name Gravity Attack) 가 이 drift route 를 문서화하고 차단했다.
  Reasoning Separation Principle 이 NST-1 을 통해 이 경로를 차단한다.

- [x] field name similarity →/ aggregation authorization (명시적 확인)

  이것은 P3 (unlabeled aggregation) 의 schema 차원 표현이다.
  label similarity 는 aggregation 권한을 부여하지 않는다.

---

## AG-4: Semantic Freeze Acknowledgement

- [x] CODEBURN_ACQUISITION_SEMANTIC_FREEZE.md 가 binding 상태로 존재함

  commit c3fb909 (생성), commit ec7e433 (Anti-Collapse Axiom 추가)
  P5 admission 전에 작성되었으며 이미 binding 상태다.

- [x] FSP-1 (replay stability →/ provider correctness) 검토 완료

  Codex 에 대한 적용: Codex JSONL replay 가 stable 하더라도
  Codex 가 실제 token 을 정확하게 보고한다는 것을 의미하지 않는다.
  AR-4a (Stable Telemetry Trustworthiness Attack) 가 이 경로를 차단했다.

- [x] FSP-2 (cross-run consistency →/ runtime completeness) 검토 완료

  Codex 에 대한 적용: Codex session log 가 여러 run 에서 일치하더라도
  runtime 에서 실제로 발생한 token 사용을 완전히 반영한다는 것이 아니다.
  Reconstruction Distance Preservation 이 이 경로를 차단한다.

- [x] FSP-3 (multiple Class C →/ comparability admissibility) 검토 완료

  Claude Class C + Codex Class C →/ comparability.
  AG-1 에서 각 P1..P5 에 대해 구체적으로 검토 완료.
  AR-1d 가 Class C Convergence Attack 을 문서화했다.

- [x] FSP-4 (provider-reported →/ provider-actual) 검토 완료

  Codex 에 대한 적용: Codex log 의 last_token_usage 는
  Codex 가 실제로 소비한 token 이라는 것을 의미하지 않는다.
  provider_truthfulness_assumed = 0 은 Codex 에도 동일하게 적용된다.
  AR-4c (Provenance Identity Truth Attack) 가 이 경로를 차단했다.

- [x] FSP-5 (acquisition coverage growth →/ governance authority growth) 검토 완료

  Codex 에 대한 적용: Provider 2 추가가 CodeBurn 의 governance authority 를
  확장하지 않는다. AR-2b (Session Index Verification Attack) 가 이 경로를 차단했다.
  AG-6 Output 2 에서 5개 authority expansion vector 가 발견되었다.

- [x] Reconstruction Distance Preservation 선언 검토 완료

  Anti-Collapse Axiom: "Stable reconstruction does not collapse observation distance."
  Codex 에 대한 적용: Codex log replay 가 stable 하더라도
  CodeBurn 의 observation distance 는 유지된다.
  이것은 design intent 이지 technical debt 가 아니다.
  AR-4a..AR-4e (Replay Stability Inflation Attacks) 가 모두 이 공리에 의해 차단되었다.

---

## AG-5: Codex-Specific Artifact Contract Required

- [x] Codex CLI 의 출력 형식 분석 완료

  CODEBURN_CODEX_ARTIFACT_SURFACE_RESEARCH.md (commit 9882d2b).
  live inspection of ~/.codex/ (cli_version=0.130.0-alpha.5).
  4개 레코드 타입, 2개 token usage 객체, SQLite 보조 표면 확인.

- [x] Codex artifact 의 admissible fields 정의 완료

  CODEBURN_CODEX_ARTIFACT_CONTRACT.md (commit d98d21d):
  - last_token_usage.input_tokens (단위 turn 입력)
  - last_token_usage.output_tokens (단위 turn 출력, reasoning 제외)
  - 레코드 최상위 timestamp
  - session_meta.payload.id (세션 UUID)

- [x] Codex artifact 의 inadmissible fields 명시 완료

  IAF-1: total_token_usage.* (세션 누적 -- 중복 집계 위험)
  IAF-2: reasoning_output_tokens (Reasoning Separation Principle)
  IAF-3: total_tokens (billing computation 비승인)
  IAF-4: cached_input_tokens (billing computation 비승인)
  IAF-5: model_context_window (운영 메타데이터)
  IAF-6: rate_limits.* (운영 메타데이터)
  IAF-7: session_meta 운영 필드 (cwd, cli_version, source, model_provider, originator)
  IAF-8: SQLite 표면 전체 (Dual Acquisition Surface Rule)

- [x] Codex 의 epistemic class 가 독립적으로 결정됨

  CODEBURN_CODEX_ARTIFACT_CONTRACT.md §Epistemic Class Determination:
  - Codex 는 독립적으로 Class C 로 결정됨
  - Claude 가 Class C 이기 때문이 아님
  - 결정 근거: observer-reconstructed (CodeBurn 이 artifact 를 해석),
    provider_truthfulness_assumed = 0 (동일 원칙 적용),
    reconstruction distance 존재 (runtime ↔ observation surface gap)
  - 이 결정은 비교 가능성 또는 aggregation 을 승인하지 않음

- [x] Codex 전용 schema extension 이 승인됨

  기존 schema 테이블 사용; 새로운 컬럼 없음.
  reasoning_output_tokens 용 컬럼: 추가 금지 (IAF-2).
  total_tokens 용 컬럼: 추가 금지 (IAF-3).
  total_token_usage.* 용 컬럼: 추가 금지 (IAF-1).
  Claude 용 schema 를 shared schema 로 재해석하는 것: 금지.

---

## AG-6: Adversarial Re-Interpretation Requirement

이 조건은 다른 조건들과 다르다.
AG-6 은 "실제로 문제를 찾으려고 시도했음" 을 요구한다.

Copy-forward reasoning 사용 여부: **사용하지 않음**

이전 provider admission (해당 없음 -- 이것이 첫 번째 추가 provider) 의 결론을
이 sign-off 의 근거로 사용하지 않았다.
모든 findings 는 Codex-surface-specific 분석에서 도출되었다.

AG-6 adversarial review artifact:
CODEBURN_PROVIDER2_ADVERSARIAL_REVIEW_CODEX.md (commit 4a2566b)

16 개의 plausible drift route 가 분석되었다. 모두 기존 invariant 에 의해 차단되었다.

---

### AG-6 Output 1: Hidden Comparability Assumptions

이 provider 도입이 암묵적으로 가정하는 비교 가능성:

**5개 발견:**

1. **Field Name Gravity** (AR-1a)
   `input_tokens` / `output_tokens` 필드명 유사성이 "같은 방식으로 측정된다" 는 암묵적 가정을 생성.
   실제로는 reasoning scope, tokenizer, counting methodology 가 모두 다를 수 있다.

2. **Cache Token Semantic Proxy** (AR-1c)
   Claude 의 `cache_read_input_tokens` 와 Codex 의 `cached_input_tokens` 가
   "비슷한 개념이므로 비교 가능하다" 는 암묵적 가정.
   실제로는 필드명부터 다르며, caching mechanism 자체가 다를 수 있다.

3. **Zero-Reasoning Selective Comparability** (AR-3c)
   `reasoning_output_tokens == 0` 인 turn 에서는 두 provider 가 비교 가능하다는 암묵적 가정.
   실제로는 zero-reasoning 이 reasoning 부재를 보장하지 않는다 (model 내부에서 발생 가능).

4. **Class C Convergence** (AR-1d)
   두 provider 가 모두 Class C 이므로 "동일한 epistemic quality" 를 가진다는 암묵적 가정.
   실제로는 Class C 는 quality label 이 아닌 epistemic category 이며, 비교 가능성을 보장하지 않는다.

5. **Cross-Surface Consistency as Verification** (AR-2c)
   JSONL 과 SQLite 가 동일한 값을 보여줄 때 "서로 검증되었다" 는 암묵적 가정.
   실제로는 두 surface 가 동일한 source 에서 쓰이면 동시 오류 가능성이 있으며,
   일치가 correctness 를 의미하지 않는다.

**차단 상태: 모두 기존 invariant 에 의해 차단됨.**

---

### AG-6 Output 2: Authority Expansion Vectors

이 provider 도입이 CodeBurn 의 authority 를 확장할 수 있는 경로:

**5개 발견:**

1. **Session Completeness Certification** (AR-2b)
   session_index.jsonl 와 JSONL 세션 파일의 일치를 확인하면
   "acquisition 이 완전하다" 는 결론으로 이어지는 경로.
   실제로는 surface completeness →/ acquisition completeness.
   차단: Reconstruction Distance Preservation.

2. **Replay-Based Verification Authority** (AR-4b)
   동일한 artifact 에서 두 번 ingestion 한 결과가 같으면
   "provider data 가 검증되었다" 는 epistemic upgrade 경로.
   실제로는 replay stability →/ provider truthfulness.
   차단: Anti-Collapse Axiom, FSP-1.

3. **Reasoning Token Behavioral Characterization** (AR-3e)
   reasoning_output_tokens 의 replay stability 가
   "model 의 행동 패턴을 특성화할 수 있다" 는 authority expansion 경로.
   차단: IAF-2, Reasoning Separation Principle.

4. **Cross-Surface Certification Authority** (AR-2c)
   JSONL + SQLite 의 일치로 "교차 검증된 token count" 를 주장하는 경로.
   차단: IAF-8, Dual Acquisition Surface Rule.

5. **Turn Count Verification Authority** (AR-2d)
   JSONL 의 token_count 레코드 수 = turn 수를 이용해
   "session completeness 가 인증되었다" 는 경로.
   차단: Reconstruction Distance Preservation.

**차단 상태: 모두 기존 invariant 에 의해 차단됨.**

---

### AG-6 Output 3: Semantic Implications Differing from Claude Admission

이 provider admission 이 이전 Claude admission 과 다른 semantic implications 를 가지는 부분:

**5개 발견:**

1. **Reasoning Token Asymmetry** (NST-1, NST-4)
   Claude admission 에는 reasoning token 카테고리가 없었다.
   Codex 는 `reasoning_output_tokens` 를 노출한다.
   이것은 새로운 inadmissibility category (IAF-2) 를 생성하며,
   Claude admission 에는 존재하지 않았던 semantic surface 다.

2. **Dual Acquisition Surface** (IAF-8, Dual Acquisition Surface Rule)
   Claude 는 단일 JSONL surface 를 가진다.
   Codex 는 JSONL + SQLite 두 개의 surface 를 가진다.
   이것은 새로운 inadmissibility category (IAF-8) 와 새로운 정책 원칙
   (Dual Acquisition Surface Rule) 을 생성한다.

3. **Cumulative vs Turn-Scoped Object Distinction** (IAF-1, NST-3)
   Claude 는 단일 usage 객체를 가진다 (turn-scoped).
   Codex 는 두 개의 객체를 가진다: total_token_usage (누적) vs last_token_usage (단위).
   이 구분은 Claude admission 에는 없었던 새로운 inadmissibility 경계다.
   첫 번째 turn 에서 두 값이 같아 보이는 현상 (AR-1b) 은 특히 위험한 ingestion bug 경로다.

4. **Secondary Evidence Surface from SQLite** (IAF-8)
   Claude 에는 SQLite 보조 표면이 없다.
   Codex 에는 `state_5.sqlite threads.tokens_used` 가 존재한다.
   이것은 admission gate 에 IAF-8 을 추가하게 된 새로운 semantic surface 다.

5. **total_tokens Explicitly Present in Log** (IAF-3)
   Claude: total_tokens = NULL (CodeBurn 정책 -- 집계 계산 비승인).
   Codex: total_tokens = 20364 (log 에 명시적으로 존재).
   이 존재 자체가 "이번엔 저장해도 된다" 는 추론 압력을 생성한다 (AR-1b 와 결합).
   IAF-3 이 명시적으로 차단하지만, 이 semantic pressure 는 Claude admission 에는 없었다.

**차단 상태: 모두 기존 invariant 에 의해 차단됨.**

---

## Gate Sign-off

모든 조건이 검토되었다. 아래 공식 기록으로 P5 admission 을 선언한다.

```
P5 Admission: GRANTED
Gate conditions: AG-1, AG-2, AG-3, AG-4, AG-5, AG-6 -- all confirmed
Prohibited narratives: acknowledged
Schema similarity disclaimer: acknowledged
Codex artifact contract: codeburn/CODEBURN_CODEX_ARTIFACT_CONTRACT.md (commit d98d21d)
Anti-collapse axiom: acknowledged
Copy-forward reasoning: not used
AG-6 Output 1 (hidden comparability assumptions): 5 FOUND -- all blocked
AG-6 Output 2 (authority expansion vectors): 5 FOUND -- all blocked
AG-6 Output 3 (semantic diff from prior admissions): 5 FOUND -- all blocked
Date: 2026-05-21
```

---

## P5.0 시작 조건 확인

이 문서가 committed 상태가 되는 시점에:

- [x] P5 는 더 이상 BLOCKED 가 아니다
- [x] P5.0 (Codex ingestor 구현) 을 시작할 수 있다

P5.0 이 준수해야 하는 boundary:

1. admissible fields 만 ingestion (`last_token_usage.input_tokens`, `last_token_usage.output_tokens`, timestamp, session UUID)
2. IAF-1..8 을 code level 에서 강제 (AR-2d open item: 코드에서 IAF-8 enforced)
3. multi-turn fixture 필요 (AR-1b open item: first-turn camouflage 탐지)
4. zero-reasoning 과 non-zero-reasoning fixture 모두 필요 (AR-3c open item)
5. `total_tokens = NULL` 정책 유지 (IAF-3)
6. reasoning_output_tokens 용 컬럼 추가 금지 (IAF-2)
7. SQLite surface 를 acquisition path 로 사용 금지 (IAF-8)
8. Class C (Codex) 는 Class C (Claude) 와 separately labeled 유지

---

*이 gate 는 P5 를 막기 위한 것이 아니었다.*
*이 gate 는 P5 가 올바른 semantic basis 위에서 시작되도록 하기 위한 것이었다.*
*gate 를 통과한 P5 는 더 강하다.*
