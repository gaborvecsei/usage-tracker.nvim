# Telemetry endpoint

This small restapi is responsible for the data collection if you enabled telemetry by defining the endpoint
in the `setup({..., telemetry_endpoint="http://localhost:8000"})`

# Setup

Change the volume mount if it is required

## Build & Run

```bash
# Build
docker compose build

# Run - it should always start (until you manually stop it)
docker compose up -d
```

# Queries

Just a few examples how you can use the logged data in the DB

## Human readable visit logs

```sql
SELECT
	filepath,
	strftime('%Y-%m-%d %H:%M:%S', datetime(entry, 'unixepoch', '+2 hour')) AS entry_time,
    strftime('%Y-%m-%d %H:%M:%S', datetime(exit, 'unixepoch', '+2 hour')) AS exit_time,
    ROUND((exit - entry)/60.0, 2) AS elapsed_time
FROM
    visits
ORDER BY entry DESC
```

## Daily aggregated activity

```sql
SELECT
	date(entry, 'unixepoch') AS date,
    SUM(ROUND((exit - entry)/60.0, 2)) AS elapsed_time
FROM
    visits
GROUP BY
	date
ORDER BY date DESC
```

