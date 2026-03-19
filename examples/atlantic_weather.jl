# examples/atlantic_weather.jl
#
# Atlantic Weather Showcase — demonstrates AtlanticCloud.jl capabilities
# Produces a four-panel publication-quality figure showing the station network,
# multi-year temperature record, diurnal climatology, and hourly resolution.
#
# Run from the examples/ directory:
#   julia --project=. atlantic_weather.jl
#
# Requires a valid API key in ATLANTICCLOUD_API_KEY environment variable.

using AtlanticCloud
using DataFrames
using CairoMakie
using GeoMakie
using Dates
using Statistics

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
# 2. Select representative stations
# ---------------------------------------------------------------------------

representative_ids = String[]
representative_labels = String[]
representative_short = String[]

# Azores (lon < -20)
azores = filter(r -> !ismissing(r.longitude_deg) && r.longitude_deg < -20 &&
    !ismissing(r.source) && r.source == "IPMA", df_stations)
if nrow(azores) > 0
    push!(representative_ids, azores.station_id[1])
    push!(representative_labels, "Azores: $(azores.place[1])")
    push!(representative_short, "Azores")
end

# Madeira (-20 < lon < -14)
madeira = filter(r -> !ismissing(r.longitude_deg) && r.longitude_deg > -20 &&
    r.longitude_deg < -14 && !ismissing(r.source) && r.source == "IPMA", df_stations)
if nrow(madeira) > 0
    push!(representative_ids, madeira.station_id[1])
    push!(representative_labels, "Madeira: $(madeira.place[1])")
    push!(representative_short, "Madeira")
end

# Mainland (lon > -14)
mainland = filter(r -> !ismissing(r.longitude_deg) && r.longitude_deg > -14 &&
    !ismissing(r.source) && r.source == "IPMA", df_stations)
if nrow(mainland) > 0
    push!(representative_ids, mainland.station_id[1])
    push!(representative_labels, "Mainland: $(mainland.place[1])")
    push!(representative_short, "Mainland")
end

println("  Representative stations: $(length(representative_ids))")
for (id, label) in zip(representative_ids, representative_labels)
    println("    $id — $label")
end

# ---------------------------------------------------------------------------
# 3. Fetch full record in 6-month chunks
#    The API limits queries to a maximum of 6 months per request.
# ---------------------------------------------------------------------------

println("Fetching full observation record in 6-month chunks...")
all_obs = Observation[]

# The API limits queries to a maximum of 6 months per request.
fetch_ranges = [
    (Date(2022, 1, 1), Date(2022, 3, 31)),
    (Date(2022, 4, 1), Date(2022, 6, 30)),
    (Date(2022, 7, 1), Date(2022, 9, 30)),
    (Date(2022, 10, 1), Date(2022, 12, 31)),
    (Date(2023, 1, 1), Date(2023, 3, 31)),
    (Date(2023, 4, 1), Date(2023, 6, 30)),
    (Date(2023, 7, 1), Date(2023, 9, 30)),
    (Date(2023, 10, 1), Date(2023, 12, 31)),
    (Date(2024, 1, 1), Date(2024, 3, 31)),
    (Date(2024, 4, 1), Date(2024, 6, 30)),
    (Date(2024, 7, 1), Date(2024, 9, 30)),
    (Date(2024, 10, 1), Date(2024, 12, 31)),
    (Date(2025, 1, 1), Date(2025, 3, 31)),
    (Date(2025, 4, 1), Date(2025, 6, 30)),
    (Date(2025, 7, 1), Date(2025, 9, 30)),
    (Date(2025, 10, 1), Date(2025, 12, 31)),
    (Date(2026, 1, 1), Date(2026, 3, 18)),
]

for (start_d, end_d) in fetch_ranges
    println("  Fetching $start_d to $end_d...")
    chunk = get_observations_bulk(client, representative_ids,
        start_date=start_d,
        end_date=end_d,
        metrics=["temperature_c"],
        progress=false)
    append!(all_obs, chunk)
    println("    $(length(chunk)) observations")
end

df_obs = to_dataframe(all_obs)
println("  Total: $(nrow(df_obs)) observations")

if nrow(df_obs) == 0
    error("No observations returned. Check API key and station availability.")
end

# Add helper columns
df_obs.date = Date.(df_obs.timestamp)
df_obs.hour = hour.(df_obs.timestamp)
df_obs.month_num = month.(df_obs.timestamp)
df_obs.year = year.(df_obs.timestamp)

# Date range of the data
date_min = minimum(df_obs.date)
date_max = maximum(df_obs.date)
years_span = round((date_max - date_min).value / 365.25, digits=1)
println("  Date range: $date_min to $date_max ($years_span years)")

# ---------------------------------------------------------------------------
# 4. Build the figure
# ---------------------------------------------------------------------------

println("Building figure...")

colors = Makie.wong_colors()
fig = Figure(size=(1400, 1800), fontsize=13)

# --- Panel 1: Station map with coastlines ---

ax1 = GeoAxis(fig[1, 1],
    title="AIR Centre Atlantic Cloud — Station Network",
    dest="+proj=merc",
    limits=(-33, -5, 31, 43),
)

# Coastlines and land
poly!(ax1, GeoMakie.land(); color=:grey90, strokecolor=:grey50, strokewidth=0.5)

# All stations by source
sources = sort(collect(Set(skipmissing(df_stations.source))))
source_colors = Dict(zip(sources, Makie.wong_colors()[1:length(sources)]))

for src in sources
    subset = filter(r -> !ismissing(r.source) && r.source == src, df_stations)
    scatter!(ax1, subset.longitude_deg, subset.latitude_deg,
        label=src,
        markersize=5,
        color=source_colors[src],
    )
end

# Representative stations (red stars with legend entry)
for (i, (id, short)) in enumerate(zip(representative_ids, representative_short))
    row = filter(r -> !ismissing(r.station_id) && r.station_id == id, df_stations)
    if nrow(row) > 0
        scatter!(ax1, [row.longitude_deg[1]], [row.latitude_deg[1]],
            marker=:star5,
            markersize=16,
            color=:red,
            strokewidth=1,
            strokecolor=:black,
            label=(i == 1 ? "Representative" : nothing),
        )
    end
end

axislegend(ax1, position=:lb)

# --- Panel 2: Full multi-year daily mean temperature ---

ax2 = Axis(fig[2, 1],
    title="Daily Mean Temperature — $date_min to $date_max ($years_span years)",
    xlabel="Date",
    ylabel="Temperature (°C)",
)

for (i, (id, label)) in enumerate(zip(representative_ids, representative_labels))
    station_obs = filter(r -> !ismissing(r.station_id) && r.station_id == id &&
        !ismissing(r.temperature_c), df_obs)
    if nrow(station_obs) > 0
        daily = combine(groupby(station_obs, :date),
            :temperature_c => mean => :temp_mean)
        sort!(daily, :date)
        lines!(ax2, daily.date, daily.temp_mean,
            label=label,
            color=colors[i],
            linewidth=0.8,
        )
    end
end

axislegend(ax2, position=:rt)

# --- Panel 3: Diurnal cycle climatology (first representative station) ---

climate_id = representative_ids[1]
climate_label = representative_labels[1]

climate_obs = filter(r -> !ismissing(r.station_id) && r.station_id == climate_id &&
    !ismissing(r.temperature_c), df_obs)

# Mean temperature by hour x month across the full record
diurnal = combine(groupby(climate_obs, [:hour, :month_num]),
    :temperature_c => mean => :temp_mean)

# Build 12x24 matrix (months on x-axis, hours on y-axis)
temp_matrix = fill(NaN, 12, 24)
for row in eachrow(diurnal)
    temp_matrix[row.month_num, row.hour + 1] = row.temp_mean
end

ax3 = Axis(fig[3, 1],
    title="Diurnal Cycle Climatology — $climate_label",
    xlabel="Month",
    ylabel="Hour of Day (UTC)",
    xticks=(1:12, ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]),
    yticks=(1:2:24, string.(0:2:23)),
)

hm = heatmap!(ax3, 1:12, 1:24, temp_matrix,
    colormap=:thermal,
)

Colorbar(fig[3, 2], hm, label="Temperature (°C)")

# --- Panel 4: One week at hourly resolution ---

# Pick a mid-January week from 2025
zoom_start = Date(2025, 1, 15)
zoom_end = zoom_start + Day(6)

# Fall back if no data in that range
zoom_check = filter(r -> !ismissing(r.temperature_c) &&
    r.date >= zoom_start && r.date <= zoom_end, df_obs)
if nrow(zoom_check) == 0
    # Try mid-record
    mid_date = date_min + Day(div(Dates.value(date_max - date_min), 2))
    zoom_start = mid_date
    zoom_end = mid_date + Day(6)
end

ax4 = Axis(fig[4, 1],
    title="Hourly Temperature — $(Dates.format(zoom_start, "d U yyyy")) to $(Dates.format(zoom_end, "d U yyyy"))",
    xlabel="Date & Time",
    ylabel="Temperature (°C)",
)

for (i, (id, short)) in enumerate(zip(representative_ids, representative_short))
    week_obs = filter(r -> !ismissing(r.station_id) && r.station_id == id &&
        !ismissing(r.temperature_c) &&
        r.date >= zoom_start && r.date <= zoom_end, df_obs)
    if nrow(week_obs) > 0
        sort!(week_obs, :timestamp)
        lines!(ax4, week_obs.timestamp, week_obs.temperature_c,
            label=short,
            color=colors[i],
            linewidth=1.2,
        )
    end
end

axislegend(ax4, position=:rt)

# ---------------------------------------------------------------------------
# 5. Save
# ---------------------------------------------------------------------------

mkpath("figures")
output_path = "figures/atlantic_weather.png"
save(output_path, fig, px_per_unit=2)
println("Saved to $output_path")
println("Done!")
