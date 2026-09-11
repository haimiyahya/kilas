# CLAUDE.md – Agent Context for kilas

## Karpathy Rules

- Think before coding. State assumptions, surface tradeoffs, push back when warranted.
- Simplicity first. Minimum code that solves the problem. Nothing speculative.
- Surgical changes. Touch only what you must. Clean up only your own mess.
- Goal-driven execution. Define success criteria. Loop until verified.

## 🔴 CRITICAL RULES

### 1. DIRECTORY SCOPE - CHANGES INSIDE THIS PROJECT ONLY
All file changes, creations, and modifications MUST stay inside this directory
(`/root/projects/kilas`). Never modify files outside it. Reading other projects
for reference is allowed; writing to them is not.

### 2. NO ASSUMPTIONS - EVIDENCE ONLY
Never form hypotheses without proper evidence. Premature hypotheses waste time.

**Required Process:**
1. **GATHER EVIDENCE FIRST** - Before any hypothesis, collect comprehensive data
2. **TEST MULTIPLE HYPOTHESES** - Never commit to one theory without testing alternatives
3. **LABEL CLEARLY** - Distinguish between SPECULATION, EVIDENCE, and PROOF
4. **DESIGN TESTS TO DISPROVE** - Tests should be able to reject hypotheses, not just confirm

**Evidence Gathering Protocol:**
- Test against known baselines before forming theory
- Multiple comparative tests before concluding
- Document exact results (commands run, pass/fail counts, error messages)
- Only conclude when you have concrete proof

**When You Don't Know:**
- Say "I don't know" - better than a wrong assumption
- Test against known baselines first
- Let results drive analysis, not theories

## Core Principles

1. **Incremental & Atomic Progress** – Build in strict phases; small verifiable steps
2. **Ask First, Brute Force Later** – When uncertain, ask the user instead of guessing; the problem has likely been solved before

**Start working only when explicitly told.**
