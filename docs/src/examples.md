# Examples

## Atlantic weather showcase

The figure below demonstrates the package's core capabilities: station discovery, bulk observation retrieval, and DataFrame conversion — all visualised with [CairoMakie.jl](https://github.com/MakieOrg/Makie.jl).

![Atlantic Weather Showcase](../assets/atlantic_weather.png)

**Panel 1 — Station network.** All 342 stations plotted by longitude and latitude, coloured by data source (IPMA, RHA, DSCIG, AIRC, AJAM, TER). Red stars mark the representative stations used in the time series below.

**Panel 2 — Hourly temperature.** One month of hourly temperature data for three stations spanning the Atlantic region. The latitudinal temperature gradient is clearly visible: Madeira (warmest), Azores (mid-range), and mainland Portugal (coolest, with larger diurnal swings).

**Panel 3 — Data completeness.** Observation counts per station for the same period, showing near-complete hourly coverage (~700 observations per station for 31 days).

### Running the demo

The script lives in `examples/atlantic_weather.jl` with its own environment:

```bash
cd examples
julia --project=. -e 'using Pkg; Pkg.develop(path=".."); Pkg.add(["CairoMakie", "DataFrames"])'
export ATLANTICCLOUD_API_KEY="your_key_here"
julia --project=. atlantic_weather.jl
```

### Key code patterns

**Fetch all stations and convert to a DataFrame:**

```julia
using AtlanticCloud, DataFrames

client = AtlanticCloudClient()
stations = get_stations(client)
df = to_dataframe(stations)
```

**Bulk fetch observations for multiple stations:**

```julia
using Dates

ids = [s.station_id for s in stations if s.station_id !== nothing]
obs = get_observations_bulk(client, ids,
    start_date=Date(2024, 12, 1),
    end_date=Date(2024, 12, 31),
    metrics=["temperature_c"],
    on_error=:warn)

df_obs = to_dataframe(obs)
```

**Use GeoInterface for spatial workflows:**

```julia
import GeoInterface as GI

s = stations[1]
GI.geomtrait(s)        # PointTrait()
GI.x(GI.PointTrait(), s)  # longitude
GI.y(GI.PointTrait(), s)  # latitude
```

Stations implement `PointTrait`, so they work directly with GeoMakie, GeometryOps, GeoJSON.jl, and any other JuliaGeo-compatible package.
