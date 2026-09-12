# Conversational Codebases: Replacing Structural Inspection with Interrogation and Historical Lineage in Autonomous Agents

**Paper 2 — Kilas Project · Research Series**
*Paper 2: Interface & Institutional Memory — Code That Can Talk*

| | |
|---|---|
| **Author** | Mohd Norhaimi Bin Yahya |
| **Affiliation** | Kilas Project |
| **Lab** | POCO F5 PRO 12GB LAB |
| **Date** | December 2024 · Kuala Lumpur |
| **Series position** | Source artifact header reads "Paper 2 / 3" and footer "Paper 2 of 3". This conflicts with Paper 1 ("Paper 1 of 4") and the stated 4-paper plan. Flagged at extraction — not corrected. |
| **Keywords** | Conversational Codebases · DuckDB · libgraph · MemGit · Chesterton's Fence · BEAM · Agentic RAG |
| **Source** | Extracted from a React artifact (pasted 2026-09-11) into Markdown. Figures were SVG diagrams in the source; they appear here as placeholders with their text content transcribed. Content transcribed as-is — no corrections applied yet. Storage revised 2026-09-11: KùzuDB references updated to the DuckDB + libgraph architecture adopted in kilas-spec-v2; performance claims scoped 2026-09-11 to AST-measured BFS benchmarks (≈0.7ms per 1k edges, Poco-class ARM). |

---

## Abstract

Autonomous coding agents operating on large repositories fail not due to weak reasoning, but due to **structural inspection**. Current approaches force agents to reconstruct architecture from raw text via grep, vector search, and embedding retrieval—dumping 50k–120k tokens of fragmented files into context, triggering window inflation, architectural drift, and historical blindness. We introduce **Conversational Codebases**, a protocol shift from inspection to interrogation: the codebase becomes an active interlocutor backed by a multi-tier knowledge graph (Property Graph + Temporal Memory + Vector Index) that negotiates architectural intent, enforces style policies, and preserves institutional memory. Our implementation pairs embedded DuckDB edge tables with an in-process libgraph projection for AST call graphs and spec relationships, MemGit lineage for commit provenance and stripped-comment recovery, and a validated plug-and-play vector store (DuckDB vss HNSW primary / sqlite-vec fallback) for intent mapping—all within the agent process with <2ms query latency at core-graph scale (≤~2k edges); worst-case full-repo traversal measured at ~6.6ms on a ~360k-LOC polyglot codebase (~10k edges). Evaluation on 120 architectural tasks shows a **96.2% token reduction** (85k → 3.2k) and **2.8× improvement** in first-turn completion (32% → 92%), while historical regression rate drops from 18.4% to <0.5% via Chesterton's Fence enforcement. The codebase no longer needs to be read; it can be asked.

---

## 1. Introduction: From Inspection to Interrogation

Autonomous agents excel at reasoning but collapse at *repository-scale implementation*. The dominant paradigm—structural inspection—treats source code as a passive text corpus to be searched. An agent tasked with "add SHA-3 hashing for spec #42" will grep for `hash`, retrieve embeddings for crypto files, and concatenate 15–30 full files into its prompt. The result is not knowledge, but noise.

We identify three systemic failure modes that inspection cannot solve:

1. **Context Window Inflation** — Dumping raw files consumes 50k–120k tokens per task. After two tool calls, the model loses track of original intent. RAG retrieves syntactically similar but architecturally irrelevant code.
2. **Architectural Drift** — Without global style policies, agents create new modules where extension was required, duplicate utilities, and violate single-responsibility boundaries enforced only by human convention.
3. **Historical Blindness** — Chesterton's Fence: why does `txn_status=1` exist? Grep cannot answer. Stripped comments, intern cleanups, and undocumented constraints cause 18.4% regressions.

We propose inverting the relationship: instead of the agent inspecting the codebase, the **codebase interrogates the agent's intent**. A conversational codebase exposes a JSON-RPC interface—`ask(intent, context)`—that returns not files, but decisions: graph paths, affected files, policy-compliant templates, and historical justification. This paper details the architecture enabling that inversion.

> **Figure 1 — Inspection Paradigm Shift** *(SVG placeholder)*
>
> Left panel — *Traditional Inspection Model*: AGENT → (Grep / Embeddings) → RAW SOURCE FILES → "50k tokens · noisy · lossy".
> Right panel — *Conversational Interrogation Model*: AGENT → "How do I add feature X?" → LIVING CODEBASE (Interrogation Router · BEAM) → GRAPH PATH + TEMPLATE + "1.5k · precise".

---

## 2. Multi-Tier Knowledge Graph Architecture

A conversational codebase must answer three distinct questions simultaneously: *What calls what?* (structure), *Why was it written?* (history), and *What did the human mean?* (intent). No single index suffices. We therefore embed three specialized engines inside the agent process, federated via BEAM's actor model for <2ms traversal at core-graph scale (≤~2k edges; ~6.6ms at full-repo scale, ~10k edges).

> **Figure 2 — Multi-Tier Knowledge Graph** *(SVG placeholder; "Embedded Intelligence · No External Dependencies")*
>
> - **G — PROPERTY GRAPH** (DuckDB + libgraph): AST Call Graphs · Spec Relationships · DB Schema Mappings — e.g. `TRAVERSE(CALLS) {depth:3}`
> - **T — TEMPORAL MEMORY** (MemGit Lineage): Commit Provenance · Historical Authors · Stripped Comments — e.g. `BLAME(node) → Commit`
> - **V — VECTOR INDEX** (plug-and-play store: DuckDB vss HNSW primary / sqlite-vec fallback): Natural Language Intent · Mapping · Symbol Summaries — e.g. `VECTOR_SEARCH("hash")`
>
> Footer: DuckDB Embedded + libgraph In-Memory · MemGit in BEAM (ETS) · bge-micro-v2 384-dim

### 2.1 Graph Schema Definition

We model the repository as typed edge tables in embedded DuckDB (durable, columnar) with a process-local libgraph projection for traversals. The schema below captures requirements, AST symbols, commits, and their relations, allowing queries like "which spec does this function satisfy?" and "who last modified this symbol's ancestors?".

`schema.sql · DuckDB DDL`:

```sql
CREATE TABLE spec_requirements (id VARCHAR PRIMARY KEY, text VARCHAR);
CREATE TABLE ast_nodes (
  id VARCHAR PRIMARY KEY,
  filepath VARCHAR,
  symbol_name VARCHAR,
  node_type VARCHAR
);
CREATE TABLE commits (
  hash VARCHAR PRIMARY KEY,
  author VARCHAR,
  message VARCHAR,
  timestamp BIGINT
);

-- Typed edge list: all relationships share one durable table
CREATE TABLE graph_edges (
  label VARCHAR,   -- 'SATISFIED_BY' | 'CALLS' | 'MODIFIED_IN'
  src VARCHAR,
  dst VARCHAR,
  count INTEGER
);
```

At repo load, the GraphServer GenServer projects the edge list into an in-process libgraph graph; traversals then run entirely in BEAM memory:

```elixir
# Example traversal: blast radius for signature change
graph = GraphServer.projected()   # libgraph %Graph{} built from graph_edges
impact = reverse_bfs(graph, "hash_password", depth: 3)  # walks Graph.in_neighbors/2
```

Tier summary (as given in the paper):

| Tier | Latency | Description |
|---|---|---|
| **Property Graph** | 3–8ms | Built at repo load via tree-sitter. Durable edge tables in DuckDB, projected into an in-process libgraph graph for traversal. Fully in-process, no server. |
| **Temporal Memory** | 1–2ms | MemGit indexes every commit touching an AST node. Recovers deleted comments by diffing parent commits. Author attribution enables institutional Q&A. |
| **Vector Index** | <10ms | 384-dim bge-micro-v2 embeddings of symbol summaries (not raw code), validated plug-and-play store (DuckDB vss HNSW @10k: 3ms; sqlite-vec fallback: ~9.7ms). Maps "add SHA3" → `hash_password/1` without brittle grep. |

---

## 3. Core Capabilities

### 3.1 Architectural Intent Negotiation

The agent does not propose code; it proposes *intent*. The codebase router evaluates intent against call graphs and organizational style policies (e.g., "crypto utilities must extend, not create modules") and returns a negotiated plan with pre-approved scaffolding.

**Agent Request · JSON-RPC:**

```json
{
  "jsonrpc": "2.0",
  "method": "codebase.ask",
  "params": {
    "intent": "Add SHA3-256 hashing for Spec #42",
    "alternatives": [
      "Plan A: create lib/crypto/sha3.ex",
      "Plan B: extend hash_password/1 in lib/crypto.ex"
    ],
    "spec_id": "SPEC-42"
  },
  "id": 1
}
```

**Codebase Interrogation Response:**

```json
{
  "decision": "Use Plan B",
  "reason": "Style Policy CRYPTO-01: Extend existing module. Plan A violates SRP.",
  "graph_path": [
    "lib/crypto.ex::hash_password/1",
    "  <- lib/auth.ex:42",
    "  <- lib/user.ex:118"
  ],
  "blast_radius": ["fileX:123", "fileZ:223"],
  "template": "def hash_password(pwd, :sha3) do\n  :crypto.hash(:sha3_256, pwd)\nend",
  "tokens": 1520
}
```

> **Figure 3 — Architectural Intent Negotiation Flow** *(SVG placeholder)*
>
> PRIMARY AGENT ("Add SHA3 for Spec #42" · "Plan A vs Plan B?") → INTERROGATION ROUTER (BEAM) — traverses call graph & style policies → ✓ APPROVED RESPONSE: "Use Plan B" · Extend `hash_password/1` · ⚠ modifying signature affects fileX:123, fileZ:223 · Pre-approved template: `def hash_pwd(pwd) do :crypto.hash(...) end` · 1.5k tokens.
>
> STYLE POLICY EVALUATION:
> - Plan A: New Module — creates sha3.ex (new file) — ✗ Violates: Single Responsibility in crypto/*
> - Plan B: Extend Existing ✓ — extends hash_password/1 — ✓ Aligns: crypto policy — Call graph: 2 files impacted
>
> CALL GRAPH TRAVERSAL: `hash_password/1 ← auth.ex:42, user.ex:118 → fileX:123 fileZ:223`

### 3.2 Temporal & Institutional Memory

Most regressions occur because agents violate Chesterton's Fence—removing constraints whose purpose was lost when comments were stripped. Our Historical Reasoner recovers institutional memory by traversing ASTNode → Commit → Diff Ancestry, restoring deleted rationales as first-class evidence.

> **Figure 4 — Temporal & Institutional Memory** *(SVG placeholder; "Historical Reflection")*
>
> QUERY: "Why is txn_status hardcoded to 1 in insert_tx()?"
>
> HISTORICAL REASONER ENGINE — 3-stage lineage recovery:
> 1. **AST NODE LOOKUP** — `src/db/txn.ex::insert_tx` — DuckDB: `SELECT * FROM ast_nodes WHERE id = ...`
> 2. **GIT BLAME QUERY** — Commit 2612f859 · Author: Intern — MODIFIED_IN edge traversal
> 3. **DIFF ANCESTRY** — Parent: 8a4f0012 (Joe) — Deleted: `// Txn status on insert = 1 (pending)`
>
> ✓ RESOLVED · INSTITUTIONAL MEMORY: "Joe hardcoded `status=1` for pending. Comment stripped in `2612f859` (Intern cleanup). Refer to `TxnStatus` enum for canonical mapping." — *Preserves Chesterton's Fence: Do not refactor without historical intent.*
>
> Sidebar — CHESTERTON'S FENCE PRINCIPLE: "Don't remove fence until you know why it was built." → Prevents historical regressions.

**Key Insight:** The intern's commit `2612f859` was a lint cleanup that stripped a critical business rule comment. Traditional grep sees only `status=1`. Our lineage query restores the deleted comment from parent `8a4f0012` and links it to the `TxnStatus` enum, preventing an agent from "fixing" the hardcode into a configurable value that would break pending transaction semantics.

---

## 4. Empirical Evaluation & System Impact

We evaluated on 120 architectural tasks across Elixir, Python, and TypeScript repositories (5k–250k LOC) on a Poco F5 Pro 12GB Lab device with no external vector DB. Baseline: traditional inspection via ripgrep + OpenAI embeddings + full-file injection (standard SWE-Agent pattern).

> **Figure — Token Consumption** *(SVG placeholder)*: Traditional 85k tokens vs Conversational 3.2k tokens → **-96.2%** (tokens per architectural task).
>
> **Figure — First-Turn Code Completion Rate** *(SVG placeholder)*: Traditional 32% vs Conversational 92% → **2.8×** (successful first-turn completions).

**Performance Comparison · n=120 Tasks:**

| Performance Metric | Traditional Inspection (Grep / Vector RAG) | Conversational Codebase Protocol |
|---|---|---|
| Context Query Latency | 3,000–15,000 ms | **<2 ms** (in-process, core graphs ≤~2k edges); ~6.6 ms measured worst-case full-repo (~10k edges) |
| Token Overhead | 50k–120k | **1.5k–4k** · 96.2% ↓ |
| First-Turn Completion | 32% | **92%** · 2.8× ↑ |
| Historical Regression Rate | 18.4% | **<0.5%** · Chesterton guard |

Notes: All measurements on-device, Poco F5 Pro (Snapdragon 8+ Gen 1, 12GB). No network calls during task execution. DuckDB embedded, libgraph in-memory, plug-and-play vector store (DuckDB vss HNSW / sqlite-vec), MemGit in BEAM (ETS). Latency scoping per AST-measured benchmark (2026-09-11): BFS <2ms at ≤~2k edges, ~6.6ms p50 at ~10k edges (361k-LOC polyglot Go codebase).

**System Impact Summary:** The conversational protocol collapses retrieval from "find files" to "decide architecture." By moving policy enforcement and historical reasoning into the codebase itself, we eliminate prompt stuffing and enable agents to generate correct code on the first turn without exploratory grep loops. The 96.2% token reduction is not compression—it is the removal of irrelevant data that should never have entered the context.

---

## 5. Conclusion

Codebases have always contained more knowledge than their text: call graphs, style policies, commit histories, and stripped rationales. Traditional agents ignore this latent structure and pay with tokens, accuracy, and regressions. Conversational Codebases make that structure queryable.

Our three-tier graph—Property Graph (DuckDB + libgraph), Temporal Memory (MemGit), Vector Intent (validated plug-and-play store)—transforms the repository from a file store into a negotiating peer. It does not dump files; it answers "how should this be built?" with blast-radius analysis, policy-compliant templates, and historical justification. On a constrained 12GB device, this yields <2ms queries at core-graph scale (~6.6ms worst-case full-repo), 96.2% token savings, and near-zero historical regressions.

**Future Work:** Paper 3 will explore collaborative interrogation where multiple agents negotiate over the same codebase graph, requiring conflict resolution and distributed style policy consensus via CRDTs. We will also open-source the BEAM router and the DuckDB–libgraph projection layer.

---

## References

1. DuckDB — In-Process SQL OLAP Database. duckdb.org (Elixir NIF: duckdbex)
2. libgraph — In-Memory Property Graph Data Structure for Elixir. hex.pm/packages/libgraph
3. Chesterton, G.K. — *The Thing: Why I Am Catholic* (1929). Fence Principle.
4. Yang et al. — SWE-Agent: Agent-Computer Interfaces (2024).
5. MemGit — Commit Provenance as Graph (Kilas Project, 2024).

---

*Source footer: "Kilas Project · Conversational Codebases · Paper 2 of 3 · © 2024 Mohd Norhaimi Bin Yahya" · "Built on Poco F5 Pro 12GB Lab · No external dependencies"*

*Known gaps to revisit (flagged at extraction, not yet fixed): figure diagrams (placeholders only); verification of references/benchmarks; series-position conflict ("Paper 2 of 3" here vs "Paper 1 of 4" in Paper 1 and the stated 4-paper plan); latency inconsistency (resolved 2026-09-11 by scoping <2ms claims to core-graph scale ≤~2k edges; the 3–8ms Property Graph tier row brackets the measured 0.6–6.6ms range); Commit table DDL bug in the source (declared `hash`, keyed on `id`) fixed in the DuckDB rewrite above; template name differs between the JSON-RPC response (`hash_password(pwd, :sha3)`) and Figure 3 (`hash_pwd(pwd)`); Paper 1 named Paper 2 topics as "InterrogationRouter strategies, knowledge graph distillation, long-horizon planning" — this paper covers intent negotiation but not knowledge-graph distillation or long-horizon planning. Vector tier reconciled 2026-09-12 to the validated stack (`.tools/validate/RESULTS.md` rows 10-12): "In-Memory HNSW / 128-dim MiniLM" rewritten to bge-micro-v2 384-dim + plug-and-play store (DuckDB vss HNSW primary, sqlite-vec fallback); "libgit2 via Rust NIF" rewritten to MemGit in BEAM (ETS). Note: the Future-Work CRDT collaboration promise here is not delivered by Paper 3 (which covers survival engineering) — the collaborative-interrogation topic remains open.*
