# pgdog omnisharded JOIN fan-out

Minimal reproduction of a routing bug in [pgdog](https://github.com/pgdogdev/pgdog).

## The bug

A table that is listed in `[[omnisharded_tables]]` with `sticky = true` and that also has the
sharding-key column (`org_id`, matched by a `[[sharded_tables]]` entry with `column = "org_id"` and
no table name) is written to every shard, as expected for an omnisharded table.

A `SELECT` that joins this table to an unlisted table without the sharding key, and that has no
sharding-key predicate, is broadcast to every shard. The results are concatenated, so one logical row
comes back once per shard.

Expected: the query is routed to one shard, like every other omnisharded read.

| Query through pgdog                                     | Rows | Shards hit |
| ------------------------------------------------------- | ---- | ---------- |
| `listed_with_key` JOIN `unlisted_no_key`                | 3    | 3          |
| same join with `AND l.org_id = 7`                       | 1    | 1          |
| `unlisted_a` JOIN `unlisted_b` (no key anywhere)        | 1    | 1          |
| `SELECT * FROM listed_with_key`                         | 1    | 1          |
| `SELECT * FROM unlisted_no_key`                         | 1    | 1          |

Workaround: list the partner table in `[[omnisharded_tables]]` too (`pgdog/pgdog-fixed.toml`).

Reproduced on `ghcr.io/pgdogdev/pgdog-enterprise:v2026-09-10` and on the open-source
`ghcr.io/pgdogdev/pgdog:main` image (build of 2026-09-14).

## Run

Needs Docker with compose v2. Nothing else is installed on the host.

```
./run.sh          # FAIL: expected 1 row(s), got 3
./run.sh fixed    # OK: partner table listed too
```

Environment variables:

| Variable       | Default                                          | Purpose                          |
| -------------- | ------------------------------------------------ | -------------------------------- |
| `PGDOG_IMAGE`  | `ghcr.io/pgdogdev/pgdog-enterprise:v2026-09-10`  | pgdog image to test              |
| `PGDOG_PORT`   | `16432`                                          | host port for a manual `psql`    |

Manual access: `psql -h localhost -p 16432 -U app app` (password `app`).

## Layout

| Path                     | Content                                                          |
| ------------------------ | ---------------------------------------------------------------- |
| `docker-compose.yml`     | three Postgres 17 shards and pgdog                               |
| `initdb/schema.sql`      | four tables, created on every shard at start                     |
| `pgdog/pgdog.toml`       | failing configuration: only `listed_with_key` is omnisharded     |
| `pgdog/pgdog-fixed.toml` | workaround: `unlisted_no_key` is omnisharded too                 |
| `pgdog/users.toml`       | one user, `app` / `app`                                          |
| `run.sh`                 | starts the stack, seeds one row per table, prints OK or FAIL     |
