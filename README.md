# AtlanticCloud.jl
[![CI](https://github.com/AIRCentre/AtlanticCloud.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/AIRCentre/AtlanticCloud.jl/actions/workflows/CI.yml)

A Julia client for the [AIR Centre](https://www.aircentre.org) Atlantic Cloud API, providing access to meteorological station data and observations across the Atlantic region.

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

An API key is required. Register at:
**https://services.aircentre.org/access/account**

Set your key as an environment variable:
```bash
export ATLANTICCLOUD_API_KEY="your_key_here"
```

Or pass it directly when creating a client:
```julia
client = AtlanticCloudClient(api_key="your_key_here")
```

## Quick start
```julia
using AtlanticCloud
using Dates

# Create a client
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

# Access fields
obs[1].timestamp
obs[1].temperature_c
obs[1].wind_speed_kmh
```

## Available metrics
```julia
VALID_METRICS
```

`wind_speed_kmh`, `temperature_c`, `radiation_kjm2`, `wind_direction_bin`,
`precipitation_accum_mm`, `rel_humidity_pctg`, `pressure_hpa`

## API documentation

- Meteorology: https://services.aircentre.org/access/docs/meteorology
- EO Catalog: https://eo-catalog.ac-az1.aircentre.org/api/v1/api

## Contributing

This package is developed by [AIR Centre](https://www.aircentre.org).
Issues and pull requests are welcome. For questions, contact dev@aircentre.org.

