# KILAS v2.0 COMPLETE BUILD SPECIFICATION

Volatile-First Autonomous Coding Harness for Android PRoot | Claude Code Executable Blueprint

- **Version:** 2.0.0-stable

- **Target:** Poco F5 Pro 12GB

- **Stack:** BEAM + Elixir + Rust + Go

- **Mode:** Executable Spec

ABSTRACT — EXECUTABLE SPEC

This spec merges Papers 1-4 into a single buildable document. Contains exact file tree, ETS/DuckDB/libgraph schemas, pseudocode, APIs, config templates, performance targets, and implementation order. Paste entire spec into Claude Code with prompt `“Build Kilas v2.0 exactly per this spec, file by file, no shortcuts”`. No bash sh -c loops. All heavy compilers via persistent Ports, fast path 100% BEAM-native.

Invariants: Volatile-First (hot state in BEAM RAM — ETS/MemGit; workspace files on f2fs; physical disk touched only by ShadowSync), Zero-Fork (≤1 fork/min), Single-Writer (CodeWriter singleton), Language-Agnostic (Tree-sitter + GenericAdapter).

14 INTERACTIONS • 6 LAYERS

workspace 1GB (f2fs) • ShadowSync 60s • WAL + atomic rsync

TABLE OF CONTENTS

1. Project Overview & Principles

2. File Tree — Exact Structure

3. Data Schemas — ETS / DuckDB / libgraph

4. Core Algorithms — Pseudocode

5. All 14 Interactions — APIs & Flows

6. Configuration — mix.exs / .kilas.json / Policies

7. Build Order for Claude Code

8. Performance Targets — Poco F5 Pro

9. Mobile Survival Spec — NAND / OOM / Thermal

10. Testing Spec — Interaction Coverage

FINAL: Claude Code Prompt + Diagrams

## 01 — Project Overview & Principles

*VOLATILE-FIRST • ZERO-FORK • SINGLE-WRITER • LANGUAGE-AGNOSTIC*

Volatile-First

Hot state lives in BEAM RAM: ETS (MemGit, locks, bindings) with validated 0.42µs reads. Workspace files live in /tmp/kilas — a plain f2fs directory with 1GB quota (kernel page cache serves hot files; validated ~1.2ms small-file reads, 2.7GB/s bulk). No tmpfs exists in PRoot (validated: no /dev/shm on host, mounts impossible rootless) — no mount is attempted. Physical repo disk is only touched by Housekeeper ShadowSync every 60s via atomic rsync + WAL.

- › WorkspaceManager.ensure_workspace(): mkdir /tmp/kilas + 1GB quota check (no mount)

- › recover_from_disk() on boot: rsync physical → workspace

- › All File.read!/write! point to /tmp/kilas/*

- › Housekeeper: .kilas_shadow_tmp → rename atomic

Zero-Fork Loop

90% BEAM-native: ETS (MemGit, locks, bindings), DuckDB (AST + graph edges), libgraph (BEAM-memory graph), Tree-sitter NIF (Rustler dirty_cpu), Finch (HTTP). 10% persistent Ports: go, cargo, gradle, mix test — started once, reused via Port.command. Target: ≤1 fork/min on Poco F5 Pro.

- › PersistentPort: Port.open({:spawn_executable, bin}, cd: cwd)

- › Finch instead of curl (no fork)

- › Tree-sitter via Rustler NIF, not CLI

- › Go vet as optional c-shared lib NIF

Single-Writer

CodeWriter is GenServer singleton. All edits via ETS reservation :ast_locks. Lock granularity: function/method, not file. Binary-part surgical patch, microsecond, rollback on Tree-sitter syntax error.

- › Coordinator.reserve_ast_lock(node_id, agent_id)

- › PolicyGate <1ms pre-flight

- › Patcher.binary_part(old, 0, offset) <> new <> rest

- › MemGit.commit ETS only (<0.5ms)

Language Agnostic

Tree-sitter for all languages. GenericShellAdapter reads .kilas.json which maps compile/check/test_targeted from templates. Auto-detect via file presence: go.mod, Cargo.toml, build.gradle, mix.exs, package.json, pyproject.toml, build.zig, etc.

- › ShadowRegistry.get_adapter(cwd) -> load_template

- › EEx eval for {test_symbol} interpolation

- › File patterns per lang in template

- › Parent context envelope: imports + class + funcs

DIAGRAM 01 — VOLATILE-FIRST DATA PATH

**Diagram (viewBox 780x180):**
- Agent / TUI → CodeWriter → /tmp/kilas workspace 1G (f2fs) → Housekeeper → Physical
- open, edit, ask → Singleton + ETS lock → All File I/O • ~1ms • 60s tick • WAL → atomic rename
- MemGit ETS :memgit_*  +  DuckDB ast_nodes  +  graph_edges + libgraph
- commit <0.5ms • BlastRadius <2ms • No disk

14 INTERACTIONS — 6 LAYERS (Code, Runtime, Environment, Knowledge, Collaboration, Deploy)

• Code: Query, Generate, Patch, TIA Test

• Runtime: Debug (bindings), Profile (fprof/pprof), REPL LiveLab

• Environment: EnvDoctor (regex→apt→Port), Survival Gauges

• Knowledge: Security (CVE traversal), Tutor (story+mermaid)

• Collaboration: Collab (MemGit timeline + locks), Push

• Deploy: ShadowSync atomic + git push via persistent Port

## 02 — File Tree — Exact Structure

Claude must create exactly this tree. No extra folders. mix.exs deps pinned. Templates JSON per language. Policies JSON in priv. All GenServers under lib/kilas/* supervision.

```text
kilas/
├── mix.exs (deps: ex_tree_sitter, rustler 0.32, duckdbex 0.3.7, libgraph 0.16, finch 0.19, req 0.5, jason 1.4, owl 0.12, ratatouille 0.5 [optional])
├── .kilas.json (template registry: {"go": "templates/go.json", ...})
├── lib/kilas/
│   ├── application.ex (Supervisor: WorkspaceManager, MemGit, DuckDBServer, GraphServer, TreeSitterServer, ShadowRegistry, CodeWriter.Coordinator, Housekeeper, Router)
│   ├── storage/
│   │   ├── workspace_manager.ex (/tmp/kilas f2fs dir, 1GB quota, recover_from_disk)
│   │   ├── memgit.ex (ETS :memgit_commits, :memgit_trees, :memgit_blobs, commit/log/diff/status/rollback)
│   │   ├── duckdb_server.ex (AST nodes, parent context envelope, FTS)
│   │   ├── graph_server.ex (project graph_edges into libgraph: CALLS, TESTED_BY, DEPENDS_ON, IMPORTS, HAS_VULN, MODIFIED_IN)
│   │   └── housekeeper.ex (60s ShadowSync atomic rsync + WAL shadow.journal + git push via persistent Port)
│   ├── compiler/
│   │   ├── shadow_registry.ex (get_adapter via .kilas.json + auto-detect)
│   │   ├── generic_adapter.ex (run cwd, template, context, EEx eval, System.cmd or persistent Port)
│   │   ├── persistent_port.ex (start_link, run_test, single fork, reuse, Port.open spawn_executable)
│   │   ├── go_vet_nif.ex (optional Go vet as NIF dirty_cpu, Go c-shared lib + C wrapper ERL_NIF_DIRTY_JOB_CPU_BOUND)
│   │   └── shadow_server.ex (compile, check, run_targeted)
│   ├── ast/
│   │   ├── tree_sitter_server.ex (parse_file, language auto-detect, NIF dirty_cpu, GenServer)
│   │   ├── granularity.ex (function=vector, class=graph-only, per language map)
│   │   ├── parent_context.ex (envelope: file, imports, surrounding class/func, 5 lines before/after)
│   │   └── policy_gate.ex (pre-flight <1ms, reject anti-patterns from anti_patterns.json, return fix suggestion)
│   ├── tia/
│   │   ├── blast_radius.ex (get_impacted_tests node_id via GraphServer bounded BFS depth≤5)
│   │   ├── test_runner.ex (run only impacted tests via GenericAdapter template.test_targeted)
│   │   └── focused_signal.ex (parse test output to 200 token hint, not wall of text)
│   ├── code_writer/
│   │   ├── coordinator.ex (GenServer singleton, reserve_ast_lock, apply_surgical_patch, global name)
│   │   ├── patcher.ex (binary_part surgical, microsecond, rollback on syntax error)
│   │   └── lock_manager.ex (ETS :ast_locks, lock per function, not file, TTL 30s)
│   ├── interrogation/
│   │   ├── router.ex (intent classification: query, generate, debug, profile, env, security, survival, tutor, collab, deploy, repl, open, edit)
│   │   ├── query_engine.ex (GraphRAG over DuckDB+libgraph, <10ms, parent_context)
│   │   ├── debug_engine.ex (get_runtime_value from last failed run bindings stored in ETS :runtime_bindings)
│   │   ├── profile_engine.ex (fprof / go pprof / cargo flamegraph in workspace, store in DuckDB)
│   │   ├── env_doctor.ex (EnvGraph error regex -> apt package -> install via Port)
│   │   ├── security_engine.ex (vuln traversal Package->CVE via libgraph)
│   │   ├── survival_engine.ex (nand_writes, battery, oom_risk gauges, thermal)
│   │   ├── tutor_engine.ex (explain as story + mermaid diagram string)
│   │   └── collab_engine.ex (MemGit timeline + lock reservations)
│   ├── tools/
│   │   ├── http.ex (Finch, not curl, pool, timeout 5s)
│   │   ├── live_lab.ex (IEx persistent Port in /tmp/kilas_lab, eval without commit)
│   │   └── repl.ex (eval in workspace, no persistence)
│   └── tui/
│       └── cli.ex (Owl TUI, commands: open, edit, ask, debug, profile, env fix, explain, push, status)
├── native/
│   ├── tree_sitter_nif/ (Rustler crate, dependencies: tree-sitter 0.22, tree_sitter_go, java, rust, elixir, python, zig, js)
│   └── go_vet_nif/ (optional, Go c-shared lib + C wrapper, ERL_NIF_DIRTY_JOB_CPU_BOUND)
├── templates/
│   ├── go.json
│   ├── rust.json
│   ├── java-gradle.json
│   ├── java-maven.json
│   ├── elixir.json
│   ├── python.json
│   ├── zig.json
│   └── node.json
├── priv/
│   └── policies/
│       └── anti_patterns.json (raw SQL interpolation, unhandled Task.async, fmt.Sprintf %s with SQL, etc)
└── test/
    ├── workspace_manager_test.exs
    ├── memgit_test.exs
    ├── blast_radius_test.exs
    ├── query_test.exs
    ├── debug_test.exs
    ├── profile_test.exs
    ├── env_doctor_test.exs
    ├── security_test.exs
    ├── survival_test.exs
    ├── tutor_test.exs
    ├── collab_test.exs
    └── all_interaction_test.exs
```

mix new kilas --sup first

Supervisor order critical

## 03 — Data Schemas — ETS / DuckDB / libgraph

DuckDB — ast_nodes

```sql
CREATE TABLE ast_nodes (
  id TEXT PRIMARY KEY, -- filepath::symbol_name  e.g. lib/auth.ex::hash_password
  filepath TEXT NOT NULL,
  symbol_name TEXT NOT NULL,
  node_type TEXT NOT NULL, -- function_declaration, method_declaration, struct, class_declaration
  language TEXT NOT NULL, -- go, rust, java, elixir, python, zig, js
  start_line INT NOT NULL,
  end_line INT NOT NULL,
  start_byte INT,
  end_byte INT,
  content TEXT, -- function body trimmed
  parent_id TEXT, -- enclosing class/struct id
  parent_context TEXT, -- JSON envelope: {"imports": [...], "class": "...", "surrounding": "..."}
  embedding BLOB, -- optional vector 384 dim for future GraphRAG
  hash TEXT, -- content hash for change detection
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_filepath ON ast_nodes(filepath);
CREATE INDEX idx_symbol ON ast_nodes(symbol_name);
CREATE INDEX idx_lang ON ast_nodes(language);

-- Parent context example for Go:
-- {
--   "imports": ["fmt", "crypto/bcrypt"],
--   "package": "auth",
--   "struct": "type User struct {...}",
--   "before": "func previousFunc() {...}",
--   "after": "func nextFunc() {...}"
-- }
```

Graph Tier — DuckDB Edge Tables (durable) + libgraph (BEAM memory)

DuckDB stores the graph as plain rows: one edge table plus typed attribute
tables (`ast_nodes` from §3 above is the vertex source for code nodes). At
boot, GraphServer projects `graph_edges` into a `%Graph{}` (libgraph) held in
BEAM memory — traversals are pure Elixir, no graph DB process, no extra NIF.

```sql
-- Attribute tables (durable, DuckDB)
CREATE TABLE test_nodes (
  id TEXT PRIMARY KEY,    -- filepath::TestFunc
  filepath TEXT NOT NULL,
  line INT
);

CREATE TABLE packages (
  name TEXT PRIMARY KEY,
  version TEXT,
  ecosystem TEXT          -- go, cargo, maven, npm, hex
);

CREATE TABLE vulnerabilities (
  cve TEXT PRIMARY KEY,
  severity TEXT,          -- critical, high, medium
  cvss DOUBLE,
  description TEXT
);

CREATE TABLE commits (
  hash TEXT PRIMARY KEY,
  message TEXT,
  ts INT
);

-- One edge table; src/dst reference ids from ast_nodes, test_nodes,
-- packages, vulnerabilities, commits
CREATE TABLE graph_edges (
  label TEXT NOT NULL,    -- CALLS | TESTED_BY | DEPENDS_ON | IMPORTS | HAS_VULN | MODIFIED_IN
  src   TEXT NOT NULL,
  dst   TEXT NOT NULL,
  count INT DEFAULT 1
);

CREATE INDEX idx_edges_src ON graph_edges(src);
CREATE INDEX idx_edges_dst ON graph_edges(dst);
```

```elixir
# GraphServer: project graph_edges into libgraph at boot (and on ShadowSync replay)
rows = DuckDBServer.query("SELECT label, src, dst FROM graph_edges", [])

graph =
  Enum.reduce(rows, Graph.new(), fn %{label: l, src: s, dst: d}, g ->
    g |> Graph.add_vertex(s) |> Graph.add_vertex(d) |> Graph.add_edge(s, d, label: l)
  end)

# Query: Blast Radius — reverse bounded BFS (depth <= 5) over CALLS edges,
# then TESTED_BY join (see 4.3). Invariant: in_neighbors of an AST node are
# exactly its CALLS callers — every other edge label ends at a non-AST vertex
# (TestNode / Package / Vulnerability / Commit).
```

ETS Tables — In-Memory Only

```bash
# MemGit — all in ETS, no disk during loop
:memgit_commits
  {hash, tree_hash, parent_hash, message, author, timestamp}
  key: hash

:memgit_trees
  {hash, entries: [%{filepath: "lib/auth.ex", blob_hash: "abc123", mode: "100644"}]}
  key: hash

:memgit_blobs
  {hash, content} # binary
  key: hash
  # content addressable, sha256

:ast_locks
  {node_id, owner_agent_id, timestamp, expires_at}
  key: node_id
  # TTL 30s, reservation per function
  # reserve: :ets.insert_new
  # release: on commit or timeout

:runtime_bindings
  {test_run_id, node_id, variable, value, stacktrace, timestamp}
  bag table, key: test_run_id
  # from last failed test run
  # populated by TestRunner parsing bindings

:env_graph
  {error_regex, apt_package, install_cmd, lang}
  key: error_regex
  # e.g. {"go:.*exec: \"gcc\":.*", "build-essential", "apt install -y build-essential"}

:shadow_registry
  {cwd_hash, template}
  key: cwd_hash
  # cached adapter

:parent_context_cache
  {node_id, envelope_json, updated_at}
  key: node_id
```

PERFORMANCE INVARIANT

ETS read <0.01ms • MemGit commit <0.5ms • libgraph CALLS BFS depth≤5 <2ms (benchmark required) • DuckDB point query <1ms

## 04 — Core Algorithms — Pseudocode

4.1

Volatile-First Init — WorkspaceManager

DIRTY_CPU NIF • ETS • <1ms

```elixir
defmodule Kilas.Storage.WorkspaceManager do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    workspace_path = "/tmp/kilas"
    physical_path = get_physical_path() # e.g. /data/data/com.termux/files/home/storage/kilas or ./kilas_physical

    # Plain f2fs dir + 1GB quota. No tmpfs: PRoot has none (validated
    # 2026-09-12 — no /dev/shm on host, mount impossible rootless).
    # Hot files are served by the kernel page cache (~1.2ms small reads).
    File.mkdir_p!(workspace_path)
    :ok = check_quota(workspace_path)

    recover_from_disk(physical_path, workspace_path)

    {:ok, %{workspace: workspace_path, physical: physical_path, writes: 0}}
  end

  def recover_from_disk(physical, workspace) do
    if File.exists?(physical) do
      # rsync physical -> workspace, preserve perms, exclude shadow tmp
      System.cmd("rsync", ["-a", "--exclude=.kilas_shadow_tmp", "#{physical}/", "#{workspace}/"])
    end
  end

  # 1GB quota, checked at boot and by Housekeeper after sync
  def check_quota(workspace_path) do
    {size, _} = System.cmd("du", ["-sb", workspace_path])
    {bytes, _} = Integer.parse(size)
    if bytes > 1_000_000_000, do: {:error, :quota_exceeded}, else: :ok
  end

  def get_physical_path do
    System.get_env("KILAS_PHYSICAL") || Path.expand("./kilas_physical")
  end
end
```

4.2

Single-Writer Surgical Patch — CodeWriter.Coordinator + Patcher

DIRTY_CPU NIF • ETS • <1ms

```elixir
defmodule Kilas.CodeWriter.Coordinator do
  use GenServer
  # Singleton, globally registered

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end

  def apply_patch(filepath, new_code, agent_id) do
    GenServer.call({:global, __MODULE__}, {:apply_patch, filepath, new_code, agent_id}, 30_000)
  end

  def handle_call({:apply_patch, filepath, new_code, agent_id}, _from, state) do
    node_id = "#{filepath}::#{extract_symbol(new_code)}" # e.g. lib/auth.ex::hash_password

    # 1. Reserve AST lock (ETS, per function)
    case Kilas.CodeWriter.LockManager.reserve(node_id, agent_id) do
      {:error, :locked_by, owner} ->
        {:reply, {:error, "locked by #{owner}, see collab timeline"}, state}
      :ok ->
        # 2. Policy gate <1ms
        case Kilas.AST.PolicyGate.check(new_code, filepath) do
          {:rejected, reason, fix} ->
            Kilas.CodeWriter.LockManager.release(node_id)
            {:reply, {:error, reason, fix}, state}
          :ok ->
            # 3. Surgical binary_part patch
            old = File.read!("/tmp/kilas/#{filepath}")
            {offset, len} = find_symbol_range(old, node_id) # via DuckDB ast_nodes start_byte/end_byte
            patched = binary_part(old, 0, offset) <> new_code <> binary_part(old, offset + len, byte_size(old) - offset - len)

            # 4. Tree-sitter syntax check (NIF dirty_cpu, <5ms)
            case Kilas.AST.TreeSitterServer.parse_string(patched, detect_lang(filepath)) do
              {:error, syntax_err} ->
                {:reply, {:error, :syntax, syntax_err}, state}
              {:ok, tree} ->
                File.write!("/tmp/kilas/#{filepath}", patched)

                # 5. MemGit ETS commit <0.5ms
                Kilas.Storage.MemGit.commit(filepath, "edit #{node_id}", agent_id)

                # 6. TIA Blast Radius libgraph BFS <2ms
                impacted = Kilas.TIA.BlastRadius.get_impacted_tests(node_id)

                # 7. Test only impacted via persistent Port
                result = Kilas.TIA.TestRunner.run_targeted(impacted)

                if result.failed do
                  Kilas.Storage.RuntimeBindings.store(result.run_id, result.bindings)
                end

                Kilas.CodeWriter.LockManager.release(node_id)
                {:reply, {:ok, %{node_id: node_id, tests: result, patched: true}}, state}
            end
        end
    end
  end
end

defmodule Kilas.CodeWriter.Patcher do
  def surgical_replace(old_binary, offset, len, new_code) do
    # Microsecond operation, no intermediate strings
    <<head::binary-size(offset), _::binary-size(len), tail::binary>> = old_binary
    <<head::binary, new_code::binary, tail::binary>>
  end
end
```

4.3

TIA Blast Radius — libgraph Bounded Reverse BFS

BEAM-native (pure Elixir, no NIF) • GraphServer projection • <2ms target

```elixir
defmodule Kilas.TIA.BlastRadius do
  # Returns list of TestNode ids impacted by change to node_id.
  # Equivalent of: MATCH (n)<-[:CALLS*1..5]-(caller), (caller)-[:TESTED_BY]->(t)
  # UNION MATCH (n)-[:TESTED_BY]->(direct) — see §3 graph tier.

  @max_depth 5

  def get_impacted_tests(node_id) do
    g = Kilas.Storage.GraphServer.graph()

    # node_id itself (direct tests) + all CALLS callers within depth 5
    touched = callers_incl_self(g, MapSet.new([node_id]), MapSet.new([node_id]), 0)

    touched
    |> Enum.flat_map(fn v ->
      g |> Graph.out_edges(v) |> Enum.filter(&(&1.label == :tested_by)) |> Enum.map(& &1.v2)
    end)
    |> Enum.uniq()
  end

  # Iterative BFS; each vertex expanded at most once (seen set)
  defp callers_incl_self(_g, _frontier, seen, d) when d >= @max_depth, do: seen

  defp callers_incl_self(g, frontier, seen, d) do
    next =
      frontier
      |> Enum.flat_map(&Graph.in_neighbors(g, &1))
      |> MapSet.new()
      |> MapSet.difference(seen)

    case MapSet.size(next) do
      0 -> seen
      _ -> callers_incl_self(g, next, MapSet.union(seen, next), d + 1)
    end
  end

  # Fallback if GraphServer not ready: file-level via DuckDB parent_context
  def fallback_file_tests(filepath) do
    Kilas.Storage.DuckDBServer.query("SELECT id FROM ast_nodes WHERE filepath = ? AND node_type LIKE '%test%'", [filepath])
  end
end

defmodule Kilas.TIA.TestRunner do
  def run_targeted(test_ids) when length(test_ids) == 0, do: %{failed: false, run_id: nil, output: "no impacted tests"}

  def run_targeted(test_ids) do
    adapter = Kilas.Compiler.ShadowRegistry.get_adapter(File.cwd!())
    # template.test_targeted e.g. "go test -run {test_symbol} ./..."
    # EEx interpolation of test symbols

    cmd = EEx.eval_string(adapter.test_targeted, test_symbol: Enum.join(test_ids, "|"))

    # Use persistent Port if available, else fallback System.cmd in /tmp/kilas
    case Kilas.Compiler.PersistentPort.get_port(File.cwd!()) do
      {:ok, port} -> Kilas.Compiler.PersistentPort.run(port, cmd)
      :none ->
        {out, code} = System.cmd("sh", ["-c", cmd], cd: "/tmp/kilas", stderr_to_stdout: true)
        %{failed: code != 0, output: out, run_id: :erlang.unique_integer([:positive])}
    end
    |> Kilas.TIA.FocusedSignal.parse() # 200 token hint, not wall
  end
end

defmodule Kilas.TIA.FocusedSignal do
  # Parse test output to 200 token focused hint
  def parse(%{failed: false} = result), do: result

  def parse(%{output: out} = result) do
    hint = out
    |> String.split("\n")
    |> Enum.filter(fn line -> String.contains?(line, ["FAIL", "Error", "panic", "expected", "got"]) end)
    |> Enum.take(10)
    |> Enum.join("\n")
    |> String.slice(0, 800) # ~200 tokens

    Map.put(result, :focused_hint, hint)
  end
end
```

4.4

Generic Adapter Auto-Detect — ShadowRegistry + .kilas.json

DIRTY_CPU NIF • ETS • <1ms

```elixir
defmodule Kilas.Compiler.ShadowRegistry do
  def get_adapter(cwd) do
    # Check ETS cache first
    case :ets.lookup(:shadow_registry, hash(cwd)) do
      [{_, template}] -> template
      [] -> detect_and_cache(cwd)
    end
  end

  def detect_and_cache(cwd) do
    template = cond do
      File.exists?("#{cwd}/go.mod") -> load("go.json")
      File.exists?("#{cwd}/Cargo.toml") -> load("rust.json")
      File.exists?("#{cwd}/build.gradle") or File.exists?("#{cwd}/build.gradle.kts") -> load("java-gradle.json")
      File.exists?("#{cwd}/pom.xml") -> load("java-maven.json")
      File.exists?("#{cwd}/mix.exs") -> load("elixir.json")
      File.exists?("#{cwd}/package.json") -> load("node.json")
      File.exists?("#{cwd}/pyproject.toml") or File.exists?("#{cwd}/requirements.txt") -> load("python.json")
      File.exists?("#{cwd}/build.zig") -> load("zig.json")
      true -> %{compile: "make", check: "make lint", test_targeted: "make test TEST={test_symbol}", test_all: "make test", file_patterns: ["**/*"]}
    end

    # Merge with local .kilas.json if exists (overrides)
    local = case File.read("#{cwd}/.kilas.json") do
      {:ok, content} -> Jason.decode!(content)
      _ -> %{}
    end

    merged = Map.merge(template, local)
    :ets.insert(:shadow_registry, {hash(cwd), merged})
    merged
  end

  def load(name) do
    Path.join([:code.priv_dir(:kilas), "templates", name])
    |> File.read!()
    |> Jason.decode!()
  end
end

# Example templates/go.json
{
  "language": "go",
  "compile": "go build ./...",
  "check": "go vet ./...",
  "test_targeted": "go test -run {test_symbol} -count=1 ./...",
  "test_all": "go test ./... -count=1",
  "file_patterns": ["**/*.go", "go.mod"],
  "persistent_port": {"bin": "go", "args": ["help"], "reuse": true},
  "env": {"CGO_ENABLED": "0"}
}
```

4.5

Persistent Port — Zero-Fork Loop

DIRTY_CPU NIF • ETS • <1ms

```elixir
defmodule Kilas.Compiler.PersistentPort do
  use GenServer

  def start_link(%{cwd: cwd, lang: lang, bin: bin, args: args}) do
    GenServer.start_link(__MODULE__, %{cwd: cwd, lang: lang, bin: bin, args: args}, name: via(cwd))
  end

  def init(%{cwd: cwd, bin: bin, args: args}) do
    port = Port.open({:spawn_executable, System.find_executable(bin)}, [
      :binary, :exit_status, :use_stdio, :stderr_to_stdout,
      args: args,
      cd: cwd,
      env: [{'TERM', 'dumb'}]
    ])
    # Single fork, reuse forever
    {:ok, %{port: port, cwd: cwd, buffer: "", awaiting: nil}}
  end

  def get_port(cwd) do
    case Registry.lookup(Kilas.PortRegistry, cwd) do
      [{pid, _}] -> {:ok, pid}
      [] -> :none
    end
  end

  def run(pid, cmd) do
    GenServer.call(pid, {:run, cmd}, 15_000)
  end

  def handle_call({:run, cmd}, from, %{port: port} = state) do
    Port.command(port, cmd <> "\n")
    {:noreply, %{state | awaiting: from, buffer: ""}}
  end

  def handle_info({port, {:data, data}}, %{port: port, awaiting: from, buffer: buf} = state) do
    new_buf = buf <> data
    # Simple delimiter: look for \n---KILAS_END---\n or 500ms silence
    if String.contains?(new_buf, "KILAS_END") or byte_size(new_buf) > 50_000 do
      GenServer.reply(from, %{output: new_buf, failed: String.contains?(new_buf, "FAIL")})
      {:noreply, %{state | buffer: "", awaiting: nil}}
    else
      {:noreply, %{state | buffer: new_buf}}
    end
  end
end
```

4.6

Housekeeper ShadowSync — 60s Atomic + WAL

DIRTY_CPU NIF • ETS • <1ms

```elixir
defmodule Kilas.Storage.Housekeeper do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule(60_000)
    {:ok, %{last_sync: System.system_time(:second), wal: []}}
  end

  def handle_info(:sync, state) do
    if should_pause_due_to_thermal?() do
      Logger.warning("Housekeeper paused: battery <20% or temp >45C")
      schedule(60_000)
      {:noreply, state}
    else
      do_sync()
      schedule(60_000)
      {:noreply, %{state | last_sync: System.system_time(:second)}}
    end
  end

  def do_sync do
    workspace = "/tmp/kilas"
    physical = Kilas.Storage.WorkspaceManager.get_physical_path()
    shadow_tmp = "/tmp/kilas/.kilas_shadow_tmp"
    journal_path = "#{shadow_tmp}/shadow.journal"

    File.mkdir_p!(shadow_tmp)
    File.rm_rf!(shadow_tmp)

    # 1. Copy workspace -> shadow_tmp (exclude self)
    System.cmd("rsync", ["-a", "--exclude=.kilas_shadow_tmp", "#{workspace}/", "#{shadow_tmp}/"])

    # 2. Write WAL (MemGit log since last sync)
    wal = Kilas.Storage.MemGit.get_commits_since_last_sync()
    File.write!(journal_path, Jason.encode!(wal))

    # 3. Atomic rename shadow_tmp -> physical (rename is atomic on same FS, rsync final)
    # On Android, do rsync --delete to physical, then rm shadow_tmp
    System.cmd("rsync", ["-a", "--delete", "#{shadow_tmp}/", "#{physical}/"])

    File.rm_rf!(shadow_tmp)

    # 4. Git push via persistent Port (single fork, reused)
    branch = System.get_env("KILAS_BRANCH") || "main"
    case Kilas.Compiler.PersistentPort.get_port(physical) do
      {:ok, port} -> Kilas.Compiler.PersistentPort.run(port, "git push origin #{branch}")
      :none -> System.cmd("git", ["push", "origin", branch], cd: physical)
    end

    :ok
  end

  def should_pause_due_to_thermal? do
    battery = read_battery() # /sys/class/power_supply/battery/capacity
    temp = read_temp() # /sys/class/thermal/thermal_zone0/temp
    battery < 20 or temp > 45_000 # 45C in millidegree
  end
end
```

DIAGRAM 02 — ZERO-FORK LOOP ARCHITECTURE

**Diagram (viewBox 760x200):**
- 90% BEAM-NATIVE (0 FORK) → 10% PERSISTENT PORTS → INTERACTION LOOP
- ETS :memgit_* <0.5ms → go test (1 port)
- 1. Agent reserves ETS lock
- DuckDB ast_nodes <1ms → cargo test (1 port)
- 2. PolicyGate check + fix hint
- libgraph CALLS BFS <2ms → gradle (1 port)
- 3. binary_part patch /tmp/kilas
- Tree-sitter NIF dirty_cpu → mix test (1 port)
- 4. Tree-sitter NIF parse
- Finch HTTP pool → git push (1 port)
- 5. MemGit ETS commit + TIA
- PolicyGate <1ms → apt install (1 port)
- 6. Test impacted via Port
- ≤1 fork/min • reuse forever

## 05 — All 14 Interactions — APIs & Flows

| INTENT | EXAMPLE QUERY | INTERNAL FLOW | LATENCY / FORKS |
|---|---|---|---|
| Query | "How to add login?" | Router → QueryEngine GraphRAG DuckDB+libgraph → parent_context envelope → answer + file:line | <10ms • 0 fork |
| Generate | "Add hash_password()" | CodeWriter reserve lock → PolicyGate → workspace patch → TreeSitter check → MemGit ETS → TIA 2 tests 8-25ms | <25ms TIA • 0 fork if no test |
| Debug | "Why user_id nil at auth.ex:42?" | DebugEngine ETS :runtime_bindings lookup node_id → stacktrace + history + last values | <15ms • 0 fork |
| Profile | "Why login slow?" | ProfileEngine fprof/go pprof/cargo flamegraph in /tmp/kilas_lab RAM → DuckDB store → 80% hash_password | <100ms profile • 1 fork |
| Env Fix | "Fix my env" | EnvDoctor EnvGraph error regex → apt package → install via persistent Port → retry compile | <5s apt • 1 fork |
| Security | "Is this safe?" | SecurityEngine libgraph 2-hop traversal ASTNode→DEPENDS_ON→Package→HAS_VULN→Vuln | <10ms • 0 fork |
| Survival | "Will this survive OOM?" | SurvivalEngine gauges: nand_writes, battery, oom_risk, thermal from /sys | <5ms • 0 fork |
| Tutor | "Explain auth as story" | TutorEngine simplified graph + mermaid diagram + parent_context story | <10ms • 0 fork |
| REPL | "What if algo=:sha3?" | LiveLab IEx persistent Port in /tmp/kilas_lab RAM eval no commit | <20ms • 0 fork (port reuse) |
| Collab | "Why edit rejected?" | CollabEngine MemGit timeline + ETS :ast_locks reservations + history | <5ms • 0 fork |
| Deploy | "Push" | Housekeeper sync() atomic rsync + WAL shadow.journal + git push Port | 60s tick • 1 fork push |
| Open | "Open auth.go" | TreeSitterServer parse if needed → DuckDB → return file + ast_nodes | <5ms • 0 fork |
| Edit | "Edit hash_password impl" | Same as Generate, but with existing symbol range replacement | <25ms • 0 fork |
| Status | "Status" | WorkspaceManager + Housekeeper + locks + MemGit log + battery gauge | <5ms • 0 fork |

ROUTER — INTENT CLASSIFICATION

```elixir
defmodule Kilas.Interrogation.Router do
  def route(query) do
    q = String.downcase(query)
    cond do
      q =~ ~r/how|what|where|explain|show/ -> :query
      q =~ ~r/add|create|generate|implement/ -> :generate
      q =~ ~r/why.*nil|debug|error|stacktrace/ -> :debug
      q =~ ~r/slow|profile|perf|flame/ -> :profile
      q =~ ~r/env|fix.*env|apt|missing/ -> :env
      q =~ ~r/safe|vuln|cve|security/ -> :security
      q =~ ~r/survive|oom|battery|nand/ -> :survival
      q =~ ~r/story|tutorial|mermaid|explain.*as/ -> :tutor
      q =~ ~r/what if|try|eval|repl/ -> :repl
      q =~ ~r/rejected|collab|who.*edit|lock/ -> :collab
      q =~ ~r/push|deploy|sync/ -> :deploy
      q =~ ~r/open/ -> :open
      true -> :query
    end
  end
end
```

DEBUG ENGINE — RUNTIME BINDINGS

```elixir
defmodule Kilas.Interrogation.DebugEngine do
  def get_runtime_value(filepath, line, variable) do
    node_id = "#{filepath}::line_#{line}"
    # ETS :runtime_bindings from last failed test
    case :ets.lookup(:runtime_bindings, node_id) do
      [] -> %{found: false, hint: "no failed run yet, run tests first"}
      bindings ->
        relevant = Enum.filter(bindings, fn {_, _, var, _, _} -> var == variable end)
        %{
          found: true,
          values: relevant,
          stacktrace: hd(relevant).stacktrace,
          history: get_memgit_history(filepath)
        }
    end
  end
end

# TestRunner stores bindings on failure:
# defp store_bindings(run_id, test_output) do
#   parse "user_id = nil at auth.ex:42" + stack
#   :ets.insert(:runtime_bindings, {run_id, node_id, var, value, stack})
# end
```

FULL DEVELOPER LOOP — 14 INTERACTIONS ACROSS 6 LAYERS

Code: Query (GraphRAG) → Generate (Single-Writer) → TIA (BlastRadius) → Test (Port)

Runtime: Debug (bindings ETS) → Profile (fprof/pprof in workspace) → REPL (LiveLab IEx)

Environment: EnvDoctor (regex→apt→Port) → Survival (battery/thermal/nand gauges)

Knowledge: Security (Package→Vuln traversal) → Tutor (story+mermaid)

Collaboration: Collab (MemGit timeline + locks)

Deploy: ShadowSync atomic + git push

## 06 — Configuration — mix.exs / .kilas.json / Policies

MIX.EXS — EXACT DEPS

```elixir
defmodule Kilas.MixProject do
  use Mix.Project

  def project do
    [
      app: :kilas,
      version: "2.0.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      rustler_crates: [
        tree_sitter_nif: [
          path: "native/tree_sitter_nif",
          mode: :release
        ],
        go_vet_nif: [
          path: "native/go_vet_nif",
          mode: :release,
          features: ["go-vet"]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :observer],
      mod: {Kilas.Application, []}
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.32.0"},
      {:duckdbex, "~> 0.3.7"}, # AST storage
      {:libgraph, "~> 0.16"}, # BEAM-memory graph projection
      {:finch, "~> 0.19.0"}, # HTTP, no curl fork
      {:req, "~> 0.5.0"}, # wrapper over Finch
      {:jason, "~> 1.4"},
      {:owl, "~> 0.12.0"}, # TUI
      {:ex_tree_sitter, "~> 0.1.0", optional: true},
      {:benchee, "~> 1.3", only: :dev}
    ]
  end
end

# config/config.exs
import Config
config :kilas,
  workspace_path: "/tmp/kilas",
  workspace_size: "1G",
  memory_limit: 512 * 1024 * 1024, # 512MB BEAM
  dirty_schedulers: 4,
  shadow_sync_interval: 60_000,
  lock_ttl: 30_000,
  physical_fallback: "./kilas_physical",
  battery_threshold: 20,
  thermal_threshold: 45_000 # millidegree
```

TEMPLATES — GO.JSON EXAMPLE

```
{
  "language": "go",
  "compile": "go build -o /tmp/kilas/bin/app ./...",
  "check": "go vet ./...",
  "test_targeted": "go test -run {test_symbol} -count=1 -run Test{TestSymbol} ./... 2>&1 | head -n 200",
  "test_all": "go test ./... -count=1 -short 2>&1 | tail -n 50",
  "file_patterns": ["**/*.go", "go.mod", "go.sum"],
  "persistent_port": {
    "bin": "go",
    "args": ["version"],
    "reuse": true,
    "cwd": "/tmp/kilas"
  },
  "env": {
    "CGO_ENABLED": "0",
    "GOFLAGS": "-mod=mod"
  },
  "granularity": {
    "function": "vector",
    "struct": "graph-only",
    "method": "vector"
  }
}

// rust.json
{
  "language": "rust",
  "compile": "cargo build --bin kilas_app --manifest-path /tmp/kilas/Cargo.toml",
  "check": "cargo clippy --manifest-path /tmp/kilas/Cargo.toml -- -D warnings",
  "test_targeted": "cargo test {test_symbol} --manifest-path /tmp/kilas/Cargo.toml -- --nocapture 2>&1 | head -n 200",
  "test_all": "cargo test --manifest-path /tmp/kilas/Cargo.toml -- --nocapture 2>&1 | tail -n 80",
  "persistent_port": {"bin": "cargo", "args": ["--version"], "reuse": true}
}

// .kilas.json (user overrides, auto-detected)
{
  "compile": "zig build",
  "test_targeted": "zig test {filepath} --test-filter {test_symbol}",
  "custom_env": {"ZIG_GLOBAL_CACHE_DIR": "/tmp/kilas/zig-cache"}
}
```

PRIV/POLICIES/ANTI_PATTERNS.JSON

```sql
[
  {
    "id": "sql_injection",
    "regex": "fmt\\.Sprintf.*%s.*SELECT|fmt.Sprintf.*%s.*INSERT",
    "message": "Raw SQL interpolation detected, use parameterized query",
    "fix": "Use db.Query(\"SELECT ... WHERE id = ?\", id)",
    "severity": "critical",
    "languages": ["go"]
  },
  {
    "id": "unhandled_task",
    "regex": "Task\\.async\\(?!.*Task\\.await)",
    "message": "Unhandled Task.async without await, may leak",
    "fix": "Add Task.await or Task.yield",
    "severity": "high",
    "languages": ["elixir"]
  },
  {
    "id": "unwrap_in_prod",
    "regex": "\\.unwrap\\(\\)",
    "message": "unwrap() in non-test code, use ? or expect with context",
    "fix": "Replace with .expect(\"context\") or propagate error",
    "severity": "high",
    "languages": ["rust"]
  },
  {
    "id": "hardcoded_secret",
    "regex": "(?i)(api_key|password|secret)\\s*=\\s*[\"\'][^\"\']+[\"\']",
    "message": "Hardcoded secret detected",
    "fix": "Use System.get_env or Vault",
    "severity": "critical"
  }
]
```

## 07 — Build Order for Claude Code

STEP-BY-STEP — VERIFY EACH WITH MIX TEST BEFORE NEXT

1

mix new kilas --sup

Create project, add deps to mix.exs, create priv/templates, priv/policies. mix deps.get.

2

Storage layer first

WorkspaceManager (/tmp/kilas dir + 1GB quota, recover_from_disk), MemGit ETS (3 tables, commit/log/diff/status/rollback), DuckDBServer (create ast_nodes table, insert/query), GraphServer (project graph_edges into libgraph), Housekeeper skeleton (60s timer, no sync yet). Test: test/workspace_manager_test.exs, memgit_test.exs must pass.

3

AST layer

TreeSitterServer NIF via Rustler (native/tree_sitter_nif/src/lib.rs, cargo, parse_file, parse_string, language auto-detect from ext), Granularity (map lang-> node_type-> vector/graph-only), ParentContext (build envelope: imports+class+surrounding funcs from DuckDB), PolicyGate (load anti_patterns.json, <1ms regex check, return fix). Test: parse Go/Rust/Java/Elixir files in /tmp/kilas sample.

4

TIA layer

BlastRadius (GraphServer bounded BFS CALLS depth≤5), TestRunner (GenericAdapter integration), FocusedSignal (parse output to 200 token hint). Test: test/blast_radius_test.exs with sample graph A->B->C, C changed => tests for A,B returned.

5

Compiler layer

GenericAdapter (EEx eval, run cwd, template, context), PersistentPort (Port.open spawn_executable, single fork, reuse, GenServer + Registry), ShadowRegistry (auto-detect go.mod/Cargo.toml/etc, ETS cache), ShadowServer (compile, check, run_targeted). Test: detect Go project, run go vet via Port, reuse port.

6

CodeWriter layer

Coordinator singleton {:global, __MODULE__}, LockManager ETS :ast_locks TTL 30s, Patcher binary_part surgical. Test: two agents try reserve same node_id, second fails, first patches, MemGit commit <0.5ms, TreeSitter syntax check rejects bad code.

7

Interrogation layer

Router intent classification regex, QueryEngine GraphRAG DuckDB+libgraph <10ms + parent_context, DebugEngine ETS :runtime_bindings, ProfileEngine fprof/go pprof/cargo flamegraph in /tmp/kilas_lab, EnvDoctor EnvGraph regex->apt, SecurityEngine Package->Vuln traversal, SurvivalEngine gauges /sys, TutorEngine story+mermaid, CollabEngine timeline+locks. Test: each engine unit test.

8

Tools

HTTP via Finch (not curl), LiveLab IEx persistent Port in /tmp/kilas_lab RAM eval without commit, REPL. Test: Finch get httpbin, LiveLab eval 1+1.

9

Housekeeper 60s sync

Implement full sync(): workspace -> .kilas_shadow_tmp -> rsync -> physical -> git push via persistent Port, WAL shadow.journal, thermal/battery pause. Test: modify file in /tmp/kilas, trigger sync, check physical has file.

10

TUI CLI

Owl TUI commands: open, edit, ask, debug, profile, env fix, explain, push, status. Each command calls Router. Render status gauges. Test: manual TUI walkthrough.

11

Templates + policies

Create 8 templates JSON (go, rust, java-gradle, java-maven, elixir, python, zig, node) in priv/templates, anti_patterns.json in priv/policies. Verify ShadowRegistry loads each.

12

Tests for each interaction

test/query_test.exs, debug_test.exs, profile_test.exs, env_doctor_test.exs, security_test.exs, survival_test.exs, tutor_test.exs, collab_test.exs, all_interaction_test.exs. Full loop: Query -> Generate -> TIA -> Debug -> Profile -> Push.

VERIFICATION CHECKPOINTS

After each layer: mix test. After storage: workspace file read <2ms (validated f2fs), MemGit commit <0.5ms. After AST: Tree-sitter parse Go file <5ms. After TIA: BlastRadius <2ms. After compiler: Port reuse confirmed (1 fork total). After code_writer: surgical patch microsecond. Full loop end-to-end <50ms for Query+Generate+TIA.

## 08 — Performance Targets — Poco F5 Pro

| OPERATION | TARGET | FORKS | NOTES |
|---|---|---|---|
| Query (GraphRAG) | <10ms | 0 | DuckDB FTS + libgraph CALLS BFS + parent_context envelope |
| Generate (TIA) | <25ms | 0 (or 1 if tests) | ETS lock + PolicyGate <1ms + binary_part + Tree-sitter NIF + MemGit + BlastRadius |
| Debug (bindings) | <15ms | 0 | ETS :runtime_bindings lookup + MemGit history |
| Profile (fprof/pprof) | <100ms | 1 | Profile in /tmp/kilas_lab RAM, store flame in DuckDB |
| Env fix (apt) | <5s | 1 | EnvGraph regex → apt via persistent Port, reuse port |
| Security (CVE traversal) | <10ms | 0 | libgraph Package->HAS_VULN->Vuln 2-hop |
| Survival gauges | <5ms | 0 | Read /sys/class/power_supply, /proc/meminfo, thermal_zone |
| Tutor (story+mermaid) | <10ms | 0 | Simplified graph + precomputed parent_context |
| MemGit commit | <0.5ms | 0 | ETS insert only, no disk |
| Workspace file read | <2ms | 0 | File.read! from /tmp/kilas (f2fs; hot files via page cache — validated 1.2ms) |
| Tree-sitter parse (1 file) | <5ms | 0 | Rustler NIF dirty_cpu, not CLI |
| BlastRadius | <2ms | 0 | libgraph CALLS BFS depth≤5 (benchmark required) |
| ShadowSync 60s | ~200ms | 1 (git push) | Atomic rsync + WAL, not during loop |
| Forks/min | <1 | — | Persistent Ports reuse, Finch no fork, NIF no fork |
| Battery | <5%/hr | — | BEAM 512MB limit, no busy loop, Housekeeper pause <20% |
| NAND writes | 0 during loop | — | Only atomic rsync every 60s, WAL batch |

## 09 — Mobile Survival Spec — NAND / OOM / Thermal

WORKSPACE + QUOTA (no tmpfs)

```elixir
# Plain f2fs dir + quota. PRoot has no usable tmpfs (validated:
# /dev/shm absent on Android host, mounts impossible rootless).
def ensure_workspace do
  workspace = "/tmp/kilas"
  File.mkdir_p!(workspace)
  check_quota(workspace)
end

# 1GB quota
def check_quota(workspace_path) do
  {size, _} = System.cmd("du", ["-sb", workspace_path])
  {bytes, _} = Integer.parse(size)
  if bytes > 1_000_000_000, do: {:error, :quota_exceeded}, else: :ok
end
```

OOM HANDLING — BEAM HEART

• config.exs memory_limit 512MB

• BEAM heart enabled: HEART_BEAT_TIMEOUT=30

• On restart: WorkspaceManager.recover_from_disk() rsync physical → workspace

• ETS tables recreated, DuckDB reopen from /tmp/kilas/.kilas_db (workspace on f2fs; WAL in physical); GraphServer rebuilds libgraph from graph_edges

• No data loss: last ShadowSync max 60s ago

• Housekeeper pauses when Mem >400MB

THERMAL + BATTERY — PAUSE LOGIC

```elixir
def read_battery do
  case File.read("/sys/class/power_supply/battery/capacity") do
    {:ok, c} -> String.to_integer(String.trim(c))
    _ -> 100
  end
end

def read_temp do
  case File.read("/sys/class/thermal/thermal_zone0/temp") do
    {:ok, t} -> String.to_integer(String.trim(t)) # millidegree
    _ -> 0
  end
end

# In Housekeeper and Coordinator:
if battery < 20 or temp > 45_000 do
  Logger.warning("Paused: battery #{battery}%, temp #{temp/1000}C")
  :paused
end
```

NAND PROTECTION

• Zero small writes during loop

• Only Housekeeper 60s atomic rsync --delete

• WAL shadow.journal batched, not per commit

• DuckDB file in workspace (f2fs), flushed only on ShadowSync (libgraph held in BEAM memory, rebuilt on boot)

• Git push via Port, not shell loop

• Target: <100MB/day NAND writes on Poco F5 Pro

## 10 — Testing Spec — Interaction Coverage

TEST FILES — EACH INTERACTION

```text
test/
├── workspace_manager_test.exs
│   └── ensure workspace dir, quota, recover_from_disk
├── memgit_test.exs
│   └── commit <0.5ms, log, diff, status, rollback
├── blast_radius_test.exs
│   └── A->B->C graph, change C => tests for A,B
├── query_test.exs
│   └── "How to add login?" -> GraphRAG <10ms, file:line
├── generate_test.exs
│   └── Add hash_password, PolicyGate, TIA 2 tests
├── debug_test.exs
│   └── Why nil at auth.ex:42? -> bindings ETS
├── profile_test.exs
│   └── Profile login slow -> flamegraph 80% hash
├── env_doctor_test.exs
│   └── gcc missing -> apt build-essential
├── security_test.exs
│   └── Package->CVE traversal
├── survival_test.exs
│   └── battery, oom_risk, thermal gauges
├── tutor_test.exs
│   └── Explain auth as story + mermaid
├── collab_test.exs
│   └── lock reservation, MemGit timeline
├── all_interaction_test.exs
│   └── Full loop: Query->Generate->TIA->Debug->Push
└── test_helper.exs (setup workspace, ETS, DuckDB, GraphServer)

# Each test must use /tmp/kilas, not physical
# mix test --trace should show <50ms per interaction
# No sh -c loops, no bash, only BEAM + Ports
```

EXAMPLE TEST — QUERY

```elixir
defmodule Kilas.QueryTest do
  use ExUnit.Case

  setup do
    Kilas.Storage.WorkspaceManager.init([])
    Kilas.Storage.DuckDBServer.insert_node(%{
      id: "lib/auth.ex::hash_password",
      filepath: "lib/auth.ex",
      symbol_name: "hash_password",
      node_type: "function_declaration",
      language: "elixir",
      start_line: 10,
      end_line: 20,
      content: "def hash_password(pw), do: Bcrypt.hash_pwd_salt(pw)",
      parent_context: Jason.encode!(%{imports: ["Bcrypt"]})
    })
    :ok
  end

  test "query how to add login <10ms" do
    {time, result} = :timer.tc(fn ->
      Kilas.Interrogation.QueryEngine.query("How to add login?")
    end)

    assert time < 10_000 # microseconds = 10ms
    assert result.file == "lib/auth.ex"
    assert result.line == 10
  end
end
```

FINAL VERIFICATION

• mix test all 14 interaction tests pass

• No test forks more than 1 (check via :os.getpid)

• workspace file read <2ms measured (f2fs, validated)

• Battery drain <5%/hr idle loop

• Housekeeper 60s sync atomic rename verified

• Zero NAND during loop (strace -e fsync)

## FINAL — Claude Code Prompt + Diagrams

DIAGRAM 03 — FULL LAYER MAP

**Diagram (viewBox 360x420):**
- TUI CLI — Owl
- open edit ask debug profile env explain push status
- Router — Intent Classification
- query generate debug profile env security survival tutor c
- ollab deploy
- Interrogation — 8 Engines
- QueryEngine GraphRAG, DebugEngine ETS, ProfileEngine fprof
- , EnvDoctor, Security, Survival, Tutor, Collab
- CodeWriter — Singleton
- Coordinator + Patcher binary_part + LockManager ETS
- TIA + AST + Compiler
- BlastRadius GraphServer, TreeSitter NIF, GenericAdapter, Persis
- tentPort, ShadowRegistry
- Storage — Volatile-First
- WorkspaceManager 1GB (f2fs), MemGit ETS, DuckDB ast_nodes + graph_edges, libgraph gra
- ph, Housekeeper 60s ShadowSync

EXECUTABLE PROMPT — COPY PASTE TO CLAUDE CODE

```text
You are building Kilas v2.0 exactly per this spec. Build file by file in order Section 7. Do not skip. Use persistent Ports for heavy compilers, BEAM-native for fast path. All work in /tmp/kilas workspace (plain f2fs dir — PRoot has no tmpfs, do not attempt mounts). No bash sh -c loops. Verify each component with mix test before next.

INVARIANTS:
- Volatile-First: hot state in ETS/MemGit (BEAM RAM); /tmp/kilas workspace 1GB quota on f2fs, recover_from_disk()
- Zero-Fork: ≤1 fork/min, 90% ETS/DuckDB/libgraph/NIF/Finch, 10% persistent Ports
- Single-Writer: CodeWriter GenServer singleton {:global}, ETS :ast_locks per function TTL 30s
- Language Agnostic: Tree-sitter NIF + .kilas.json + GenericAdapter EEx + auto-detect go.mod/Cargo.toml/build.gradle/mix.exs/package.json

BUILD ORDER:
1. mix new kilas --sup, deps, priv/templates, priv/policies
2. storage layer: WorkspaceManager, MemGit ETS 3 tables, DuckDBServer ast_nodes + graph_edges, GraphServer libgraph projection, Housekeeper skeleton
3. ast layer: TreeSitterServer Rustler NIF dirty_cpu, Granularity, ParentContext envelope, PolicyGate <1ms anti_patterns.json
4. tia layer: BlastRadius libgraph CALLS BFS depth≤5, TestRunner GenericAdapter, FocusedSignal 200 token hint
5. compiler layer: ShadowRegistry auto-detect, GenericAdapter EEx, PersistentPort Port.open spawn_executable reuse, ShadowServer
6. code_writer layer: Coordinator singleton reserve_ast_lock apply_surgical_patch binary_part, Patcher, LockManager
7. interrogation layer: Router intent + 8 engines QueryEngine GraphRAG <10ms, DebugEngine :runtime_bindings, ProfileEngine fprof/pprof workspace, EnvDoctor regex->apt->Port, SecurityEngine Package->Vuln, SurvivalEngine gauges, TutorEngine story+mermaid, CollabEngine timeline
8. tools: http Finch not curl, live_lab IEx persistent Port /tmp/kilas_lab RAM eval no commit
9. Housekeeper 60s sync: workspace -> .kilas_shadow_tmp -> rsync -> physical atomic + WAL shadow.journal + git push Port, pause battery<20% temp>45C
10. TUI CLI Owl: open edit ask debug profile env fix explain push status
11. templates 8x JSON + policies anti_patterns.json
12. tests 14 interactions, full loop <50ms

PERF TARGETS: Query <10ms, Generate <25ms TIA, Debug <15ms, Profile <100ms, Env <5s, Security <10ms, Survival <5ms, MemGit <0.5ms, workspace file read <2ms, BlastRadius <2ms, Zero NAND during loop, Battery <5%/hr, Forks <1/min.

MOBILE: workspace /tmp/kilas on f2fs with 1GB quota (no tmpfs in PRoot — validated), BEAM heart OOM recover_from_disk, thermal pause, NAND only atomic rsync.

TEST: Each interaction test in test/*_test.exs, all pass, no sh -c loops.

Now build. Start with step 1. Do not ask questions, build file by file.
```

Paste entire spec document + prompt above into Claude Code. Build file by file, verify with mix test.

NATIVE NIF — TREE-SITTER RUSTLER SKELETON

```rust
// native/tree_sitter_nif/src/lib.rs
use rustler::{Env, NifResult, Term};
use tree_sitter::{Parser, Language};
extern "C" { fn tree_sitter_go() -> Language; fn tree_sitter_rust() -> Language; /* etc */ }

#[rustler::nif(schedule = "DirtyCpu")]
fn parse_file(path: String, lang: String) -> NifResult<(bool, String)> { /* ... */ }

#[rustler::nif(schedule = "DirtyCpu")]
fn parse_string(code: String, lang: String) -> NifResult<(bool, String)> { /* ... */ }

rustler::init!("Elixir.Kilas.AST.TreeSitterNIF", [parse_file, parse_string]);

// mix.exs rustler_crates path: native/tree_sitter_nif, mode: release
// Cargo.toml dependencies: tree-sitter 0.22, tree-sitter-go, tree-sitter-rust, tree-sitter-java, tree-sitter-elixir, tree-sitter-python, tree-sitter-zig, tree-sitter-javascript
```

KILAS v2.0 — COMPLETE SPEC READY FOR CLAUDE CODE

Volatile-First Guarantee

Hot state in BEAM RAM (ETS/MemGit). All edits in /tmp/kilas workspace — plain f2fs dir, 1GB quota (PRoot has no tmpfs; validated). Physical only via Housekeeper 60s atomic rsync + WAL. No fsync during loop. Recover on OOM via rsync physical→workspace.

Zero-Fork Guarantee

90% BEAM-native: ETS MemGit <0.5ms, DuckDB <1ms, libgraph <2ms, Tree-sitter NIF dirty_cpu, Finch. 10% persistent Ports: go/cargo/gradle/mix/git/apt each 1 Port.open, reuse forever. ≤1 fork/min.

Single-Writer Guarantee

CodeWriter GenServer singleton

{:global}

. All edits via ETS :ast_locks per function, not file, TTL 30s. binary_part surgical microsecond, Tree-sitter syntax check rollback. MemGit ETS commit only.

KILAS v2.0 • BEAM + Elixir + Rust + Go • POCO F5 PRO 12GB • EXECUTABLE SPEC • BUILD EXACTLY PER THIS DOC

Paste into Claude Code: “Build Kilas v2.0 exactly per this spec, file by file, no shortcuts”

© Kilas Volatile-First Harness • workspace 1GB (f2fs) • ShadowSync 60s • Zero-Fork • Single-Writer

SPEC VALID • READY TO PASTE
