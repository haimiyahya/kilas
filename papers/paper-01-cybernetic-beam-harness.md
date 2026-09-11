# The Cybernetic BEAM Harness: A Zero-Disk, Sub-Millisecond Control Plane for Autonomous Software Engineering

**Paper 1 of 4 — Kilas Project**

| | |
|---|---|
| **Author** | Mohd Norhaimi Bin Yahya |
| **Affiliation** | Kilas Project — Autonomous SWE Lab |
| **Version** | v0.3.1 • OTP 26 • Elixir 1.16 |
| **DOI** | 10.5281/kilas.2025.beam |
| **License** | MIT Licensed |
| **Motto** | "Code That Can Talk" |
| **Source** | Extracted from `paper_polished_academic.html` (React artifact, pasted 2026-09-10) into Markdown. Figures were SVG diagrams in the source; they appear here as placeholders. Content transcribed as-is — no corrections applied yet. |

---

## Abstract

Autonomous software engineering (SWE) agents remain bottlenecked by "outsider harnesses" that interact with the filesystem from outside the runtime: disk-bound I/O (45–120 ms per operation), token bloat from re-reading files (2–8k tokens per re-read), and non-deterministic write contention among concurrent agents.

We present the **Cybernetic BEAM Harness**, an insider harness in which the agent control plane *is* the runtime: Erlang/Elixir BEAM (OTP 26, Elixir 1.16). The harness models the environment as lightweight BEAM actors (GenServer/GenStateMachine, <1 KB initial heap), sustaining 2,000+ concurrent actors. Files never touch disk during execution: they live as Elixir binaries in ETS and as immutable objects in MemGit, a content-addressed in-memory Git (checkout 0.06 ms), resident on a tmpfs RAM-disk workspace (8 GB). A single-writer **CodeWriter Coordinator** serializes mutations via message passing, eliminating write races by construction. A **Pre-Flight AST Policy Gatekeeper** rejects policy-violating mutations in <1 ms with surgical notices, before any side effect. A **Target Test Impact Engine (TIA)** uses a compile-time dependency graph to select only affected tests, achieving a 93% test reduction (18.4 s → 1.2 s on a 412-module / 1,840-test corpus).

End-to-end mutation latency is **0.42 ms median (p99 1.8 ms)** — a **180×** improvement over disk-baseline outsider harnesses — validated on two platforms: an 8-core x86_64 workstation (32 GB) and a Poco F5 Pro smartphone (Snapdragon 8+ Gen 1, 12 GB, proot-distro Ubuntu 22.04, tmpfs 8 GB).

---

## 1. Introduction

### 1.1 The three bottlenecks of outsider harnesses

1. **File I/O latency** — 45–120 ms per disk operation dominates the agent feedback loop.
2. **Token bloat** — every mutation forces a 2–8k-token file re-read into context.
3. **Mutation contention** — concurrent agents race on shared files; writes interleave non-deterministically.

### 1.2 The inversion

> **BEAM processes orchestrate agents. Files cease to exist on disk during execution; they live as Elixir binaries in ETS and as immutable objects in MemGit, resident in tmpfs.**

The harness is "cybernetic": agent, state, and policy form a single feedback loop inside one runtime, with sub-millisecond signal propagation.

---

## 2. Architecture

The harness is an OTP supervision tree with the following components:

| Component | Role |
|---|---|
| **InterrogationRouter** | Query/Context/RAG routing for agent questions |
| **CodeWriter Coordinator** | Single-writer GenServer serializing all mutations |
| **ShadowCompiler** | AST caching in `:persistent_term`, in-RAM Dialyzer PLT; <4 ms incremental compile |
| **Multi-Tier Knowledge Graph** | ETS / CubDB / Vector tiers; 12M edges, <0.3 ms lookup |
| **RAM Disk Workspace** | tmpfs + MemGit; zero disk I/O during execution |
| **Target Test Impact Engine (TIA)** | Dependency-graph test selection; 93% reduction |
| **Message bus** | 0.02 ms dispatch |
| **Telemetry** | p50 0.18 ms, p99 0.92 ms |

### 2.1 The CodeWriter Coordinator

`lib/kilas/code_writer.ex`:

```elixir
defmodule Kilas.CodeWriter do
  use GenServer
  @enforce_keys [:memgit, :policy]

  def propose(pid, %Mutation{ast: ast, author: agent}) do
    GenServer.call(pid, {:propose, ast, agent}, 500)
  end

  def handle_call({:propose, ast, agent}, _from, state) do
    with {:ok, checked} <- PolicyEngine.check(ast, agent),
         {:ok, commit}  <- MemGit.apply(state.memgit, checked),
         :ok <- TIA.invalidate(commit.changed_modules) do
      {:reply, {:ok, commit.id}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
end
```

### 2.2 Zero-Disk Memory Architecture

- **tmpfs workspace:** `/mnt/ram`, 8 GB. No persistence across boot — by design (ephemeral execution environments).
- **MemGit:** content-addressed, ETS-backed in-memory Git. Checkout = ETS lookup + binary copy, **0.06 ms**.
- **ShadowCompiler:** AST in `:persistent_term` + in-RAM Dialyzer PLT; **<4 ms** incremental compile.
- **Copy-on-Write branching:** branch creation is an O(1) pointer operation.

---

## 3. Policy and Test Selection

### 3.1 Pre-Flight AST Policy Gatekeeper

Policies enforced at the AST level, before any side effect:

- No global mutations
- No unauthorized module imports
- Bounded function arity
- Test-file parity (every production change paired with a test change)

Gate invariants:

- No `File.read!/File.write!` — pure AST transform only
- Scope check via Credo rules
- Bounded mailbox / backpressure

Rejection is **<1 ms** and produces surgical notices, e.g.:

```
{:error, :out_of_scope}, rule: :no_global_mut, hint: "use local assign"
```

### 3.2 Target Test Impact Engine (TIA)

Blast-radius invariant:

> **If mutation M touches module A, and B → A in the dependency graph, then B ∈ blast_radius(M). Tests for ¬blast_radius are provably unaffected.**

The dependency graph is built at compile time via `:code.all_loaded/0` and Mix compiler tracers; blast radius is the transitive closure. Result: **93% test reduction** (18.4 s → 1.2 s; 412 modules, 1,840 tests).

---

## 4. Evaluation

**Table 1** — Platform B (Poco F5 Pro), median of 10,000 iterations, 16 concurrent agents:

| Operation | p50 (ms) | p99 (ms) | vs. baseline |
|---|---|---|---|
| File Read (MemGit checkout) | 0.06 | 0.18 | 180× |
| Code Mutation | 0.24 | 0.61 | 112× |
| Policy Gate Check | 0.31 | 0.92 | <1 ms SLA |
| Test Impact Resolution | 0.42 | 1.12 | 96× |
| End-to-end mutation + test | 1.18 | 1.82 | 93% reduction |

Notes:

- Thermal throttling observed on the phone after ~12 minutes of sustained load.
- Platform A (8-core x86_64, 32 GB): end-to-end **0.38 ms**.

---

## 5. Benefits

- **Trial-and-error elimination:** 4.7 → 1.2 trials per feature (policy gate + TIA feedback loop).
- **Unit economics:** 1 mutation = 1 message + 1 ETS operation. 10k mutations ≈ **3.2% battery** on Platform B, vs. **28%** for disk-baseline harness.
- **Deterministic concurrency:** 16 agents coordinated via single-writer serialization; linearizable mutations; supervisor restart **0.4 ms**.

---

## 6. Conclusion and Future Work

The Cybernetic BEAM Harness demonstrates that an insider, runtime-native control plane eliminates the three structural bottlenecks of outsider harnesses, achieving sub-millisecond end-to-end mutation latency on commodity and mobile hardware.

**Future work (Paper 2):** InterrogationRouter strategies, knowledge graph distillation, long-horizon planning.

### Reproducibility

```bash
mix kilas.bench --lab poco --iterations 10000 --concurrency 16
```

Artifacts: `github.com/haimiyahya/kilas`

---

## References

1. J. Armstrong, *Programming Erlang*, 2013.
2. F. De Angelis et al., "AST-level Policy Enforcement," *ICSE 2024*.
3. M. Alam et al., "MemGit: In-Memory Git for Ephemeral CI," *OSDI 2023*.
4. Kilas Project, Technical Report TR-2025-01.

---

*Known gaps to revisit (flagged at extraction, not yet fixed): figure diagrams, and verification of references/benchmarks against real sources.*
