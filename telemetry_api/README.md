# Telemetry endpoint

This small restapi is responsible for the data collection if you enabled telemetry by defining the endpoint
in the `setup({..., telemetry_endpoint="http://localhost:8000/visit"})`

# Setup

Change the volume mount if it is required

## Build & Run

```
# Build
docker-compose build

# Run - it should always start (until you manually stop it)
docker-compose up -d
```

