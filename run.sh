#!/usr/bin/env bash
# Usage: ./run.sh          reproduce the bug (unlisted_no_key not in [[omnisharded_tables]])
#        ./run.sh fixed    workaround: unlisted_no_key listed as omnisharded too
set -euo pipefail
cd "$(dirname "$0")"
[[ "${1:-}" == "fixed" ]] && export PGDOG_CONFIG=pgdog-fixed.toml

via_pgdog() { docker compose exec -T -e PGPASSWORD=app shard0 psql -h pgdog -p 6432 -U app -d app -At "$@"; }
on_shard()  { docker compose exec -T -e PGPASSWORD=app "shard$1" psql -U app -d app -At "${@:2}"; }

docker compose down -v --remove-orphans >/dev/null 2>&1 || true
docker compose up -d --wait --quiet-pull
sleep 2

echo "== seed one row per table through pgdog"
via_pgdog <<'SQL'
INSERT INTO listed_with_key (org_id, name) VALUES (7, 'row');
INSERT INTO unlisted_no_key (listed_id) VALUES (1);
INSERT INTO unlisted_a VALUES (1, 'row');
INSERT INTO unlisted_b VALUES (1, 1);
SQL
for n in 0 1 2; do
  echo "shard$n: listed_with_key=$(on_shard $n -c 'select count(*) from listed_with_key') unlisted_no_key=$(on_shard $n -c 'select count(*) from unlisted_no_key') unlisted_a=$(on_shard $n -c 'select count(*) from unlisted_a') unlisted_b=$(on_shard $n -c 'select count(*) from unlisted_b')"
done

check() { # label expected sql
  local got; got=$(via_pgdog -c "$3" | wc -l | tr -d ' ')
  if [[ "$got" == "$2" ]]; then echo "OK    $1: $got row(s)"; else echo "FAIL  $1: expected $2 row(s), got $got"; fi
}
echo "== queries through pgdog (every table has exactly one row on every shard)"
check "listed_with_key JOIN unlisted_no_key                  " 1 \
  'SELECT l.* FROM listed_with_key l INNER JOIN unlisted_no_key u ON u.listed_id = l.id WHERE u.id = 1'
check "same join with the sharding key in WHERE              " 1 \
  'SELECT l.* FROM listed_with_key l INNER JOIN unlisted_no_key u ON u.listed_id = l.id WHERE u.id = 1 AND l.org_id = 7'
check "unlisted_a JOIN unlisted_b (no sharding key anywhere) " 1 \
  'SELECT a.* FROM unlisted_a a INNER JOIN unlisted_b b ON b.a_id = a.id WHERE b.id = 1'
check "single-table read of listed_with_key                  " 1 'SELECT * FROM listed_with_key'
check "single-table read of unlisted_no_key                  " 1 'SELECT * FROM unlisted_no_key'
