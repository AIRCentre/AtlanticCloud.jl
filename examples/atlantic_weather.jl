# examples/atlantic_weather.jl
#
# Atlantic Weather Showcase — demonstrates AtlanticCloud.jl capabilities
# Produces a multi-panel figure showing the station network, data completeness,
# and temperature time series across the Atlantic region.
#
# Run from the examples/ directory:
#   julia --project=. atlantic_weather.jl
#
# Requires a valid API key in ATLANTICCLOUD_API_KEY environment variable.

using AtlanticCloud
using DataFrames
using CairoMakie
using Dates

# ---------------------------------------------------------------------------
# 1. Fetch station data
# ---------------------------------------------------------------------------

println("Creating client...")
client = AtlanticCloudClient()

println("Fetching stations...")
stations = get_stations(client)
df_stations = to_dataframe(stations)
println("  $(nrow(df_stations)) stations loaded")

# ---------------------------------------------------------------------------
# 2. Select representative stations for time series
#    Pick stations across the geographic spread with good data coverage
# ---------------------------------------------------------------------------

# Candidates: one per region, IPMA source (most reliable coverage)
representative_ids = String[]
representative_labels = String[]

# Find one Azores station (lon < -20)
azores = filter(r -> !ismissing(r.longitude_deg) && r.longitude_deg < -20 && !ismissing(r.source) && r.source == "IPMA", df_stations)
if nrow(azores) > 0
    push!(representative_ids, azores.station_id[1])
    push!(representative_labels, "Azores: $(azores.place[1])")
end

# Find one Madeira station (-20 < lon < -14)
madeira = filter(r -> !ismissing(r.longitude_deg) && r.longitude_deg > -20 && r.longitude_deg < -14 && !ismissing(r.source) && r.source == "IPMA", df_stations)
if nrow(madeira) > 0
    push!(representative_ids, madeira.station_id[1])
    push!(representative_labels, "Madeira: $(madeira.place[1])")
end

# Find one mainland station (lon > -14)
mainland = filter(r -> !ismissing(r.longitude_deg) && r.longitude_deg > -14 && !ismissing(r.source) && r.source == "IPMA", df_stations)
if nrow(mainland) > 0
    push!(representative_ids, mainland.station_id[1])
    push!(representative_labels, "Mainland: $(mainland.place[1])")
end

println("  Representative stations: $(length(representative_ids))")
for (id, label) in zip(representative_ids, representative_labels)
    println("    $id — $label")
end

# ---------------------------------------------------------------------------
# 3. Fetch observations for representative stations (last 30 days)
# ---------------------------------------------------------------------------

end_date = Date(2024, 12, 31)
start_date = Date(2024, 12, 1)

println("Fetching observations ($start_date to $end_date)...")
obs = get_observations_bulk(client, representative_ids,
    start_date=start_date,
    end_date=end_date,
    metrics=["temperature_c"],
    progress=true)
df_obs = to_dataframe(obs)
println("  $(nrow(df_obs)) observations loaded")

if nrow(df_obs) == 0
    println("WARNING: No observations returned. Try a different date range.")
    println("  The API may not have data for the requested period.")
    println("  Continuing with station map only...")
end

# ---------------------------------------------------------------------------
# 4. Build the figure
# ---------------------------------------------------------------------------

println("Building figure...")

fig = Figure(size=(1200, 1400), fontsize=14)

# --- Panel 1: Station network map (lon/lat scatter) ---

ax1 = Axis(fig[1, 1],
    title="AIR Centre Atlantic Cloud — Station Network",
    xlabel="Longitude (°)",
    ylabel="Latitude (°)",
    aspect=DataAspect(),
)

# Colour by source
sources = unique(skipmissing(df_stations.source))
source_colors = Dict(zip(sources, Makie.wong_colors()[1:length(sources)]))

for src in sources
    subset = filter(r -> !ismissing(r.source) && r.source == src, df_stations)
    scatter!(ax1, subset.longitude_deg, subset.latitude_deg,
        label=src,
        markersize=6,
        color=source_colors[src],
    )
end

# Mark representative stations
for (id, label) in zip(representative_ids, representative_labels)
    row = filter(r -> !ismissing(r.station_id) && r.station_id == id, df_stations)
    if nrow(row) > 0
        scatter!(ax1, [row.longitude_deg[1]], [row.latitude_deg[1]],
            marker=:star5,
            markersize=18,
            color=:red,
            strokewidth=1,
            strokecolor=:black,
        )
    end
end

axislegend(ax1, position=:lb)

# --- Panel 2: Temperature time series ---

ax2 = Axis(fig[2, 1],
    title="Hourly Temperature — December 2024",
    xlabel="Date",
    ylabel="Temperature (°C)",
)

has_timeseries = false
colors = Makie.wong_colors()
for (i, (id, label)) in enumerate(zip(representative_ids, representative_labels))
    station_obs = filter(r -> !ismissing(r.station_id) && r.station_id == id && !ismissing(r.temperature_c), df_obs)
    if nrow(station_obs) > 0
        lines!(ax2, station_obs.timestamp, station_obs.temperature_c,
            label=label,
            color=colors[i],
            linewidth=1.2,
        )
        global has_timeseries = true
    end
end

if has_timeseries
    axislegend(ax2, position=:rt)
end

# --- Panel 3: Data availability summary ---

ax3 = Axis(fig[3, 1],
    title="Observations per Station — December 2024",
    xlabel="Station",
    ylabel="Number of Observations",
    xticklabelrotation=π/4,
)

# Count observations per representative station
counts = Int[]
labels = String[]
for (id, label) in zip(representative_ids, representative_labels)
    station_obs = filter(r -> !ismissing(r.station_id) && r.station_id == id, df_obs)
    push!(counts, nrow(station_obs))
    # Short label for x-axis
    short = split(label, ": ")[end]
    if length(short) > 20
        short = short[1:20] * "…"
    end
    push!(labels, short)
end

barplot!(ax3, 1:length(counts), counts,
    color=colors[1:length(counts)],
)
ax3.xticks = (1:length(labels), labels)

# ---------------------------------------------------------------------------
# 5. Save
# ---------------------------------------------------------------------------

mkpath("figures")
output_path = "figures/atlantic_weather.png"
save(output_path, fig, px_per_unit=2)
println("Saved to $output_path")
println("Done!")
