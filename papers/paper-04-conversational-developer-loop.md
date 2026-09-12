# The Conversational Developer Loop: Expanding Autonomous Harness Interactions Beyond Code Generation

**Paper 4 — Kilas Project · Research Series**
*From Code-Centric to Developer-Centric Autonomy on Mobile*

| | |
|---|---|
| **Author** | Mohd Norhaimi Bin Yahya |
| **Affiliation** | Kilas Project • Autonomous Mobile Development Lab |
| **Lab** | Poco F5 Pro 12GB Lab • Snapdragon® 8+ Gen 1 • Android 14 + PRoot-Distro |
| **Version** | Header tag reads "v1.2 → v2.0 Proposal" — no version number is given for the paper itself. |
| **Date** | Not stated in header; footer reads "© 2025". |
| **Contact** | norhaimi@kilas.dev • kilas.dev/papers/4 |
| **License** | CC BY-SA 4.0 (footer). Conflicts with Paper 1's "MIT Licensed" — flagged at extraction, not corrected. |
| **Series position** | Header reads "Kilas Project • Paper 4" — consistent with the 4-paper plan. However, the footer "Paper Series" list renames Papers 1–3 as "MemGit — Volatile-First Git", "ShadowCompiler — Zero-Fork Compilation", "Housekeeper — Autonomous Maintenance", which do not match the titles of the delivered Papers 1–3 (MemGit, ShadowCompiler, Housekeeper are all components described in Paper 1). Flagged at extraction — not corrected. |
| **Keywords** | Conversational AI · Mobile Development · BEAM · PRoot · Developer Experience · GraphRAG |
| **Source** | Extracted from a React artifact (pasted 2026-09-11) into Markdown. Figures were 9 inline SVG diagrams in the source (artifact meta line: "9 SVG diagrams hand-drawn"); they appear here as placeholders with their text content transcribed. Content transcribed as-is — no corrections applied yet. Storage revised 2026-09-11: KùzuDB references updated to the DuckDB + libgraph architecture adopted in kilas-spec-v2. Storage revised 2026-09-12: tmpfs references updated to the volatile-workspace design (validation proved PRoot on this device has no tmpfs — see `.tools/validate/RESULTS.md` row 1). |

---

## Abstract

Kilas v1.2 implements a robust conversational loop for *code manipulation*: query, generation, updates, compilation, and intent negotiation, achieving <10ms interactions on Android PRoot through volatile-first, zero-fork design. Yet field studies of developer workflows reveal that code manipulation constitutes only ~30% of the actual developer loop. The remaining 70% — debugging runtime failures, live experimentation, performance profiling, environment repair, security review, resource survival on constrained devices, teaching, and multi-agent collaboration — remains conversationally inaccessible.

This paper identifies seven interaction gaps and proposes a unified conversational developer loop (v2.0). We present architecture for each gap leveraging existing Kilas substrates: ETS bindings for interrogative debugging, persistent REPL ports over the volatile workspace for zero-NAND experimentation, DuckDB-backed flamegraphs for battery-aware profiling, Housekeeper EnvGraph for self-healing dependencies, libgraph GraphRAG for security policy chat, ShadowSync NAND accounting for survival advisory, and a temporal collaboration log for tutoring. All designs preserve the core invariants: 90% BEAM-native, <15ms latency for runtime layers, <50ms for environment layers, and zero process forks in the fast path on Poco F5 Pro 12GB. We show how expanding from a code harness to a developer OS reduces mean time-to-understanding by 3.2× without sacrificing the battery and NAND durability that makes mobile-native development viable.

---

## Contents

1. Introduction: Beyond Code That Can Talk
2. Current Interaction Model (Kilas v1.2)
3. Seven Gaps and Architectures
   a. Debugging & Runtime Inspection
   b. Live REPL & Experimentation
   c. Performance & Profiling for Mobile
   d. Environment & Dependency Doctor
   e. Security & Policy Chat
   f. Survival & NAND Advisor
   g. Teaching & Collaboration Log
4. Unified Interaction Taxonomy v2.0
5. Empirical Impact
6. Conclusion: From Harness to OS for Mobile Dev

---

## 1. Introduction: Beyond Code That Can Talk

The dominant metaphor for AI-assisted development is *code generation*. Prompt in, code out. Tools like Copilot, Cursor, and Kilas v1.2 have made this loop conversational: developers can query a codebase in natural language, request patches, negotiate intent when ambiguity arises, and see compilation feedback within milliseconds on-device. This is a substantial advance over autocomplete.

Yet ethnographic logging from 47 hours of Kilas usage on Poco F5 Pro reveals a sobering distribution. We instrumented the harness to classify every developer utterance across 1,240 turns. Only 31.2% were code-centric (query, generate, update). The remainder partitioned as follows: 19.4% debugging ("why is this nil?", "what's in scope here?"), 12.1% environment ("missing library", "Elixir version mismatch"), 11.3% performance ("why is this slow on device?"), 8.7% exploratory REPL ("what if I try..."), 7.9% security/compliance checks, 5.1% teaching/explanation, and 4.3% collaboration/handoff. In other words, **the harness covers the minority of the loop**.

The developer loop is not `edit → compile → test` but `think → try → fail → understand → fix → survive → teach → deploy`. Code generation solves *try* and partially *fix*. It leaves *fail, understand, survive, teach* untouched.

This paper argues that the next architectural frontier is not better generation, but a **full conversational developer loop**. We present Kilas v2.0: a unified interaction model that treats debugging, profiling, environment, security, survival, and collaboration as first-class conversational endpoints, all implemented under the same volatile-first, zero-fork constraints that make v1.2 viable on Android PRoot.

> **Core Thesis:** "A developer harness must become a developer OS: every layer of the stack — runtime, env, battery, NAND, knowledge, team — must be interrogatable in natural language, with <15ms latency and zero mandatory NAND writes, otherwise mobile autonomy fails."

---

## 2. Current Interaction Model (Kilas v1.2)

Kilas v1.2 implements six interactions, all BEAM-native and backed by MemGit (ETS + the volatile workspace) and DuckDB + libgraph GraphRAG:

| Interaction | Description | Status |
|---|---|---|
| **Query** | Natural language → libgraph traversal (DuckDB edges) → AST nodes + provenance | ✓ Live |
| **Generate** | Intent → ShadowCompiler spec → workspace draft → MemGit commit | ✓ Live |
| **Update** | Targeted patch via AST edit, not rewrite, 3-way merge aware | ✓ Live |
| **Compile** | ShadowCompiler persistent Port, no fork, ETS error cache | ✓ Live |
| **Discuss** | GraphRAG intent negotiation, ambiguity detection | ✓ Live |
| **Run Commands** | Persistent Port shell, stdout → ETS, <10ms echo | ✓ Live |

These six achieve 80% of *code time* but only 30% of *developer time*. The missing pieces cluster around state that v1.2 discards: runtime bindings, profiler samples, shell env state, CVE graphs, NAND counters, and multi-agent edit histories.

> **Figure 1 — Current vs Full Developer Loop** *(SVG placeholder — concentric ring diagram, "DEVELOPER INTENT — Full Loop Coverage")*
>
> Inner ring (green, "Kilas v1.2 — Implemented (6)"): Query, Generate, Update, Compile, Discuss, Run.
> Outer ring ("Gap — Missing Runtime (8)"): Debug, REPL, Profile, Env Doctor, Security, Survival, Tutor, Collaboration.
> Center: "Developer Intent" — annotated "Center = Intent Negotiation", with arrow "30% → 100% loop".

---

## 3. Seven Gaps and Architectures

### 3.1 Debugging & Runtime Inspection

**Problem:** Test fails at `auth.ex:42 user_id is nil`. Developer asks "Why?". v1.2 can show the file but not the runtime binding at failure time, nor which commit introduced the nil path.

**Architecture — Conversational Debugger:** ShadowCompiler's persistent Port captures exceptions via `:erlang.get_stacktrace()` + `Binding` at crash. We store in ETS table `:kilas_runtime_bindings` with schema `{node_id, file, line, var, value, timestamp, test_id}`. Interrogation Router adds verb `get_runtime_value(ast_node_id)`. Query path: (1) libgraph traverses `ASTNode -TOUCHED_BY-> Commit -AUTHORED_BY-> Agent` (edges loaded from DuckDB) to find historical mutations of line 42, (2) ETS lookup returns live binding, (3) Answer synthesizes: "user_id nil because Guardian.Plug returned nil at line 38 when token expired — introduced in commit a3f9 by agent-1, 2 days ago". Zero fork, <5ms ETS lookup.

> **Figure 2 — Conversational Debugger Flow** *(SVG placeholder)*
>
> Flow: Test Fails (auth.ex:42 user_id=nil) → ShadowCompiler (captures stacktrace + bindings in ETS `:kilas_runtime_bindings`; persistent Port, 0 fork) → Developer Query "Why user_id nil at auth.ex:42?" (Interrogation Router) → Synthesized Answer.
>
> ETS `:kilas_runtime_bindings` contents as drawn:
>
> | node_id | var | value | line | history |
> |---|---|---|---|---|
> | a42 | user_id | nil | 42 | commit a3f9 |
> | a38 | token | %Expired | 38 | 2 days ago |
> | a38 | conn | %Plug.Conn | 38 | agent-1 |
> | → | Guardian.Plug | returned nil | | root cause |
>
> Notes: `get_runtime_value(ast_node_id)` → O(1) ETS lookup, <2ms; libgraph: `ASTNode -TOUCHED_BY-> Commit -AUTHORED_BY-> Agent` (edges from DuckDB); No fork, BEAM-native, survives PRoot.
>
> Synthesized Answer: "user_id is nil because Guardian.Plug returned nil at auth.ex:38 when token expired. No fallback assign." History: commit a3f9 by agent-1, 2 days ago, touched Guardian call, removed nil guard. Suggested fix: add guard. Latency: ETS 1.2ms + libgraph BFS 4.1ms = 5.3ms total. PRoot forks: 0 • NAND writes: 0. Battery: <0.1% impact.

### 3.2 Live REPL & Experimentation

**Problem:** Developer wants to test `hash_password("test") with algo=:sha3` without committing, without NAND wear, without polluting MemGit history. Traditional IEx forks, writes to disk, and is not conversationally addressable.

**Architecture — Live Lab:** Persistent IEx Port lives in `/tmp/kilas_lab` (volatile workspace: plain f2fs dir, 1GB quota on 12GB device, served by the kernel page cache — PRoot has no tmpfs, validated 2026-09-12). Eval is tagged `:ephemeral`, result stored in ETS, never in MemGit. Developer utterance "What if algo=:sha3?" → Router → `Lab.eval("hash_password('test', algo: :sha3)")` → Port receives, evals in isolated binding, returns `32 bytes`. UI shows result with amber badge "volatile only — no NAND write". If developer says "commit this", then MemGit transaction promotes ephemeral to durable. This enables 200+ experiments/hour with zero NAND wear, critical for UFS longevity on Poco F5 Pro (TLC NAND, ~1,000 P/E cycles).

> **Figure 3 — Live Lab in the volatile workspace** *(SVG placeholder)*
>
> Flow: Developer "What if algo=:sha3?" → Interrogation Router (`Lab.eval/1`, `:ephemeral` tag) → `/tmp/kilas_lab — volatile workspace (f2fs, page-cached)`: IEx Persistent Port (PID 42, alive 3h, 0 fork; 2.1MB / 1GB quota); eval: `hash_password('test', algo: :sha3)` (no MemGit commit); → 32 bytes: `<<19, 34, 92...>>`; Time: 8ms • NAND: 0 writes. Badge: "volatile only". → Result: 32 bytes SHA3-256; "Copy / Commit?"; NAND saved: ~4KB vs ext4 commit.
>
> Footer comparison: Traditional IEx: fork + ext4 write 4KB + journaling 12KB = 16KB NAND per eval → 200 evals = 3.2MB/day wear. Kilas Live Lab: hot state in BEAM RAM (ETS), page-cached workspace only, 0 NAND, 200 evals = 0KB NAND, 2.1MB RAM, <10ms latency, 0 forks.

### 3.3 Performance & Profiling for Mobile

**Problem:** Login endpoint 800ms on Poco F5 Pro, developer asks "Why login slow?". v1.2 cannot answer. Need CPU profiling that respects battery and NAND constraints — traditional `:fprof` writes 50MB traces to ext4, triggering GC and thermal throttling on Snapdragon.

**Architecture — Perf Interrogation:** ShadowCompiler spawns :fprof / Go pprof / py-spy in persistent Port but redirects output to the volatile workspace (`/tmp/kilas_prof/*.trace`). Parser extracts hotspots, stores aggregated flamegraph nodes in DuckDB table `perf_samples(function, calls, pct, battery_impact)`. Query "Why login slow?" → DuckDB `SELECT * ORDER BY pct DESC LIMIT 5` → `hash_password/1 80% 10k calls, no cache` → estimates battery +15%/hr if uncached (PBKDF2 100k rounds). Suggests memoization. All profiling artifacts live in the page-cached workspace — purged after aggregation, zero mandatory NAND in the loop.

> **Figure 4 — Perf Interrogation** *(SVG placeholder)*
>
> Flow: Developer "Why login slow?" → ShadowCompiler runs :fprof / pprof in a persistent Port (traces to `/tmp/kilas_prof/*.trace`) → DuckDB `perf_samples` (function / pct / calls: hash_password/1 80% 10k; Repo.get/2 12% 2k; Jason.encode/1 5% 1k; Battery impact +15%/hr) → Answer.
>
> Answer: hash_password/1 80% CPU, no cache; 10k calls × PBKDF2 100k rounds. Before/After cache: 80% → 5%. Battery: 15%/hr → 3%/hr.
>
> Flamegraph (stored in DuckDB, rendered from the volatile workspace): login/2 — 800ms total — 1 call; hash_password/1 — 640ms (80%) — 10k calls — PBKDF2 100k; Repo.get — 96ms; Jason — 40ms. "Critical for Snapdragon: 8+ Gen 1 thermal throttles at 42°C after 640ms sustained crypto. Cache reduces to 40ms." DuckDB query: `SELECT function, SUM(pct) FROM perf_samples GROUP BY function ORDER BY SUM(pct) DESC` — <4ms. All traces in /tmp/kilas_prof — page-cached, batched to flash by ShadowSync — purged after aggregation.
>
> Battery Impact Model: Traditional :fprof writes 50MB ext4 → +8%/hr. Kilas volatile-workspace trace (page-cached, batched flush) 2MB → +0.3%/hr. Snapdragon 8+ Gen 1: perf cores 3.2GHz, thermal budget 5W sustained — crypto must cache.

### 3.4 Environment & Dependency Doctor

**Problem:** Build fails: `libssl-dev missing`. Developer stuck in apt-get loop, manual proot-distro shell breaks flow. On Android, fork() inside PRoot was assumed to cost 80-120ms (disproven 2026-09-12: measured 3.6ms/fork); zero-fork remains a design goal for battery and jank reasons, not fork latency.

**Architecture — Env Doctor:** Housekeeper maintains EnvGraph as typed edges in DuckDB, projected into libgraph: `ErrorRegex -MAPS_TO-> AptPackage -INSTALLS_VIA-> ShellCommand`. When ShadowCompiler returns non-zero, error string matched against 200+ regex patterns. Match → auto generates install command, execs it on demand via System.cmd (3.6ms/fork measured — trivial next to the 1-3s apt run itself), then retries compile. Latency: regex match <2ms (ETS), install 1-3s (once), retry <50ms. Preserves volatile-first: EnvGraph itself lives in BEAM RAM (ETS), synced to the physical repo only on explicit `:kilas env save`.

> **Figure 5 — Env Doctor** *(SVG placeholder)*
>
> Flow: Build Fails (libssl-dev missing) → Housekeeper EnvGraph (libgraph regex → package: `/libssl.*not found/` → libssl-dev; `/openssl.*header/` → libssl-dev; 200+ patterns • ETS cache <2ms) → System.cmd (`apt install libssl-dev`; exec on demand, 3.6ms/fork measured) → Retry Compile (✓ success, <50ms retry, auto).
>
> Footer: Flow: Error regex (ETS <2ms) → libgraph EnvGraph → apt package → System.cmd → retry. Traditional: fork shell per build — 3.6ms/fork measured (originally assumed 80-120ms) × 10 failures ≈ 36ms + NAND journal. Kilas: exec on demand, error cache in ETS, EnvGraph in BEAM RAM, <50ms env fix.

### 3.5 Security & Policy Chat

**Problem:** Developer asks "Is this safe?" about auth.ex. v1.2 can discuss code but cannot traverse vulnerability graphs, run `cargo audit` or `mix audit` conversationally, nor link AST nodes to CVE databases.

**Architecture — Security GraphRAG:** DuckDB edge tables (`graph_edges`: DEPENDS_ON, HAS_VULN, FIXED_BY) projected into libgraph at boot: `ASTNode -DEPENDS_ON-> Package -HAS_VULN-> CVE -FIXED_BY-> Commit`. Package versions extracted by ShadowCompiler during compile. On query "Is this safe?", Interrogation Router: (1) finds AST nodes in file, (2) traverses to Packages, (3) checks Vulnerability nodes (populated by nightly `cargo audit` in persistent Port, result cached in DuckDB), (4) returns SQL injection at line 12 (string interpolation in Ecto), plus `cargo audit` report. Answer includes fix suggestion: parameterized query. Latency <10ms for graph traversal, 1/min Port for audit.

> **Figure 6 — Security GraphRAG** *(SVG placeholder)*
>
> Graph chain: ASTNode (auth.ex:12) —DEPENDS_ON→ Package (ecto 3.11.0) —HAS_VULN→ Vulnerability (CVE-2024-1234 SQLi) → Fix (Param query).
>
> 1. libgraph traversal (edges loaded from DuckDB): start at `auth.ex` ASTNodes, follow DEPENDS_ON then HAS_VULN edges, return `(line, cve, severity)` per Vuln. Latency: <8ms, 0 fork. Graph held in BEAM memory.
> 2. Audit cache (DuckDB): cargo audit — nightly Port; mix audit — nightly Port; Result cached: ecto 3.11.0 → CVE-2024-1234 MEDIUM; 1/min fork max, volatile result.
> 3. Synthesized Answer: ⚠️ SQL injection at auth.ex:12. Ecto query uses string interpolation; `"where: u.id == ^id" not "where: fragment"`. Fix: use parameterized query — `from u in User, where: u.id == ^id`. Battery: <0.1% • NAND: 0 • Forks: 0.

### 3.6 Survival & NAND Advisor (Mobile Specific)

**Problem:** Mobile development on UFS 3.1 (Poco F5 Pro) has finite P/E cycles (~1,000-3,000 for TLC). Traditional dev loops — git commits, npm install, cargo builds — write 50-200MB/hour to NAND, accelerating wear. Battery drain 15%/hr under load. OOM killer terminates BEAM under memory pressure; workspace overgrowth is bounded by a quota instead. Developers have no conversational visibility into these constraints.

**Architecture — Survival Check:** Housekeeper tracks three counters in ETS: `nand_writes_bytes` (via ShadowSync batch accounting), `battery_pct_per_hr` (via Android dumpsys), `workspace_used` (via `du -sb`). Query "Will this survive overnight?" → returns dashboard: NAND writes 0 during loop (vs 480 batched/day in v1.2), battery <5%/hr (vs 15% traditional), OOM risk Low (2MB of the 1GB workspace quota). ShadowSync batches 480 writes/day vs traditional immediate fsync per file. Conversational advisor suggests "workspace at 80%, run `:kilas gc`" or "battery 18%, enable low-power mode (pause profilers)". All survival metrics <5ms ETS reads.

> **Figure 7 — Survival Check** *(SVG placeholder — "Kilas Survival Dashboard — Query: 'Will this survive overnight?'")*
>
> Gauges: NAND Writes — "0 KB during loop" (480 batched/day vs traditional 50MB/hr). Battery — "<5% per hour" (Traditional 15%/hr • 3× improvement). OOM Risk — "Low" (2MB / 1GB workspace quota; BEAM safe • GC at 800MB).
>
> ShadowSync vs Traditional fsync — NAND writes per hour: Traditional dev loop (git + npm + build): 50MB/hr • 1.2GB/day • 400 days to 1k P/E. Kilas v2.0 volatile-first + batch: 0.48MB/day batched • 0KB during loop • 8,500 days to 1k P/E.

### 3.7 Teaching & Collaboration Log

**Problem:** Developer asks "Explain auth flow as story" — v1.2 can return AST but not pedagogical narrative. Multi-agent edits collide: Agent-1 edits auth.ex line 20, Agent-2 edits same line 2s later, human edit rejected without explanation.

**Architecture:** Tutor mode uses GraphRAG to fetch simplified subgraph (hide crypto internals, show story: User → Token → Guardian → DB), then prompts LLM with analogy scaffolding. Collaboration log stores every edit in DuckDB `edit_log(file, line, agent, timestamp, lock_id, status)`. Lock reservations via ETS `:kilas_locks` — 5s lease per file range. On collision, answer explains "Edit rejected: Agent-1 holds lock on auth.ex:18-25 until 14:03:02, reserved for token refresh logic". Both features preserve zero-fork: tutoring is libgraph + ETS only, collaboration log is DuckDB query <5ms.

> **Figure 8 — Tutor & Multi-Agent** *(SVG placeholder, two panels)*
>
> Left — Tutor: "Explain auth flow as story". Simplified GraphRAG → Mermaid + Analogy: User (key) → Guardian (bouncer) → Token (wristband) → checks expiry (bouncer looks at date) → DB (VIP list). Hides: PBKDF2 100k rounds, ETS bindings. Shows: story, 3 steps, why nil happens (lost wristband). Mermaid flow (generated): `graph LR` / `A[User request] --> B{Token expired?}` / `B -->|yes| C[user_id=nil]` / `B -->|no| D[DB lookup]`. Latency: libgraph BFS 6ms + LLM 200ms = 206ms. NAND 0 • Forks 0 • ETS only for graph.
>
> Right — Collaboration Log & Locks, timeline of edits to auth.ex:
>
> | Time | Editor | Edit | lock | status |
> |---|---|---|---|---|
> | 14:02:55 | Agent-1 | line 18-25 | reserve 5s | ✓ lock |
> | 14:02:57 | Agent-2 | line 20 | conflict | ✗ rejected |
> | 14:03:00 | Human | line 42 | free | ✓ committed |
> | 14:03:02 | Agent-1 | release | expired | released |
>
> "Why edit rejected — conversational: 'Agent-2, your edit to auth.ex:20 was rejected because Agent-1 holds lock on 18-25 until 14:03:02 for token refresh logic.'" DuckDB edit_log query <5ms • ETS locks O(1). Zero fork • 0 NAND • PRoot safe.

---

## 4. Unified Interaction Taxonomy v2.0

We unify all interactions into six layers, each with explicit latency and fork budgets for Poco F5 Pro 12GB. The taxonomy guides implementation: Layer 1-2 spawn nothing; Layer 3-6 exec on demand (3.6ms/fork measured — only genuinely interactive processes like the LiveLab IEx keep a persistent Port).

| Layer | Interactions | v1.2 | v2.0 | Latency Poco F5 Pro | PRoot Forks |
|---|---|---|---|---|---|
| **Layer 1 — Code** | Query, Generate, Update, Compile, Test | Yes | Yes | <10ms | 0 |
| **Layer 2 — Runtime** | Debug, Profile, REPL | No | Yes | <15ms | 0 |
| **Layer 3 — Environment** | Env Doctor, Dep Mgmt, Survival | No | Yes | <50ms | 1/min |
| **Layer 4 — Knowledge** | Discuss, Explain, Teach, Security | Partial | Yes | <10ms | 0 |
| **Layer 5 — Collaboration** | Multi-Agent Log, History | No | Yes | <5ms | 0 |
| **Layer 6 — Deploy** | Build artifact, Push | Partial | Yes | <100ms | 1/min |

> **Figure 9 — Full Loop Architecture (Hexagon)** *(SVG placeholder — "Kilas v2.0 — Full Conversational Developer OS")*
>
> Central BEAM node (Elixir 1.16, OTP 26 • 90% native) connects in a hexagon to: Layer 1 Code (Query Gen Update), Layer 2 Runtime (Debug REPL Profile), Layer 3 Env (Doctor Survival), Layer 4 Knowledge (Teach Security), Layer 5 Collab (Multi-Agent Log), Layer 6 Deploy (Build Push).
>
> Backing stores: volatile workspace (f2fs, 1GB quota), ETS (Bindings), DuckDB (Perf+Logs+Edges), libgraph (in-memory GraphRAG), Persistent Ports.
>
> Legend: 90% BEAM-native zero-fork (green) • 10% persistent ports amber — 1/min max • All layers <50ms on Poco F5 Pro.
>
> Caption: Central BEAM node connects to 6 layers in hexagon. Each layer backed by the volatile workspace (experiments; page-cached f2fs), ETS (O(1) bindings/locks), DuckDB (perf + edit log + durable graph edges), libgraph (in-memory knowledge + security + env graph), and persistent Ports (reuse, not fork). 90% green = zero-fork BEAM-native, 10% amber = 1/min Port.

---

## 5. Empirical Impact

We measured Kilas v2.0 prototype on Poco F5 Pro 12GB (Snapdragon 8+ Gen 1, volatile workspace on f2fs, UFS 3.1). Workload: 1 hour of mixed developer tasks (code, debug, profile, env fix, security check, tutor). We compare traditional Android dev (Termux + git + mix + IEx) vs Kilas v2.0.

**Pareto — Fast vs Slow Path** *(panel in source)*: Ops per hour: 800 fast, 5 slow — Time saved 11.2s vs 1.5s.
- Fast path (parse, MemGit, TIA, File read): 800 ops • 80% time • 11.2s saved.
- Slow path (full builds, audit): 5 ops • 20% time • 1.5s overhead.
- Kilas keeps 80% of interactions in fast path via the volatile workspace/ETS/DuckDB/libgraph. Slow path amortized: 1 Port reused, not forked per op.
- Net: 11.2s saved − 1.5s overhead = **9.7s net saved per hour**. Equivalent to **16% faster dev loop on mobile**. All fast path <10ms, slow path <100ms, 0 NAND during loop.

**Battery — Traditional vs Kilas v2.0** *(panel in source)*: Battery drain per hour — 1hr mixed workload.
- Traditional Termux + git + mix: **15%/hr** (forks 40/min • fsync 50MB).
- Kilas v2.0 volatile-first: **<5%/hr** (0 fork fast path • 1/min slow).
- Why 3× improvement: zero fork fast path — 800 ops × 0 fork vs 40/min × 60 = 2,400 forks saved; page-cached workspace, not journaled ext4 — writes batched by ShadowSync, no constant UFS GC wakeups; persistent Ports — 1 shell reused, not spawn/kill per command.

**Mean Time to Understanding (MTTU):** We measured time from "test fails" to developer correctly identifies root cause. Traditional flow (read logs, add IO.inspect, recompile): 4.2 minutes. Kilas v2.0 conversational debugger (ask "why nil?", get binding + history): 1.3 minutes. **3.2× improvement**, statistically significant (p<0.01, n=24 failures).

**NAND longevity:** Projected P/E exhaustion for 256GB UFS 3.1 TLC (1k cycles, ~256TBW). Traditional: 50MB/hr × 8hr/day × 300 days = 120GB/year → 2.1 years to 256TBW if device used only for dev (unrealistic, but shows pressure). Kilas v2.0: 0.48MB/day batched × 300 = 0.144GB/year → 1,777 years. Volatile-first makes mobile dev sustainable.

---

## 6. Conclusion: From Harness to OS for Mobile Dev

Kilas began as a code harness — a way to make BEAM survive Android PRoot without forks. v1.2 proved that <10ms conversational code manipulation is possible on a phone. This paper shows that code is the minority of the loop. The majority — debugging, experimenting, profiling, fixing environments, checking security, surviving battery/NAND, teaching, collaborating — can also be conversational, and must be if mobile autonomy is to succeed.

The architectural insight is reuse: the same substrates that made v1.2 fast (ETS for bindings, the volatile workspace for drafts, DuckDB for logs and durable graph edges, libgraph for in-memory traversal, persistent Ports for shells) also make v2.0's seven gaps fast. No new fork-heavy daemons, no new ext4 writes, no new battery drains. The conversational developer loop is not 7 new features, but 7 new queries over existing volatile stores.

We propose Kilas v2.0 as a **developer OS**: not an IDE, not a chatbot, but an OS layer where every developer intent — code, runtime, env, security, survival, teaching — is a first-class conversational endpoint with <50ms latency and zero mandatory NAND writes. On Poco F5 Pro 12GB, this OS runs in 2.1MB workspace + 50MB BEAM, <5%/hr battery, 0 forks in fast path, and makes the 70% of developer time that v1.2 ignored conversationally accessible.

**Future work:** implement Layer 2-5 routers, measure MTTU across 100 developers, and open-source the EnvGraph pattern library (200 regex → apt mappings). The goal remains: a phone that can autonomously develop, debug, profile, secure, survive, and teach — all through conversation.

> **Reproducibility:** All measurements on Poco F5 Pro 12GB, Snapdragon 8+ Gen 1, Android 14, PRoot-Distro Ubuntu 22.04, Elixir 1.16.2 OTP 26, volatile workspace (f2fs, 1GB quota), libgraph, DuckDB 0.10.1. Code, EnvGraph, and perf traces: `github.com/haimiyahya/kilas`. NAND write accounting via `/proc/diskstats` + ShadowSync counters. Battery via `dumpsys batterystats`.

---

*Source footer: "Kilas Project — Paper 4" • "© 2025 Mohd Norhaimi Bin Yahya • Kilas Project • Licensed CC BY-SA 4.0"*

*Source footer "Paper Series" list: "Paper 1: MemGit — Volatile-First Git" • "Paper 2: ShadowCompiler — Zero-Fork Compilation" • "Paper 3: Housekeeper — Autonomous Maintenance" • "Paper 4: Conversational Developer Loop (this)" — these titles do not match the delivered Papers 1–3 (see provenance table).*

*Source footer build line: "Built on Poco F5 Pro 12GB Lab • Snapdragon 8+ Gen 1 • Android PRoot • BEAM • DuckDB • libgraph • ETS • volatile workspace" (source said "tmpfs"; revised 2026-09-12 — see storage-revision note in the provenance table)*

---

*Known gaps to revisit (flagged at extraction, not yet fixed): all 9 SVG figures are placeholders (text transcribed, not redrawn); verification of references/benchmarks and the 47-hour / 1,240-turn field study; no external references section. Footer "Paper Series" renames Papers 1–3 ("MemGit — Volatile-First Git" / "ShadowCompiler — Zero-Fork Compilation" / "Housekeeper — Autonomous Maintenance") — mismatch with delivered paper titles. Stack oscillation: resolved 2026-09-11 — all papers unified on DuckDB edge tables + libgraph (this paper originally used KùzuDB for graphs; Paper 3 had used DuckDB + vec0). Version/device drift: Elixir 1.16.2 / OTP 26 (Paper 3 said 1.17), Android 14 (Paper 3 said Android 13 MIUI 14), tmpfs "8GB available" in §5 vs "1GB budget" in §3.2/Figure 9/Reproducibility — RESOLVED 2026-09-12: validation proved PRoot on this device has no tmpfs at all (RESULTS.md row 1), so all tmpfs references in this paper were rewritten to the volatile workspace (BEAM RAM hot state + page-cached f2fs, ShadowSync batching), eliminating the 8GB-vs-1GB-vs-mounts-fail contradiction, license CC BY-SA 4.0 (Paper 1 said MIT). NAND arithmetic internally inconsistent: "120GB/year → 2.1 years to 256TBW" only holds if endurance is 256GB, not the stated ~256TBW (256TB would give ~2,133 years); Figure 7's "400 days to 1k P/E" (at 1.2GB/day, implies ~480GB budget) and "8,500 days to 1k P/E" (at 0.48MB/day, implies ~4GB budget) cannot share the same endurance figure. Contact differs from Paper 3 (norhaimi@kilas.dev vs mohd.norhaimi@kilas.dev); github.com/kilas-project/paper4 renamed 2026-09-11 to github.com/haimiyahya/kilas; kilas.dev/papers/4 unverified/likely placeholder. §5 "16% faster dev loop" derivation unstated. TIA appears in §5 fast-path list without expansion (Paper 1: "Target Test Impact Engine"; Paper 3 renamed it "Transactional Intent Assessment"). Reconciled 2026-09-12: fork cost — §3.4's "80-120ms per fork" was DISPROVEN by measurement (3.6ms/fork on this device, RESULTS.md row 11); §3.4/Figure 5 rewritten to exec-per-command via System.cmd, with zero-fork retained as a fast-path design goal (battery/jank) and PersistentPort scoped to genuinely interactive processes (LiveLab IEx); TIA's canonical name is Target Test Impact Engine everywhere. Latency budgets: this paper's layer table (<15ms runtime, <50ms environment) is aspirational; the operative spec (kilas-spec-v2.md §08) targets Profile <100ms and Env fix <5s.*
