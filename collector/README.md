# Andon History Collector

Small Go worker that polls the public Andon FM metadata endpoints and records a local SQLite history database. It is designed to run as one long-lived Fly Machine with a persistent volume mounted at `/data`.

## Data Model

The database is shaped for analysis:

- `stations` is a station dimension table.
- `tracks` is a de-duplicated track dimension table keyed by normalized title and artist.
- `observations` is the minute-grain fact table. Each poll upserts one row per station per UTC minute with the observed track, listener count, current block, and raw source payloads.
- `airings` is a convenience/session table. It approximates play starts and ends by extending the latest airing when a station reports the same track on consecutive polls, or inserting a new airing when the track changes.

The `observations` table is the source of truth for time-based questions. It stores both exact `observed_at` and bucketed minute fields:

- `observed_minute`, a UTC ISO minute timestamp.
- `minute_epoch`, a Unix timestamp truncated to the minute.
- `observed_date`, the UTC date.
- `minute_of_day`, from `0` to `1439`.
- `weekday_utc`, with Sunday as `0`.

The `airings` table is useful for human-scale counts like "how many times did this song appear to play?"

Useful views:

- `station_minute_observations`
- `current_station_airings`
- `track_airing_counts`
- `hourly_track_observations`
- `same_minute_history_similarity`
- `same_minute_prior_day_similarity`

## Local Run

```sh
cd collector
go run . -once -db /tmp/andon-history.sqlite3
```

Run continuously:

```sh
go run . -db ./andon-history.sqlite3 -interval 1m
```

## Example Queries

Most-played tracks by detected airing:

```sql
SELECT station_name, artist, title, airing_count, last_played_at
FROM track_airing_counts
ORDER BY airing_count DESC, last_played_at DESC
LIMIT 25;
```

When a track tends to appear:

```sql
SELECT
    minute_of_day / 60 AS utc_hour,
    minute_of_day % 60 AS utc_minute,
    station_name,
    artist,
    title,
    count(*) AS observed_minutes
FROM station_minute_observations
WHERE artist = 'Tame Impala'
GROUP BY minute_of_day, station_id, track_id
ORDER BY observed_minutes DESC, minute_of_day;
```

How similar each minute is to the same minute yesterday:

```sql
SELECT
    observed_minute,
    station_name,
    current_artist,
    current_title,
    prior_artist,
    prior_title,
    exact_track_match
FROM same_minute_prior_day_similarity
ORDER BY observed_minute DESC, station_name;
```

How similar each minute is to the same minute across prior days:

```sql
SELECT
    observed_minute,
    station_name,
    avg(exact_track_match) AS average_exact_match,
    count(*) AS compared_prior_days
FROM same_minute_history_similarity
WHERE days_back BETWEEN 1 AND 14
GROUP BY observed_minute, station_id
ORDER BY observed_minute DESC, station_name;
```

Similarity by minute-of-day over the whole dataset:

```sql
SELECT
    minute_of_day / 60 AS utc_hour,
    minute_of_day % 60 AS utc_minute,
    station_name,
    avg(exact_track_match) AS average_exact_match,
    count(*) AS comparisons
FROM same_minute_history_similarity
WHERE days_back BETWEEN 1 AND 7
GROUP BY station_id, minute_of_day
ORDER BY average_exact_match DESC, comparisons DESC;
```

Raw observations for one station:

```sql
SELECT observed_minute, artist, title, listener_count
FROM station_minute_observations
WHERE station_id = '6b53fc38-ed57-4738-80d6-f9fddf981054'
ORDER BY observed_minute DESC
LIMIT 100;
```

## Fly.io

Create a Fly app and volume:

```sh
fly apps create andon-cone-history
fly volumes create andon_history_data --size 1 --region iad --app andon-cone-history
cp collector/fly.toml.example fly.toml
fly deploy
```

The example Fly config sets:

- `SQLITE_PATH=/data/andon-history.sqlite3`
- `POLL_INTERVAL=1m`

SQLite is a good fit while this is one writer on one Machine. If the analysis needs concurrent writes, remote querying, or larger retention later, the append-only `observations` table will migrate cleanly to DuckDB, ClickHouse, Postgres/Timescale, or MotherDuck.
