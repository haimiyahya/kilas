#!/bin/bash
# T0#1 tmpfs latency test (fixed timing: date +%s%N, no /usr/bin/time).
set -u
DATA=/root/projects/kilas/.tools/validate/data
LOG=$DATA/tmpfs_latency.txt
: > "$LOG"
log() { echo "$@" | tee -a "$LOG"; }

bench_big() {
  local label=$1 path=$2
  local f="$path/bench_100m.bin"
  log "=== $label ==="
  local s e
  s=$(date +%s%N)
  dd if=/dev/zero of="$f" bs=1M count=100 conv=fdatasync 2>/dev/null
  e=$(date +%s%N)
  log "write 100MB: $(( (e - s) / 1000000 ))ms"
  s=$(date +%s%N)
  dd if="$f" of=/dev/null bs=1M 2>/dev/null
  e=$(date +%s%N)
  log "read  100MB: $(( (e - s) / 1000000 ))ms"
  rm -f "$f"
}

bench_4k_reads() {
  # pure-syscall read loop via dd single 4k block, repeated: no fork cost
  local label=$1 path=$2
  local f="$path/bench_small.bin"
  dd if=/dev/zero of="$f" bs=4k count=1 2>/dev/null
  # warm cache
  for i in $(seq 1 100); do cat "$f" > /dev/null; done
  local s e
  s=$(date +%s%N)
  for i in $(seq 1 1000); do cat "$f" > /dev/null; done
  e=$(date +%s%N)
  log "4KB read x1000 via cat(fork): $(( (e - s) / 1000000 / 1000 ))ms per op incl. fork"
  rm -f "$f"
}

# many-small-files latency: create 1000 files, read them back — closer to kilas file workload
bench_many_files() {
  local label=$1 path=$2
  local d="$path/kilas_many"
  mkdir -p "$d"
  local s e
  s=$(date +%s%N)
  for i in $(seq 1 1000); do echo "content $i" > "$d/f$i.txt"; done
  e=$(date +%s%N)
  log "1000 small-file writes: $(( (e - s) / 1000000 ))ms total, $(( (e - s) / 1000000 / 1000 ))ms/file"
  s=$(date +%s%N)
  for i in $(seq 1 1000); do cat "$d/f$i.txt" > /dev/null; done
  e=$(date +%s%N)
  log "1000 small-file reads (fork): $(( (e - s) / 1000000 ))ms total, $(( (e - s) / 1000000 / 1000 ))ms/file"
  # pure read via loopback file read in bash (no fork): use read
  s=$(date +%s%N)
  for i in $(seq 1 1000); do read -r x < "$d/f$i.txt"; done
  e=$(date +%s%N)
  log "1000 small-file reads (bash builtin open+read): $(( (e - s) / 1000000 ))ms total, $(( (e - s) / 1000000 / 1000 ))ms/file"
  rm -rf "$d"
}

bench_big "/dev/shm (f2fs disk, dev fe2c)" /dev/shm
bench_4k_reads "/dev/shm" /dev/shm
bench_many_files "/dev/shm" /dev/shm
log "done"
