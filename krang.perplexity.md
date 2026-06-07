<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# i want to design \& implement an LLM powered agentic mutation tester.

* goal: on a pull request, consisting of commits on a feature branch,supposed to implement the requirements of a JIRA ticket,  determine and report which code changes lack test coverage
* method:
a. pinpoint key code changes which are important to the JIRA ticket requirements, and/or handle edge cases
b. for each key code change, determine a *mutation* which either reverts the code change  surgically or modifies it in a edge-case relevant manner, **while keeping the code compiling w/o syntax errors**
c. compile and run the tests, to ascertain whether the mutation is caught by test failures - test coverage okay, or not caught by tests passing - mutation surviving
d. report surviving mutations in results \& on respective file:line describing the mutation diff
e. iterate for next mutation

does this make sense? pros/cons, weakmesses/strengths?
come up with an LLM prompt to instruct a model to carry this out.
which model should be used for this?
design a process to iteratively refine and improve the prompt for higher quality \& amount of mutations discovered

Yes — this makes sense, and it is a **good** direction for PR review because it tests whether the tests actually protect the intent of a change, not just whether lines were executed. It is especially strong for requirement-driven changes tied to a JIRA ticket, where “important behavior changed” matters more than raw statement coverage.

## Fit

Your workflow is basically a requirement-aware mutation tester: select semantically important changes, generate compiling mutations that negate or stress them, run the test suite, and report surviving mutants at file:line granularity. That is closer to “does the test suite defend the behavior we meant to add?” than conventional coverage metrics, which often miss weak assertions and untested edge cases.

This is stronger than plain mutation testing in one important way: you are not mutating arbitrary code uniformly, but prioritizing code changes that appear central to the ticket or to edge-case handling. That raises signal and makes the output much more usable in PR review.

## Strengths and risks

**Strengths**

- It aligns testing with product intent: the JIRA ticket, PR diff, and tests are all considered together, so the system can flag “this requirement was implemented, but tests would still pass if we broke it.”
- It produces actionable findings: a surviving mutant with a small diff on a specific line is much easier for reviewers to understand than “coverage is 71%.”
- It naturally finds weak tests around boundaries, validation, conditionals, default values, null/empty handling, and error paths.

**Weaknesses**

- The hard part is mutant quality, not test execution; a poor model will generate noisy, irrelevant, or uncompilable mutations, or mutate incidental refactors instead of requirement-bearing logic.
- Ticket understanding can be lossy; if the JIRA is vague, the model may over-focus on the wrong code paths or miss hidden requirements implied by older behavior.
- Surviving mutants are not always “missing tests”; sometimes they indicate dead code, equivalent mutants, behavior intentionally left unspecified, or tests that run only under integration environments not available in CI.


## Failure modes

The biggest technical weakness is the equivalent-mutant problem: some mutations preserve observable behavior, so a surviving mutant is not always a real gap. You need explicit triage labels such as “likely uncovered,” “possibly equivalent,” and “environment-dependent” rather than treating every survivor as a defect.

A second weakness is test-suite economics. If you mutate every candidate change and rerun the full suite each time, runtime will explode on large repositories, so you will want scope reduction: test impact analysis, mutation budgets per PR, timeout ceilings, and early stopping once enough high-confidence survivors are found.

A third weakness is model overreach. If the agent is allowed to invent mutations freely, it may produce broad rewrites instead of surgical changes, which weakens attribution; you want mutations that are minimal, compile-clean, and obviously tied to a specific requirement or edge case.

## Model choice

For the mutation-generation step, I would use a top-tier coding model with strong repo reasoning and long-horizon agent behavior rather than a small fast model. OpenAI says GPT-5 is its strongest coding model to date, with 74.9% on SWE-bench Verified and 88% on Aider Polyglot with thinking enabled, and says GPT-5 improves instruction following and agentic tool use for multi-step technical work. [^1_1]

If you want the model most explicitly positioned for agentic coding workflows, OpenAI presents GPT-5.3-Codex as its most capable agentic coding model, reporting state-of-the-art results on SWE-Bench Pro and Terminal-Bench 2.0, with 56.8% on SWE-Bench Pro Public and 77.3% on Terminal-Bench 2.0. [^1_2] OpenAI also notes SWE-Bench Pro was designed to be more challenging, more diverse, cross-language, and more contamination-resistant than SWE-bench Verified, which matters for a system like yours that needs real repository judgment more than benchmark-chasing. [^1_2]

Anthropic positions Claude Opus 4 and Sonnet 4 as strong coding models as well, and a widely cited summary of Anthropic’s release reports roughly 72.5% and 72.7% on SWE-bench respectively. [^1_3][^1_4] If you optimize for raw code-edit quality plus broad ecosystem support for agent loops, my practical pick would be: GPT-5.3-Codex first, GPT-5 second, Claude Opus 4 as a strong alternative, and a cheaper fast model only as a first-pass triage model.

## Recommended architecture

Use a two-stage system instead of one monolithic agent.

1. **Selector agent**

- Inputs: JIRA ticket, PR title/description, commit list, diff hunks, changed tests, and optionally blame/history.
- Output: ranked “key code changes” with rationale, requirement mapping, edge-case tags, and candidate file:line anchors.

2. **Mutator agent**

- Inputs: one selected change at a time, nearby code, symbols/types, and build/test instructions.
- Output: one minimal compiling mutation, expected affected behavior, confidence score, and why this mutation is meaningful.

3. **Executor**

- Applies patch in isolation, builds, runs impacted tests first, optionally escalates to broader suites, records compile/test outcome, and restores workspace.

4. **Judge/reporter**

- Filters equivalent/noisy cases, clusters survivors, and emits PR comments plus a machine-readable artifact.

That separation matters because “what change matters?” and “what is the best surgical mutant?” are different reasoning tasks.

## Good mutation classes

Your mutator should strongly prefer small, semantics-focused edits such as:

- Boolean inversion: `if (x)` to `if (!x)`.
- Boundary shifts: `>`, `>=`, `<`, `<=`, `==`, `!=`.
- Default/fallback changes: empty value, null path, timeout, feature flag default.
- Early return removal/addition.
- Error handling changes: swallow error, wrong exception branch, missing retry/backoff condition.
- Collection edge cases: empty, single-item, duplicate, ordering.
- Security/validation changes: auth check bypass, input normalization removed, tenant scoping weakened.
- Requirement reversion: revert just the key added clause or the new branch introduced by the PR.

Avoid stylistic mutations, wide refactors, renames, logging-only edits, and anything that changes many lines when a one-line mutation would do.

## LLM prompt

Use a prompt that makes the model produce exactly one mutation at a time, justify why it matters, and stay extremely constrained.

```text
You are an expert software testing agent performing requirement-aware mutation testing on a pull request.

Goal:
Given a JIRA ticket, a PR diff, nearby code context, and repository build/test instructions, identify one high-value mutation candidate at a time that tests whether the changed behavior is actually protected by tests.

Mission:
Find code changes in the PR that are likely important to the JIRA requirements or important edge-case handling.
For exactly one chosen change, propose one minimal mutation that either:
1) surgically reverts the behavior introduced by the PR, or
2) modifies the behavior in an edge-case-relevant way.

Hard constraints:
- The mutation must be minimal and local.
- The mutation must preserve syntactic correctness.
- Prefer mutations that are highly likely to compile.
- Do not invent APIs, symbols, imports, or helper functions unless already present nearby.
- Do not perform broad rewrites.
- Do not mutate formatting, comments, logging, or naming-only changes.
- If the changed code appears irrelevant to the JIRA requirement, skip it.
- If no meaningful mutation is possible, say so explicitly.

Prioritization:
Prefer mutations on:
- conditionals, guards, validation, authz/authn, tenant scoping
- boundary checks, null/empty handling, default values
- retries/timeouts/backoff, error handling
- state transitions, feature flags, data filtering, ordering
- branches newly introduced by the PR
- code clearly tied to acceptance criteria or bug fix semantics

Treat these as lower priority:
- pure refactors
- dead code movement
- dependency/version bumps
- comments/docs
- non-functional logging/telemetry changes

Inputs you will receive:
- JIRA ticket text
- PR title/description
- commit summaries
- unified diff
- nearby file context
- changed tests, if any
- build and test commands

Required reasoning process:
1. Infer the key requirement(s) from the JIRA + PR.
2. Identify the code change most likely to embody one requirement or one edge case.
3. Explain why this change is important.
4. Produce exactly one mutation that meaningfully weakens/reverts that behavior.
5. Ensure the mutation is as surgical as possible.
6. Predict what test(s) should fail if coverage is adequate.
7. Estimate the risk of equivalent-mutant behavior.

Output format:
Return JSON only with this schema:

{
  "candidate_id": "string",
  "requirement_summary": "string",
  "file": "string",
  "line_start": number,
  "line_end": number,
  "why_this_change_matters": "string",
  "mutation_type": "revert_change | boundary_shift | guard_inversion | edge_case_modification | error_path_change | default_change | ordering_change | other",
  "original_behavior": "string",
  "mutated_behavior": "string",
  "expected_test_signal": "string",
  "equivalent_mutant_risk": "low | medium | high",
  "confidence": 0.0,
  "patch_unified_diff": "string"
}

Quality bar:
A good answer picks one mutation that a reviewer would immediately recognize as semantically meaningful, plausibly compiling, and directly tied to the ticket’s intended behavior.
```


## Process tuning

To improve quality and increase discovered survivors, run prompt refinement as an evaluation loop, not by intuition.

1. Build a gold set:

- Sample 30–100 historical PRs with JIRA links.
- Have humans label key requirement-bearing hunks.
- Add outcomes for proposed mutants: compile fail, test-killed, survived-useful, survived-equivalent, survived-noisy.

2. Track metrics per prompt version:

- Key-change precision: how often selected hunks are genuinely important.
- Compile rate of generated mutants.
- Meaningful-survivor rate: survivors judged useful, not equivalent/noisy.
- Mutation diversity: how many distinct classes of defects are explored.
- Cost per useful survivor: tokens + CI minutes.

3. Refine prompts systematically:

- Add negative instructions when you see recurring junk, for example “do not mutate logging-only changes.”
- Add ranking heuristics when you see weak prioritization, for example “prefer newly added branches over moved code.”
- Add repository-specific guardrails, for example language idioms, test commands, or “never mutate generated code.”

4. Use pairwise prompt bake-offs:

- For the same PR set, run Prompt A vs Prompt B.
- Blind-rank outputs by human reviewers on usefulness.
- Keep the better prompt only if it improves both compile rate and useful-survivor yield.

5. Add critic passes only where they pay off:

- Generator proposes $N$ candidates.
- Critic removes equivalent or broad mutations.
- Final mutator emits one best patch.
This usually improves quality, but only if you cap tokens and keep the critic rubric strict.


## Practical refinements

A few design decisions will improve the system a lot:

- **Use changed tests as evidence, not ground truth.** If the PR added tests for only one happy path, the agent should still generate boundary mutants nearby.
- **Run impacted tests first.** Only escalate to broader suites when the mutation survives.
- **Cluster by requirement.** Report “three surviving mutations around tenant-filter logic” rather than spamming one comment per mutant.
- **Cache build artifacts.** Mutation testing is expensive; compilation caching and test selection matter.
- **Keep humans in the loop.** Let reviewers mark findings as “good catch,” “equivalent,” or “not important,” then feed that back into prompt and ranking refinement.

My overall view: the idea is solid, likely high-value, and more product-aligned than generic mutation testing. The main risks are equivalent mutants, CI cost, and poor mutation selection, so the project will live or die on candidate ranking, surgical patch quality, and a disciplined evaluation loop.

Would you like me to turn this into a concrete system design next — for example, a GitHub Action plus worker architecture, data model, and execution pipeline?
<span style="display:none">[^1_10][^1_11][^1_12][^1_13][^1_14][^1_15][^1_5][^1_6][^1_7][^1_8][^1_9]</span>

<div align="center">⁂</div>

[^1_1]: https://openai.com/index/introducing-gpt-5/

[^1_2]: https://openai.com/index/introducing-gpt-5-3-codex/

[^1_3]: https://opencv.org/blog/claude-4/

[^1_4]: https://www.anthropic.com/news/claude-4

[^1_5]: https://www.morphllm.com/swe-bench-pro

[^1_6]: https://www.codeant.ai/blogs/swe-bench-scores

[^1_7]: https://evolink.ai/blog/swe-bench-verified-2026-claude-vs-gpt

[^1_8]: https://swe-rebench.com

[^1_9]: https://swe-bench-live.github.io

[^1_10]: https://www.vellum.ai/blog/gpt-5-benchmarks

[^1_11]: https://www.reddit.com/r/LocalLLM/comments/1swpv81/confirmed_swe_bench_is_officially_a_benchmaxxed/

[^1_12]: https://www.reddit.com/r/ClaudeAI/comments/1ksvb5q/claude_4_benchmarks_we_eating/

[^1_13]: https://labs.scale.com/leaderboard/swe_bench_pro_public

[^1_14]: https://github.com/swe-bench/SWE-bench

[^1_15]: https://www.datacamp.com/blog/claude-4


---

# in your prompt - the model procudes a single mutation, is that ideal?

* how do you iterate this to exclude already generated mutations on next runs?
* parts of the analysis done by earlier iterations would be repeated in all subsequent ones

isn't it better to instruct the prompt to generate n mutations at once?

No — “exactly one mutation per model call” is usually not the **optimal** outer-loop design. It is ideal as the *unit of execution and evaluation*, but not necessarily as the *unit of generation*. [^2_1][^2_2]

So the better answer is: generate a **small ranked batch** of candidates at once, then execute them one-by-one with deduplication and state carried forward. That gives you better token efficiency and less repeated analysis, while still keeping mutation application and test evaluation isolated. [^2_1][^2_3]

## Best granularity

A good architecture separates:

- **analysis pass**: understand JIRA, PR, important hunks, edge cases
- **candidate generation pass**: produce $N$ ranked mutation proposals
- **execution pass**: apply one mutation at a time, build, run tests, record result
- **refresh pass**: ask for more only when the queue is depleted or quality drops

This is usually better than “single mutation only” because the expensive semantic work — ticket interpretation, diff triage, edge-case discovery — is shared across many candidates instead of recomputed for every run. That fits your efficiency bias well and reduces repeated context consumption. [^2_4]

## Why not generate many

You also do **not** want a very large batch, because quality tends to drop after the first few candidates. When a model is asked for 20 mutations at once, later items are more likely to be near-duplicates, broader rewrites, lower-confidence guesses, or equivalent mutants.

So the sweet spot is usually:

- 5–12 candidate mutations per analysis batch for a medium PR
- maybe 3–5 for a small PR
- maybe 10–20 only if you first partition the PR into independent change clusters

That gives you reuse of analysis without inviting “list-padding.”

## Recommended loop

I’d use a two-level loop.

### Level 1: batch planning

The planner model sees the JIRA, PR diff, changed tests, and local context, then returns:

- ranked key changes
- one or more candidate mutations per key change
- metadata: mutation class, confidence, likely equivalent risk, expected impacted tests
- stable fingerprints for deduplication


### Level 2: isolated execution

For each candidate in rank order:

1. Check whether its fingerprint or normalized patch is already seen.
2. Apply the mutation in a clean worktree.
3. Build.
4. Run impacted tests first, then broader tests if needed.
5. Record outcome: compile fail, killed, survived, flaky, equivalent-suspect.
6. Feed outcome into the next planning step only after a batch is exhausted or if the model is underperforming.

This preserves one-mutation-at-a-time **evaluation**, which is important for attribution, while allowing many-at-once **generation**.

## Deduplication

Yes, if you do repeated runs, you need explicit exclusion of prior mutations. Do not rely on prompt text alone.

Use three layers of dedupe:

- **Patch hash**: hash the normalized unified diff.
- **Semantic fingerprint**: `file + symbol + line-range + mutation_type + normalized_behavior_change`.
- **Behavioral family key**: for example, “invert auth guard in function X” and “change auth check to always true in function X” may belong to the same family.

Then pass prior generated candidates back as compact structured state, for example:

```json
{
  "seen_mutations": [
    {
      "fingerprint": "src/authz.py|can_access|120-128|guard_inversion|tenant_scope_removed",
      "outcome": "survived"
    },
    {
      "fingerprint": "src/authz.py|can_access|126-126|boundary_shift|>= to >",
      "outcome": "killed"
    }
  ]
}
```

That is far better than pasting raw prior diffs every time.

## Avoiding repeated analysis

You’re right that repeated full analysis is wasteful. The fix is to persist intermediate artifacts and make later prompts incremental.

Persist these objects:

- requirement graph from JIRA
- ranked PR hunk list
- code-change-to-requirement mapping
- mutation families already explored
- test-impact hints
- outcomes from executed mutants

Then subsequent prompts can say:

```text
Reuse the existing analysis state.
Do not re-rank the entire PR unless prior assumptions were invalidated.
Generate up to 5 new high-value mutations only for unexplored change clusters or mutation families.
Avoid any candidate semantically equivalent to fingerprints in SEEN_MUTATIONS.
Prioritize clusters with no killed mutations yet.
```

That turns later iterations into targeted exploration instead of redoing the whole job.

## Better prompt shape

So yes: in practice, I would change the prompt from “produce exactly one mutation” to “produce up to $N$ ranked candidate mutations.” But I would still require each candidate to be individually executable and self-contained.

A good output schema would look like this:

```json
{
  "analysis_id": "pr-123-run-2",
  "requirement_summary": [
    "string"
  ],
  "change_clusters": [
    {
      "cluster_id": "string",
      "file": "string",
      "line_start": 0,
      "line_end": 0,
      "importance": "high | medium | low",
      "requirement_link": "string"
    }
  ],
  "mutations": [
    {
      "candidate_id": "string",
      "cluster_id": "string",
      "fingerprint": "string",
      "rank": 1,
      "mutation_type": "revert_change | boundary_shift | guard_inversion | edge_case_modification | error_path_change | default_change | ordering_change | other",
      "why_this_change_matters": "string",
      "original_behavior": "string",
      "mutated_behavior": "string",
      "expected_test_signal": "string",
      "equivalent_mutant_risk": "low | medium | high",
      "confidence": 0.0,
      "patch_unified_diff": "string"
    }
  ]
}
```

Then your executor can pop one candidate at a time from `mutations`.

## Prompt strategy

I’d rewrite the instruction like this:

```text
You are a requirement-aware mutation planning agent.

Task:
Given a JIRA ticket, PR diff, code context, prior analysis state, and previously generated mutation fingerprints, produce a ranked batch of up to N new mutation candidates.

Goals:
- Reuse prior analysis instead of recomputing it.
- Generate only mutations not already explored.
- Prioritize semantically important PR changes and edge cases.
- Prefer minimal, local, compile-likely mutations.
- Maximize diversity across mutation families.
- Avoid near-duplicates, broad rewrites, and likely equivalent mutants.

Rules:
- Output 5 candidates by default unless the PR is very small.
- No two candidates may target the same exact semantic change in the same way.
- Do not regenerate anything matching prior fingerprints or behavioral families.
- If a prior candidate in a family survived, explore an adjacent family before adding another same-family variant unless the family is central to the ticket.
- Reuse the supplied change clusters and requirement mapping; only revise them if clearly wrong.

For each candidate include:
- stable fingerprint
- cluster_id
- file and line range
- mutation type
- why this mutation matters
- expected failing tests or test areas
- equivalent-mutant risk
- unified diff

Output JSON only.
```


## Selection policy

A strong practical policy is:

- Planner generates 8 candidates.
- Critic/ranker reduces to top 5.
- Executor runs top 3 immediately.
- If 2 of 3 are low-value or uncompilable, trigger replanning with stricter constraints.
- If survivors appear in one cluster, ask for more mutations adjacent to that cluster.
- If everything is killed quickly, shift focus to unexplored clusters.

That is more adaptive than either “one forever” or “generate 30 up front.”

## When single-mutation generation is still useful

There are still cases where one-at-a-time generation is the right move:

- very large repos with tight context budgets
- mutation synthesis that requires live compiler/test feedback between attempts
- especially fragile languages or macro-heavy code where compile-likely mutations are hard
- second-stage deepening around one critical hunk after a survivor is found

So I’d say:

- **batch generation** for discovery
- **single generation** for refinement around a promising area


## My recommendation

For your system, I would not use “single mutation only” as the main prompt contract. I would use:

- one **planning** call to generate 5–10 ranked mutations
- one **execution** loop that tests them individually
- one **incremental replanning** call that sees prior state and emits only novel candidates

That gets you:

- less repeated reasoning
- better token efficiency
- easier dedupe
- better mutation diversity
- preserved attribution per executed mutant

In short: generate $N$ at once, execute 1 at a time, and carry forward structured state.

Would you like me to draft the exact planner prompt, executor prompt, and the state schema between iterations?
<span style="display:none">[^2_10][^2_11][^2_12][^2_13][^2_14][^2_15][^2_16][^2_5][^2_6][^2_7][^2_8][^2_9]</span>

<div align="center">⁂</div>

[^2_1]: https://developers.openai.com/codex/concepts/subagents

[^2_2]: https://openai.com/index/gpt-5-3-codex-system-card/

[^2_3]: https://openreview.net/forum?id=9R2iUHhVfr

[^2_4]: https://www.perplexity.ai/search/266ec668-5341-44a4-a886-8d3469b5ed09

[^2_5]: https://openai.com/index/introducing-gpt-5-3-codex/

[^2_6]: https://developers.openai.com/blog/run-long-horizon-tasks-with-codex

[^2_7]: https://developers.openai.com/api/docs/models/gpt-5.3-codex

[^2_8]: https://www.youtube.com/watch?v=xAy64mGKKJ8

[^2_9]: https://github.com/kortix-ai/suna/issues/460

[^2_10]: https://www.reddit.com/r/ClaudeAI/comments/1ksvebb/introducing_claude_4/

[^2_11]: https://www.swebench.com

[^2_12]: https://cdn.openai.com/pdf/23eca107-a9b1-4d2c-b156-7deb4fbc697c/GPT-5-3-Codex-System-Card-02.pdf

[^2_13]: https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview

[^2_14]: https://awesomeagents.ai/leaderboards/swe-bench-coding-agent-leaderboard/

[^2_15]: https://openai.com/index/introducing-gpt-5-3-codex-spark/

[^2_16]: https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools


---

# > Would you like me to draft the exact planner prompt, executor prompt, and the state schema between iterations?

yes, go ahead

Yes — I’d structure this as a planner/executor/stateful loop, not a single giant prompt, because long-horizon software-engineering tasks benefit from decomposition, and structured outputs are the safest way to keep each step machine-consumable. [^3_1][^3_2][^3_3][^3_4] Given your preference for efficient, interactive agent workflows with model/tool switching, this split also fits better than repeatedly rerunning one monolithic reasoning pass.

## Orchestration

Use one planner pass to produce a ranked mutation queue, then execute mutations one at a time in isolation, because parallel or delegated subagent-style workflows are useful for analysis but cost more tokens than a single-agent run. [^3_5][^3_6] Keep the planner read-mostly and the executor action-oriented, so analysis remains reusable while build/test side effects stay attributable to one mutation at a time. [^3_5][^3_7]

A good default is: planner emits 5–10 candidates, executor runs the top 3–5, then a replanner is called only if the queue is exhausted or low-quality. That matches the general guidance that complex tasks become more consistent when broken into smaller subtasks with structured outputs. [^3_3][^3_4]

## Planner prompt

The planner should output only JSON and must be explicitly told to reuse prior state, avoid prior fingerprints, and diversify mutation families, because structured outputs are recommended when you need valid schema-conforming results. [^3_3][^3_4]

```text
SYSTEM
You are the Mutation Planner for a requirement-aware PR mutation testing system.

Your job is to analyze a JIRA ticket, PR diff, nearby code, and prior run state, then produce a ranked batch of NEW mutation candidates.

You do NOT execute code.
You do NOT run tests.
You do NOT modify files.
You ONLY plan high-value candidate mutations.

Primary goal:
Find code changes in the PR that are important to the JIRA requirements or to edge-case handling, and propose minimal, local, compile-likely mutations that could reveal missing test coverage.

Inputs:
- jira_ticket_text
- pr_title
- pr_description
- commit_summaries
- unified_diff
- changed_tests
- repository_notes
- prior_state_json

Rules:
1. Reuse prior_state_json.analysis when still valid; do not redo full PR analysis unless prior assumptions are clearly wrong.
2. Do not emit any mutation whose fingerprint, family_key, or normalized patch matches prior_state_json.seen_mutations or prior_state_json.rejected_mutations.
3. Prefer mutations on:
   - new branches and guards introduced by the PR
   - validation/authz/authn/tenant scoping
   - boundary checks
   - null/empty/default handling
   - retries, timeouts, backoff, error handling
   - ordering/filtering/state transitions
   - code directly tied to ticket acceptance criteria
4. Avoid:
   - formatting, comments, logging-only changes
   - dependency/version bumps
   - pure renames
   - broad rewrites
   - generated code
   - speculative mutations requiring invented APIs or imports
5. Favor diversity across mutation families. Do not produce near-duplicates.
6. Each mutation must be minimal and localized, and should be highly likely to compile.
7. If a mutation is likely equivalent, mark it as such and rank it lower.
8. Output ONLY valid JSON matching the schema below.

Output schema:
{
  "analysis_version": "string",
  "requirement_summary": [
    {
      "requirement_id": "REQ-1",
      "summary": "string",
      "evidence": ["jira", "pr", "tests"]
    }
  ],
  "change_clusters": [
    {
      "cluster_id": "CL-1",
      "file": "string",
      "line_start": 0,
      "line_end": 0,
      "symbol": "string",
      "importance": "high|medium|low",
      "requirement_ids": ["REQ-1"],
      "why_it_matters": "string"
    }
  ],
  "mutations": [
    {
      "candidate_id": "MUT-1",
      "cluster_id": "CL-1",
      "rank": 1,
      "fingerprint": "string",
      "family_key": "string",
      "file": "string",
      "line_start": 0,
      "line_end": 0,
      "symbol": "string",
      "mutation_type": "revert_change|boundary_shift|guard_inversion|edge_case_modification|error_path_change|default_change|ordering_change|other",
      "why_this_change_matters": "string",
      "original_behavior": "string",
      "mutated_behavior": "string",
      "expected_test_signal": "string",
      "suggested_test_scope": ["string"],
      "equivalent_mutant_risk": "low|medium|high",
      "compile_confidence": 0.0,
      "semantic_value": 0.0,
      "patch_unified_diff": "string"
    }
  ],
  "planner_notes": [
    "string"
  ]
}

User task:
Analyze the provided PR and prior state, then emit 5 new ranked mutation candidates unless the PR is too small to justify that many.
```

A short planner-user message template is:

```text
Produce a ranked mutation plan for this pull request.

Goals:
- maximize useful surviving mutants
- minimize uncompilable or equivalent mutants
- reuse prior analysis
- avoid duplicates
- prefer requirement-bearing logic over incidental edits

Artifacts attached:
- JIRA ticket
- PR metadata
- diff
- changed tests
- prior_state_json
```


## Executor prompt

The executor should consume one candidate at a time and return structured outcomes, because the planning/execution split works best when each subtask has a narrow scope and a strict output contract. [^3_3][^3_7] Keep it deterministic: apply the exact diff, build, run the narrowest relevant tests first, widen only if needed, then classify the result. [^3_1][^3_2]

```text
SYSTEM
You are the Mutation Executor for a requirement-aware PR mutation testing system.

You receive exactly one mutation candidate plus repository build/test instructions.
Your job is to apply that mutation in isolation, validate whether it compiles, run tests, classify the outcome, and report machine-readable results.

You must not invent a different mutation.
You must apply the candidate patch exactly as provided unless it fails to apply cleanly.
If patch application fails, report "patch_apply_failed".
If compilation fails, report "compile_failed".
If tests fail due to the mutation, report "killed".
If relevant tests pass, report "survived".
If results are inconsistent across reruns, report "flaky".
If the mutation appears behaviorally redundant, mark "equivalent_suspect": true.

Execution rules:
1. Use a clean checkout or clean worktree for each mutation.
2. Apply only the provided patch_unified_diff.
3. Record exact file and line targets after patch application.
4. Run build/compile first.
5. Run suggested_test_scope first.
6. If suggested_test_scope passes and policy allows, run broader PR-related tests.
7. Capture:
   - compile status
   - test commands run
   - failing tests
   - stderr/stdout snippets
   - classification
8. Never silently modify the mutation.
9. Output ONLY valid JSON matching the schema below.

Output schema:
{
  "candidate_id": "string",
  "fingerprint": "string",
  "apply_result": "applied|patch_apply_failed",
  "compile_result": "passed|failed|not_run",
  "test_result": "killed|survived|flaky|not_run",
  "equivalent_suspect": true,
  "outcome_confidence": 0.0,
  "commands": [
    {
      "kind": "build|test",
      "command": "string",
      "exit_code": 0,
      "duration_seconds": 0.0
    }
  ],
  "failing_tests": [
    {
      "name": "string",
      "signal": "assertion|exception|timeout|other"
    }
  ],
  "artifacts": {
    "mutation_diff_path": "string",
    "build_log_path": "string",
    "test_log_path": "string"
  },
  "summary": "string"
}
```

A good executor-user message template is:

```text
Execute this one mutation candidate exactly as specified.

Repository instructions:
- build: <build command>
- narrow tests: <impacted tests command>
- broader tests: <optional broader command>
- timeout policy: <policy>

Candidate JSON:
<single mutation candidate object here>
```


## State schema

The key optimization is to persist analysis state and mutation history, so subsequent planner runs can be incremental instead of redoing the same semantic work. That is especially worthwhile in long-horizon engineering tasks, where context and decomposition quality strongly affect results. [^3_1][^3_2][^3_7]

```json
{
  "run_id": "pr-1234-run-01",
  "repo": {
    "name": "example-repo",
    "base_ref": "main",
    "head_ref": "feature/xyz",
    "pr_number": 1234
  },
  "analysis": {
    "analysis_version": "2026-06-07T13:44:00Z",
    "jira_requirements": [
      {
        "requirement_id": "REQ-1",
        "summary": "Reject expired session tokens during refresh.",
        "evidence": ["JIRA acceptance criterion 2", "PR description", "new test test_refresh_rejects_expired"]
      }
    ],
    "change_clusters": [
      {
        "cluster_id": "CL-1",
        "file": "src/auth/session.py",
        "line_start": 118,
        "line_end": 146,
        "symbol": "refresh_session",
        "importance": "high",
        "requirement_ids": ["REQ-1"],
        "why_it_matters": "Introduces new expiry validation path before issuing refreshed session."
      }
    ],
    "assumptions": [
      "Expiry behavior is requirement-bearing, not incidental refactor."
    ]
  },
  "queues": {
    "planned": ["MUT-1", "MUT-2", "MUT-3"],
    "in_progress": [],
    "completed": ["MUT-0"]
  },
  "seen_mutations": [
    {
      "candidate_id": "MUT-0",
      "fingerprint": "src/auth/session.py|refresh_session|120-126|guard_inversion|expiry_check_removed",
      "family_key": "refresh_session:expiry_guard",
      "status": "killed"
    }
  ],
  "rejected_mutations": [
    {
      "fingerprint": "src/auth/session.py|refresh_session|120-126|other|logging_only",
      "reason": "not requirement-bearing"
    }
  ],
  "results": [
    {
      "candidate_id": "MUT-0",
      "fingerprint": "src/auth/session.py|refresh_session|120-126|guard_inversion|expiry_check_removed",
      "apply_result": "applied",
      "compile_result": "passed",
      "test_result": "killed",
      "equivalent_suspect": false,
      "summary": "Expiry-removal mutation was caught by auth session tests."
    }
  ],
  "family_stats": [
    {
      "family_key": "refresh_session:expiry_guard",
      "attempted": 1,
      "killed": 1,
      "survived": 0,
      "compile_failed": 0
    }
  ],
  "policy": {
    "max_new_candidates_per_replan": 5,
    "max_mutations_per_cluster": 3,
    "avoid_high_equivalent_risk": true,
    "prefer_unexplored_clusters": true
  }
}
```

Use `fingerprint` for exact dedupe and `family_key` for near-duplicate control, so the planner can avoid producing five variants of the same idea. That mirrors the general subagent/planner pattern where the planner emits machine-readable tasks with explicit scope and rules rather than relying on free-form memory. [^3_5][^3_8]

## Replanning loop

The replanner prompt should be short and state-driven, because later iterations should exploit prior results rather than reopen the whole repository from scratch. [^3_3][^3_7] A good trigger is: queue empty, compile-failure rate too high, or too many low-value duplicates. [^3_5][^3_3]

```text
SYSTEM
You are replanning for the next mutation batch.

Inputs:
- prior_state_json
- latest_results_json
- optional_new_context

Task:
Generate up to 5 NEW mutation candidates.

Instructions:
- Reuse prior_state_json.analysis unless contradicted by results.
- Exclude all fingerprints and family_keys already attempted or rejected.
- Prefer unexplored clusters first.
- If a cluster produced a survivor, allow one adjacent mutation family in that same cluster.
- If compile failures exceeded 30% in the last batch, reduce aggressiveness and favor simpler mutations.
- If all recent mutations were killed, shift attention to untested-looking clusters or weaker changed-test areas.
- Output valid JSON only in the planner schema.
```

That loop gives you a stable shape: planner for breadth, executor for attribution, and replanner for adaptive search. It should work well with strong coding agents and structured-output-capable models, especially on the kind of long-horizon repository tasks captured by modern software-engineering benchmarks. [^3_9][^3_1][^3_4]

If you want, the next useful step is a concrete implementation sketch: GitHub Action, worker queue, patch application strategy, and how to map diffs back into PR comments.
<span style="display:none">[^3_10][^3_11][^3_12][^3_13][^3_14][^3_15][^3_16]</span>

<div align="center">⁂</div>

[^3_1]: https://openreview.net/forum?id=9R2iUHhVfr

[^3_2]: https://arxiv.org/abs/2509.16941

[^3_3]: https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/increase-consistency

[^3_4]: https://platform.claude.com/docs/en/build-with-claude/structured-outputs

[^3_5]: https://developers.openai.com/codex/concepts/subagents

[^3_6]: https://developers.openai.com/codex/subagents

[^3_7]: https://developers.openai.com/codex/workflows

[^3_8]: https://github.com/openai/codex/discussions/3898

[^3_9]: https://openai.com/index/introducing-gpt-5-3-codex/

[^3_10]: https://juliangoldie.com/openai-codex-cli-subagents/

[^3_11]: https://github.com/openai/codex/issues/11701

[^3_12]: https://github.com/openai/codex/issues/2604

[^3_13]: https://thomas-wiegold.com/blog/claude-api-structured-output/

[^3_14]: https://github.com/scaleapi/SWE-bench_Pro-os

[^3_15]: https://www.linkedin.com/posts/iamrajusingh_ai-openai-codex-activity-7440029028369137664-x7vW

[^3_16]: https://code.claude.com/docs/en/agent-sdk/structured-outputs

