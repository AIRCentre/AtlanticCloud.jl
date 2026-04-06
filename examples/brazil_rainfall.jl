# examples/brazil_rainfall.jl
#
# Brazilian Rainfall Showcase — AtlanticCloud.jl
#
# Four-panel figure demonstrating Brazilian rainfall data served via the
# Atlantic Cloud API. The dataset combines observations from 6 national
# networks, quality-controlled and served at hourly and daily resolution.
#
# Run:  julia --project=. brazil_rainfall.jl
# Env:  ATLANTICCLOUD_API_KEY must be set
#
# References:
#   QC'd dataset: DOI: 10.5281/zenodo.19427080
#   QC pipeline:  DOI: 10.5281/zenodo.19427280
#   Raw dataset:  Lemos et al. (2026) UNIPLU-BR. DOI: 10.5281/zenodo.18883358
#   API docs:     https://services.aircentre.org/access/docs/meteorology

using AtlanticCloud
using DataFrames
using CairoMakie
using NaturalEarth
using Dates
using Statistics
import GeoInterface as GI

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

const SF_BOUNDS = (lat_min=-21.0, lat_max=-7.0, lon_min=-47.0, lon_max=-36.0)
const CLIM_YEARS = 2020:2022

const EVENTS = (
	petropolis = (
		label  = "Petrópolis, RJ — February 2022",
		lat    = -22.51,
		lon    = -43.18,
		radius = 0.3,
		start  = Date(2022, 2, 13),
		stop   = Date(2022, 2, 17),
	),
	rs_floods = (
		label  = "Rio Grande do Sul — May 2024",
		lat    = -29.92,
		lon    = -51.17,
		radius = 0.5,
		start  = Date(2024, 4, 27),
		stop   = Date(2024, 5, 6),
	),
)

const NETWORK_COLORS = Dict(
	"CEMADEN"         => Makie.wong_colors()[1],
	"Hidroweb diário" => Makie.wong_colors()[2],
	"INMET diário"    => Makie.wong_colors()[3],
	"INMET subdiário" => Makie.wong_colors()[4],
	"Telemetria"      => Makie.wong_colors()[5],
	"ICEA"            => Makie.wong_colors()[6],
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"""Split a date range into 3-month chunks (safely under the 6-month API limit)."""
function quarterly_chunks(start_date::Date, end_date::Date)
	chunks = Tuple{Date, Date}[]
	cursor = start_date
	while cursor <= end_date
		chunk_end = min(cursor + Month(3) - Day(1), end_date)
		push!(chunks, (cursor, chunk_end))
		cursor = chunk_end + Day(1)
	end
	chunks
end

"""Filter DataFrame to stations within a lat/lon box around a point."""
function nearby_stations(df::DataFrame, lat::Float64, lon::Float64, radius::Float64)
	filter(r -> abs(r.latitude_deg - lat) <= radius &&
	            abs(r.longitude_deg - lon) <= radius, df)
end

"""Fetch BR observations for multiple stations across a multi-year range, chunked quarterly."""
function fetch_chunked(client, station_ids::Vector{String};
		resolution::String, years, flagged=nothing, on_error=:warn)
	obs = BrObservation[]
	for yr in years
		for (s, e) in quarterly_chunks(Date(yr, 1, 1), Date(yr, 12, 31))
			println("  $s → $e...")
			chunk = get_br_observations_bulk(client, station_ids,
				resolution=resolution, start_date=s, end_date=e,
				flagged=flagged, on_error=on_error, progress=false)
			append!(obs, chunk)
		end
	end
	obs
end

"""Fetch event data for candidate stations near a location."""
function fetch_event(client, cemaden_df::DataFrame, ev)
	candidates = nearby_stations(cemaden_df, ev.lat, ev.lon, ev.radius)
	if nrow(candidates) == 0
		println("    No CEMADEN stations within $(ev.radius)° — skipping")
		return nothing
	end

	println("    $(nrow(candidates)) CEMADEN stations nearby")
	ev_ids = String[id for id in candidates.station_id if !ismissing(id)]
	ev_ids = ev_ids[1:min(5, length(ev_ids))]

	t0 = time()
	ev_obs = get_br_observations_bulk(client, ev_ids,
		resolution="hourly", start_date=ev.start, end_date=ev.stop,
		flagged=false, on_error=:warn, progress=false)
	df = to_dataframe(ev_obs)
	elapsed = round(time() - t0, digits=1)

	if nrow(df) > 0
		peak = maximum(df.precipitation_accum_mm)
		total = sum(df.precipitation_accum_mm)
		println("    $(nrow(df)) obs, peak: $(round(peak, digits=1)) mm/h, " *
		        "total: $(round(total, digits=1)) mm [$(elapsed)s]")
		return (df=df, label=ev.label, peak=peak, total=total)
	else
		println("    No observations returned [$(elapsed)s]")
		return nothing
	end
end

"""Plot a single GeoInterface LinearRing as a line on a Makie Axis."""
function plot_ring!(ax, ring; color=:grey50, linewidth=0.5)
	n = GI.ngeom(ring)
	n < 2 && return
	xs = Vector{Float64}(undef, n)
	ys = Vector{Float64}(undef, n)
	for j in 1:n
		pt = GI.getgeom(ring, j)
		xs[j] = GI.x(pt)
		ys[j] = GI.y(pt)
	end
	lines!(ax, xs, ys; color, linewidth)
end

"""Recursively plot a GeoJSON Polygon or MultiPolygon as boundary lines."""
function plot_geojson!(ax, geometry; color=:grey50, linewidth=0.5)
	trait = GI.geomtrait(geometry)
	if trait isa GI.PolygonTrait
		for i in 1:GI.ngeom(geometry)
			plot_ring!(ax, GI.getgeom(geometry, i); color, linewidth)
		end
	elseif trait isa GI.MultiPolygonTrait
		for i in 1:GI.ngeom(geometry)
			plot_geojson!(ax, GI.getgeom(geometry, i); color, linewidth)
		end
	end
end

"""Plot Brazilian state boundaries from NaturalEarth onto an Axis."""
function plot_brazil_boundaries!(ax)
	admin1 = naturalearth("admin_1_states_provinces", 10)
	n_plotted = 0
	for feat in admin1.features
		props = feat.properties
		get(props, :admin, nothing) == "Brazil" || continue
		plot_geojson!(ax, feat.geometry; color=:grey70, linewidth=0.5)
		n_plotted += 1
	end
	println("  Plotted $n_plotted state boundaries")
end

"""Look up a station's place name from the station DataFrame, falling back to the ID."""
function station_label(df_stations::DataFrame, station_id::String)
	row = filter(r -> !ismissing(r.station_id) && r.station_id == station_id, df_stations)
	nrow(row) > 0 && !ismissing(row.place[1]) ? row.place[1] : station_id
end

"""Build disambiguated labels for a list of station IDs (appends gauge suffix for duplicates)."""
function disambiguated_labels(df_stations::DataFrame, ids)
	raw = [station_label(df_stations, sid) for sid in ids]
	counts = Dict{String, Int}()
	for name in raw
		counts[name] = get(counts, name, 0) + 1
	end
	seen = Dict{String, Int}()
	labels = String[]
	for (name, sid) in zip(raw, ids)
		if counts[name] > 1
			seen[name] = get(seen, name, 0) + 1
			suffix = length(sid) >= 4 ? sid[end-3:end] : sid
			push!(labels, "$name ($suffix)")
		else
			push!(labels, name)
		end
	end
	labels
end

# ---------------------------------------------------------------------------
# 1. Fetch station data
# ---------------------------------------------------------------------------

println("Creating client...")
client = AtlanticCloudClient()

println("Fetching Brazilian stations...")
t0 = time()
br_stations = get_stations(client, country="BR")
df_br = to_dataframe(br_stations)
println("  $(nrow(df_br)) stations loaded ($(round(time() - t0, digits=1))s)")

source_counts = Dict{String, Int}()
for s in skipmissing(df_br.source)
	source_counts[s] = get(source_counts, s, 0) + 1
end
println("  Networks:")
for (net, n) in sort(collect(source_counts), by=last, rev=true)
	println("    $net: $n")
end

unknown_nets = setdiff(keys(source_counts), keys(NETWORK_COLORS))
if !isempty(unknown_nets)
	@warn "Unknown network names — update NETWORK_COLORS" unknown_nets
	for (i, net) in enumerate(unknown_nets)
		NETWORK_COLORS[net] = Makie.wong_colors()[mod1(length(NETWORK_COLORS) + i, 7)]
	end
end

# ---------------------------------------------------------------------------
# 2. Panel 2 data: São Francisco basin climatology
# ---------------------------------------------------------------------------

sf_all = filter(r ->
	r.latitude_deg >= SF_BOUNDS.lat_min && r.latitude_deg <= SF_BOUNDS.lat_max &&
	r.longitude_deg >= SF_BOUNDS.lon_min && r.longitude_deg <= SF_BOUNDS.lon_max,
	df_br)
println("\nSão Francisco bounding box: $(nrow(sf_all)) stations")

sf_candidates = filter(r -> !ismissing(r.source) && r.source == "Hidroweb diário", sf_all)
if nrow(sf_candidates) < 5
	sf_candidates = sf_all
	println("  Few Hidroweb diário stations in box — using all networks")
end

sort!(sf_candidates, :latitude_deg)
n_clim = min(8, nrow(sf_candidates))
idx = round.(Int, range(1, nrow(sf_candidates), length=n_clim))
clim_stations = sf_candidates[idx, :]
clim_ids = String[id for id in clim_stations.station_id if !ismissing(id)]
println("  Selected $(length(clim_ids)) stations for climatology:")
for (id, place) in zip(clim_stations.station_id, clim_stations.place)
	println("    $id — $(coalesce(place, "unnamed"))")
end

println("\nFetching daily observations ($(CLIM_YEARS))...")
t0 = time()
clim_obs = fetch_chunked(client, clim_ids,
	resolution="daily", years=CLIM_YEARS, flagged=false)
df_clim = to_dataframe(clim_obs)
println("  $(nrow(df_clim)) daily observations ($(round(time() - t0, digits=1))s)")

df_clim.month_num = month.(df_clim.timestamp)
monthly = combine(groupby(df_clim, :month_num),
	:precipitation_accum_mm => mean => :precip_mean,
	:precipitation_accum_mm => std  => :precip_std,
	nrow => :n_obs)
sort!(monthly, :month_num)

println("  Monthly aggregation:")
for r in eachrow(monthly)
	println("    Month $(lpad(r.month_num, 2)): $(round(r.precip_mean, digits=1)) ± " *
	        "$(round(r.precip_std, digits=1)) mm (n=$(r.n_obs))")
end

# ---------------------------------------------------------------------------
# 3. Panel 3 data: QC filtering effect
# ---------------------------------------------------------------------------

cemaden = filter(r -> !ismissing(r.source) && r.source == "CEMADEN", df_br)
sp_cemaden = nearby_stations(cemaden, -23.55, -46.63, 0.2)
if nrow(sp_cemaden) == 0
	@warn "No CEMADEN stations near São Paulo — falling back to first CEMADEN station"
	sp_cemaden = cemaden[1:1, :]
end
qc_id = sp_cemaden.station_id[1]
qc_place = coalesce(sp_cemaden.place[1], "unnamed")
println("\nQC comparison: $qc_id ($qc_place)")

qc_start = Date(2023, 1, 1)
qc_end = Date(2023, 3, 31)

println("Fetching hourly data (all + clean)...")
t0 = time()
qc_all_obs = get_br_observations(client,
	resolution="hourly", station_id=qc_id,
	start_date=qc_start, end_date=qc_end)
qc_clean_obs = get_br_observations(client,
	resolution="hourly", station_id=qc_id,
	start_date=qc_start, end_date=qc_end, flagged=false)

n_total = length(qc_all_obs)
n_clean = length(qc_clean_obs)
n_suspect = n_total - n_clean
pct = n_total > 0 ? round(100 * n_suspect / n_total, digits=1) : 0.0
println("  All: $n_total, Clean: $n_clean, Suspect: $n_suspect ($(pct)%) [$(round(time() - t0, digits=1))s]")

df_qc_all = to_dataframe(qc_all_obs)
df_qc_clean = to_dataframe(qc_clean_obs)
clean_ts = Set(df_qc_clean.timestamp)
df_qc_suspect = filter(r -> !(r.timestamp in clean_ts), df_qc_all)

# ---------------------------------------------------------------------------
# 4. Panel 4 data: extreme event comparison
# ---------------------------------------------------------------------------

println("\nFetching extreme event data...")
event_results = Dict{Symbol, NamedTuple}()
for (key, ev) in pairs(EVENTS)
	println("  $(ev.label)...")
	result = fetch_event(client, cemaden, ev)
	if result !== nothing
		event_results[key] = result
	end
end

if isempty(event_results)
	error("Neither extreme event returned data. Check station availability and date ranges.")
end

best_key, best_result = first(sort(collect(event_results), by=kv -> kv.second.peak, rev=true))
df_event = best_result.df
event_label = best_result.label
println("\n  → Selected: $event_label (peak $(round(best_result.peak, digits=1)) mm/h)")
for (key, res) in event_results
	key == best_key && continue
	println("    (alternative: $(res.label) — peak $(round(res.peak, digits=1)) mm/h)")
end

# ---------------------------------------------------------------------------
# 5. Build the figure
# ---------------------------------------------------------------------------

println("\nBuilding figure...")
colors = Makie.wong_colors()

fig = Figure(size=(1600, 1800), fontsize=14)

# Supertitle — Atlantic Cloud as the service, all three DOIs for provenance
supertitle = Label(fig[1, 1, Top()],
	"Atlantic Cloud — Quality-Controlled Brazilian Rainfall Data\n" *
	"Data: 10.5281/zenodo.19427080 · Pipeline: 10.5281/zenodo.19427280 · Source: 10.5281/zenodo.18883358",
	fontsize=16, padding=(0, 0, 20, 0))

# ---- Panel 1: Station coverage map ----

ax1 = Axis(fig[1, 1],
	xlabel="Longitude (°)",
	ylabel="Latitude (°)",
	aspect=DataAspect(),
)
xlims!(ax1, -76, -28)
ylims!(ax1, -35, 6)

println("  Drawing state boundaries...")
plot_brazil_boundaries!(ax1)

lines!(ax1,
	[SF_BOUNDS.lon_min, SF_BOUNDS.lon_max, SF_BOUNDS.lon_max,
	 SF_BOUNDS.lon_min, SF_BOUNDS.lon_min],
	[SF_BOUNDS.lat_min, SF_BOUNDS.lat_min, SF_BOUNDS.lat_max,
	 SF_BOUNDS.lat_max, SF_BOUNDS.lat_min],
	color=:red, linewidth=1.5, linestyle=:dash,
	label="São Francisco basin")

net_order = sort(collect(NETWORK_COLORS), by=k -> get(source_counts, k[1], 0), rev=true)
for (net, color) in net_order
	subset = filter(r -> !ismissing(r.source) && r.source == net, df_br)
	nrow(subset) == 0 && continue
	scatter!(ax1, subset.longitude_deg, subset.latitude_deg,
		markersize=4, color=(color, 0.8),
		label="$net ($(nrow(subset)))")
end

axislegend(ax1, position=:lb, labelsize=11, framevisible=true,
	backgroundcolor=(:white, 0.85), padding=(8, 8, 6, 6))

# ---- Panel 2: Monthly rainfall climatology ----

month_labels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

ax2 = Axis(fig[2, 1],
	title="(b) Wet-Dry Seasonality — São Francisco Basin, $(first(CLIM_YEARS))–$(last(CLIM_YEARS))",
	xlabel="Month",
	ylabel="Mean Daily Precipitation (mm)",
	xticks=(1:12, month_labels),
)

if nrow(monthly) > 0
	barplot!(ax2, monthly.month_num, monthly.precip_mean,
		color=colors[1], strokewidth=0.5, strokecolor=:black)
	errorbars!(ax2, monthly.month_num, monthly.precip_mean, monthly.precip_std,
		color=:black, whiskerwidth=8)
end

# ---- Panel 3: QC filtering ----

qc_epoch = DateTime(2023, 1, 1)
qc_to_days(dt::DateTime) = Dates.value(dt - qc_epoch) / (1000 * 60 * 60 * 24)

qc_tick_dates = [DateTime(2023, m, d) for m in 1:3 for d in (1, 15)]
qc_tick_vals = [qc_to_days(d) for d in qc_tick_dates]
qc_tick_labels = [Dates.format(d, "d u") for d in qc_tick_dates]

ax3 = Axis(fig[3, 1],
	title="(c) QC Pipeline Flags $(round(Int, pct))% of Observations as Suspect — $qc_place",
	xlabel="Date (2023)",
	ylabel="Precipitation (mm)",
	xticks=(qc_tick_vals, qc_tick_labels),
	xticklabelrotation=π/6,
)

if nrow(df_qc_suspect) > 0
	scatter!(ax3, qc_to_days.(df_qc_suspect.timestamp), df_qc_suspect.precipitation_accum_mm,
		markersize=9, color=(:red, 0.5), marker=:xcross,
		label="Suspect ($(nrow(df_qc_suspect)))")
end
if nrow(df_qc_clean) > 0
	scatter!(ax3, qc_to_days.(df_qc_clean.timestamp), df_qc_clean.precipitation_accum_mm,
		markersize=8, color=colors[1],
		label="Clean ($(nrow(df_qc_clean)))")
end

axislegend(ax3, position=:rt, labelsize=11)

# ---- Panel 4: Extreme event ----
# Precipitation is discrete (accumulated per hour), not continuous — scatter only, no lines.

ev_epoch = DateTime(EVENTS[best_key].start)
ev_to_days(dt::DateTime) = Dates.value(dt - ev_epoch) / (1000 * 60 * 60 * 24)

ev_day_range = Dates.value(Date(EVENTS[best_key].stop) - Date(EVENTS[best_key].start))
ev_tick_dates = [DateTime(EVENTS[best_key].start) + Day(d) for d in 0:ev_day_range]
ev_tick_vals = [ev_to_days(d) for d in ev_tick_dates]
ev_tick_labels = [Dates.format(d, "d u") for d in ev_tick_dates]

peak_mm = round(Int, best_result.peak)

ax4 = Axis(fig[4, 1],
	title="(d) RS Floods, May 2024 — Up to $(peak_mm) mm/h at Hourly Resolution",
	xlabel="Date (UTC)",
	ylabel="Precipitation (mm)",
	xticks=(ev_tick_vals, ev_tick_labels),
	xticklabelrotation=π/6,
)

if nrow(df_event) > 0
	station_ids = collect(unique(skipmissing(df_event.station_id)))
	labels = disambiguated_labels(df_br, station_ids)
	for (i, sid) in enumerate(station_ids)
		sdf = sort(filter(r -> !ismissing(r.station_id) && r.station_id == sid, df_event),
			:timestamp)
		xs = ev_to_days.(sdf.timestamp)
		scatter!(ax4, xs, sdf.precipitation_accum_mm,
			markersize=8, color=(colors[mod1(i, 7)], 0.8),
			label=labels[i])
	end
	if length(station_ids) <= 5
		axislegend(ax4, position=:rt, labelsize=10)
	end
end

rowsize!(fig.layout, 1, Relative(0.40))
rowsize!(fig.layout, 2, Relative(0.20))
rowsize!(fig.layout, 3, Relative(0.20))
rowsize!(fig.layout, 4, Relative(0.20))

# ---------------------------------------------------------------------------
# 6. Save
# ---------------------------------------------------------------------------

mkpath("figures")
output_path = "figures/brazil_rainfall.png"
save(output_path, fig, px_per_unit=2)
println("\nSaved to $output_path")
println("Done!")
