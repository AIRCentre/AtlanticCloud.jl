# AtlanticCloud.jl

[![CI](https://github.com/AIRCentre/AtlanticCloud.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/AIRCentre/AtlanticCloud.jl/actions/workflows/CI.yml)
[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://aircentre.github.io/AtlanticCloud.jl/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Julia client for the [AIR Centre](https://www.aircentre.org) Atlantic Cloud API, providing access to meteorological and rainfall data across Portugal and Brazil.

![Atlantic Weather Showcase](examples/figures/atlantic_weather.png)

## Features

- **21,000+ stations** across Portugal and Brazil, from 6 observation networks.
- **Portuguese observations** — 5+ years of hourly data: temperature, wind, humidity, radiation, precipitation, and pressure.
- **Brazilian rainfall** — 140 years (1885–2025) of hourly and daily precipitation from the UNIPLU-BR dataset, with quality control flags.
- **Bulk fetch** — retrieve observations for multiple stations in a single call with configurable error handling.
- **DataFrame integration** — convert results directly to DataFrames for analysis and plotting.
- **JuliaGeo compatible** — stations implement [GeoInterface.jl](https://github.com/JuliaGeo/GeoInterface.jl) `PointTrait` for use with GeoMakie, GeometryOps, and the wider JuliaGeo ecosystem.

## Installation

Once registered with the Julia General Registry:

```julia
using Pkg
Pkg.add("AtlanticCloud")
```

For now, install directly from the repository:

```julia
using Pkg
Pkg.add(url="https://github.com/AIRCentre/AtlanticCloud.jl")
```

## Authentication

An API key is required. Register at [services.aircentre.org/access/account](https://services.aircentre.org/access/account).

Set your key as an environment variable:

```bash
export ATLANTICCLOUD_API_KEY="your_key_here"
```

Or pass it directly:

```julia
client = AtlanticCloudClient(api_key="your_key_here")
```

## Quick start

```julia
using AtlanticCloud
using Dates
using DataFrames

# Create a client (reads ATLANTICCLOUD_API_KEY from environment)
client = AtlanticCloudClient()

# List all stations
stations = get_stations(client)

# Filter by data source
ipma_stations = get_stations(client, source="IPMA")

# Get observations for a station
obs = get_observations(client, "11217160",
    start_date=Date(2024, 1, 1),
    end_date=Date(2024, 1, 31))

# Select specific metrics
obs_temp = get_observations(client, "11217160",
    start_date=Date(2024, 1, 1),
    end_date=Date(2024, 1, 31),
    metrics=["temperature_c", "wind_speed_kmh"])

# Convert to a DataFrame
df = to_dataframe(obs)

# Bulk fetch across multiple stations
ids = [s.station_id for s in stations if s.station_id !== nothing]
bulk_obs = get_observations_bulk(client, ids[1:5],
    start_date=Date(2024, 1, 1),
    end_date=Date(2024, 1, 7))
df_bulk = to_dataframe(bulk_obs)
```


## Brazilian rainfall data

```julia
# Get Brazilian stations
br_stations = get_stations(client, country="BR")

# Filter by state
sp_stations = get_stations(client, country="BR", state="SP")

# Hourly rainfall observations
br_obs = get_br_observations(client,
    resolution="hourly", state="SP",
    start_date=Date(2020, 1, 1),
    end_date=Date(2020, 1, 31))

# Daily rainfall
daily = get_br_observations(client,
    resolution="daily", station_id="1442032",
    start_date=Date(2020, 1, 1),
    end_date=Date(2020, 6, 30))

# Filter by quality control
clean = get_br_observations(client,
    resolution="hourly", state="MG",
    start_date=Date(2020, 1, 1),
    end_date=Date(2020, 1, 31),
    flagged=false)

df_br = to_dataframe(br_obs)
```
## GeoInterface integration

Stations implement `PointTrait`, so they work directly with JuliaGeo packages:

```julia
import GeoInterface as GI

s = stations[1]
GI.geomtrait(s)              # PointTrait()
GI.x(GI.PointTrait(), s)     # longitude
GI.y(GI.PointTrait(), s)     # latitude
```

## Available metrics — Portuguese observations

| Metric | Unit | Notes |
|--------|------|-------|
| `temperature_c` | °C | Air temperature |
| `wind_speed_kmh` | km/h | Wind speed |
| `wind_direction_bin` | integer | Wind direction bin index |
| `rel_humidity_pctg` | % | Relative humidity |
| `radiation_kjm2` | kJ/m² | Solar radiation |
| `precipitation_accum_mm` | mm | Accumulated precipitation |
| `pressure_hpa` | hPa | Atmospheric pressure (limited station coverage) |


## Available metrics — Brazilian observations

| Metric | Unit | Notes |
|--------|------|-------|
| `precipitation_accum_mm` | mm | Accumulated precipitation |
| `qc_flag` | string | `"PASS"` or `"SUSPECT_*"` |
| `flagged` | boolean | `true` if observation is suspect |
| `state` | string | Two-letter Brazilian state code |
## API documentation

- **Package docs:** [aircentre.github.io/AtlanticCloud.jl](https://aircentre.github.io/AtlanticCloud.jl/)
- Meteorology API: [services.aircentre.org/access/docs/meteorology](https://services.aircentre.org/access/docs/meteorology)
- EO Catalog: [eo-catalog.ac-az1.aircentre.org/api/v1/api](https://eo-catalog.ac-az1.aircentre.org/api/v1/api) (coming soon)

## Contributing

This package is developed by [AIR Centre](https://www.aircentre.org).
Issues and pull requests are welcome. For questions, contact [dev@aircentre.org](mailto:dev@aircentre.org).