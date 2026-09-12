#!/usr/bin/env python3
"""T0#2 DuckDB rapid-write bench: upsert latency at scales 1k/10k/50k.

Interactive-edit model: agent edits file -> upsert a handful of edges.
Measures: single-row upserts x100 (timer per stmt), batch upserts of 10 and 100.
Durable file DB on f2fs (the real spec deployment), memory_limit=512MB threads=4.
"""
import sys, os

OUT = sys.argv[1] if len(sys.argv) > 1 else ".tools/validate/run_writes.sql"

def edge(i):
    return ("call", f"m{i % 9973}.go:func{i % 23}", f"m{(i * 7 + 3) % 9973}.go:func{(i * 5) % 31}")

lines = [
    ".timer on",
    ".mode trash",
    "SET memory_limit='512MB';",
    "SET threads=4;",
    "INSTALL updatable; LOAD updatable;" if False else "",
    "DROP TABLE IF EXISTS graph_edges;",
    "CREATE TABLE graph_edges(label TEXT, src TEXT, dst TEXT, count INT, PRIMARY KEY(label, src, dst));",
]
# seed with inserts in one batch (bulk load path)
seed = 1000
values = ",".join(f"('{l}','{s}','{d}',1)" for l, s, d in (edge(i) for i in range(seed)))
lines.append(f"INSERT INTO graph_edges VALUES {values};")
lines.append(".output stdout")
lines.append("SELECT 'scale_1000';")
lines.append(".output /dev/null")

def upsert_stmt(i):
    l, s, d = edge(10_000_000 + i)
    return f"INSERT INTO graph_edges VALUES ('{l}','{s}','{d}',1) ON CONFLICT (label, src, dst) DO UPDATE SET count = count + 1;"

def batch_stmt(start, n):
    vals = ",".join(f"('{l}','{s}','{d}',1)" for l, s, d in (edge(20_000_000 + start + j) for j in range(n)))
    return f"INSERT INTO graph_edges VALUES {vals} ON CONFLICT (label, src, dst) DO UPDATE SET count = count + 1;"

def block(tag, base):
    out = [f".output stdout", f"SELECT '{tag}';", ".output /dev/null"]
    # 100 single-row upserts, individually timed
    for i in range(100):
        out.append(upsert_stmt(base + i))
    # one batch of 10, one of 100 (single statements, timed as units)
    out.append(batch_stmt(100, 10))
    out.append(batch_stmt(110, 100))
    return out

lines += block("bench_at_1000", 0)

# grow to 10k, repeat
extra = ",".join(f"('{l}','{s}','{d}',1)" for l, s, d in (edge(i) for i in range(seed, 10_000)))
lines += [f"INSERT INTO graph_edges VALUES {extra};", ".output stdout", "SELECT 'scale_10000';", ".output /dev/null"]
lines += block("bench_at_10000", 1000)

# grow to 50k, repeat
extra = ",".join(f"('{l}','{s}','{d}',1)" for l, s, d in (edge(i) for i in range(10_000, 50_000)))
lines += [f"INSERT INTO graph_edges VALUES {extra};", ".output stdout", "SELECT 'scale_50000';", ".output /dev/null"]
lines += block("bench_at_50000", 2000)

lines += [".output stdout", "SELECT count(*) FROM graph_edges;", "CHECKPOINT;", ".output /dev/null"]

with open(OUT, "w") as f:
    f.write("\n".join(x for x in lines if x) + "\n")
print(f"wrote {OUT}")
