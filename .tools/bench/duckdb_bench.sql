.timer on
.echo off
.output /dev/null

CREATE TABLE graph_edges(label TEXT, src TEXT, dst TEXT, count INT);
COPY graph_edges FROM '__EDGES_CSV__' (FORMAT csv, HEADER true);

.output stdout
.mode box
SELECT '__SCALE__ loaded', count(*) AS edges FROM graph_edges;

-- 1. Projection feed: full edge scan (what GraphServer would read at boot)
SELECT 'full_scan' AS bench, count(*) AS rows FROM graph_edges;
SELECT 'proj_feed' AS bench, count(*) AS n FROM (SELECT label, src, dst FROM graph_edges);

-- 2. In-neighbor query (BFS backing query, unindexed): callers of one node
SELECT 'in_nbr_noidx' AS bench, count(*) AS n FROM graph_edges WHERE dst = 'n1234';

-- 3. Point query with index
CREATE INDEX idx_edges_dst ON graph_edges(dst);
SELECT 'in_nbr_idx' AS bench, count(*) AS n FROM graph_edges WHERE dst = 'n1234';

DROP TABLE graph_edges;
.output /dev/null
