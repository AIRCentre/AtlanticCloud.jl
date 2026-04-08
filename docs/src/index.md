# AtlanticCloud.jl

A Julia client for the [Atlantic Cloud](https://www.aircentre.org/atlantic-cloud/) API — meteorological and rainfall data from 21,700+ stations across Portugal and Brazil. Powered by the [AIR Centre](https://www.aircentre.org) and its Atlantic basin partners.

## Features

- **21,700+ stations** across Portugal and Brazil, from 6 observation networks.
- **Portuguese observations** — 5+ years of hourly data: temperature, wind, humidity, radiation, precipitation, and pressure.
- **Brazilian rainfall** — 140 years (1885–2025) of hourly and daily precipitation from the UNIPLU-BR dataset, with quality control flags.
- **Bulk fetch** — retrieve observations for multiple stations in a single call with configurable error handling.
- **DataFrame integration** — convert results directly to DataFrames for analysis and plotting.
- **JuliaGeo compatible** — stations implement [GeoInterface.jl](https://github.com/JuliaGeo/GeoInterface.jl) `PointTrait` for use with GeoMakie, GeometryOps, NaturalEarth.jl, and the wider JuliaGeo ecosystem.

## Installation

```julia
using Pkg
Pkg.add("AtlanticCloud")
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

## Quick start — Portuguese weather data

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

# Convert to DataFrame
df = to_dataframe(obs)

# Bulk fetch across multiple stations
all_ids = [s.station_id for s in stations if s.station_id !== nothing]
bulk_obs = get_observations_bulk(client, all_ids[1:5],
    start_date=Date(2024, 1, 1),
    end_date=Date(2024, 1, 7))
```

## Quick start — Brazilian rainfall data

```julia
# All Brazilian stations
br_stations = get_stations(client, country="BR")

# Filter by state
sp_stations = get_stations(client, country="BR", state="SP")

# Hourly rainfall for a state
br_obs = get_br_observations(client,
    resolution="hourly", state="SP",
    start_date=Date(2020, 1, 1),
    end_date=Date(2020, 1, 31))

# Daily rainfall for a single station
daily = get_br_observations(client,
    resolution="daily", station_id="1442032",
    start_date=Date(2020, 1, 1),
    end_date=Date(2020, 6, 30))

# Only clean (non-suspect) observations
clean = get_br_observations(client,
    resolution="hourly", state="MG",
    start_date=Date(2020, 1, 1),
    end_date=Date(2020, 1, 31),
    flagged=false)

df_br = to_dataframe(br_obs)
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

## GeoInterface integration

Stations implement `PointTrait`, so they work directly with JuliaGeo packages:

```julia
import GeoInterface as GI

s = stations[1]
GI.geomtrait(s)              # PointTrait()
GI.x(GI.PointTrait(), s)     # longitude
GI.y(GI.PointTrait(), s)     # latitude
```

## API documentation

- Meteorology API: [services.aircentre.org/access/docs/meteorology](https://services.aircentre.org/access/docs/meteorology)
- EO Catalog: [eo-catalog.ac-az1.aircentre.org/api/v1/api](https://eo-catalog.ac-az1.aircentre.org/api/v1/api) (coming soon)
