"""Synthetic kilas-style graph generator: heavy-tailed CALLS graph + labeled edges."""
import random, sys

def gen(n_nodes, target_edges, seed, out_prefix):
    rng = random.Random(seed)
    # Preferential attachment: call graph degrees are heavy-tailed.
    parents = [0]  # node i attaches to parents[i]; node 0 is root
    for i in range(1, n_nodes):
        # attach to an existing node chosen by degree-biased (linear) preference
        parents.append(rng.randrange(max(1, i // 2)) if i > 1 else 0)

    calls = set()
    while len(calls) < target_edges:
        src = rng.randrange(1, n_nodes)
        # 70% follow parent chain (hub-heavy), 30% uniform
        dst = parents[src] if rng.random() < 0.7 else rng.randrange(n_nodes)
        if src != dst:
            calls.add((src, dst))
    calls = list(calls)

    n_tests = max(10, n_nodes // 20)
    n_pkgs = max(10, n_nodes // 200)
    n_vulns = max(2, n_pkgs // 10)
    n_commits = max(10, n_nodes // 50)

    with open(f"{out_prefix}_nodes.csv", "w") as f:
        f.write("id,filepath,symbol_name,node_type,language\n")
        for i in range(n_nodes):
            f.write(f"n{i},lib/mod{i % 997}.ex,f{i},function,elixir\n")

    with open(f"{out_prefix}_edges.csv", "w") as f:
        f.write("label,src,dst,count\n")
        for s, d in calls:
            f.write(f"CALLS,n{s},n{d},{rng.randrange(1, 9)}\n")
        for _ in range(target_edges // 20):  # TESTED_BY: node -> test
            f.write(f"TESTED_BY,n{rng.randrange(n_nodes)},t{rng.randrange(n_tests)},1\n")
        for _ in range(target_edges // 50):  # DEPENDS_ON + IMPORTS
            f.write(f"DEPENDS_ON,n{rng.randrange(n_nodes)},p{rng.randrange(n_pkgs)},1\n")
            f.write(f"IMPORTS,n{rng.randrange(n_nodes)},p{rng.randrange(n_pkgs)},1\n")
        for _ in range(target_edges // 50):  # MODIFIED_IN
            f.write(f"MODIFIED_IN,n{rng.randrange(n_nodes)},c{rng.randrange(n_commits)},1\n")
        for v in range(n_vulns):  # HAS_VULN
            f.write(f"HAS_VULN,p{rng.randrange(n_pkgs)},v{v},1\n")

    with open(f"{out_prefix}_meta.txt", "w") as f:
        f.write(f"{n_nodes} {target_edges}\n")
    print(f"{out_prefix}: {n_nodes} nodes, {len(calls)} CALLS edges")

if __name__ == "__main__":
    base = sys.argv[1]
    scales = {
        "100": (32, 100), "1k": (160, 1000), "5k": (800, 5000),
        "10k": (1600, 10000), "20k": (3200, 20000), "30k": (4800, 30000),
        "40k": (6400, 40000), "50k": (8000, 50000),
        "100k": (16000, 100000), "150k": (24000, 150000),
        "200k": (30000, 200000), "500k": (70000, 500000),
    }
    names = sys.argv[2:] or ["50k", "200k", "500k"]
    for name in names:
        nodes, edges = scales[name]
        gen(nodes, edges, 42, f"{base}/{name}")
