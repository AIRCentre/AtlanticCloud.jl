module AtlanticCloud

using HTTP
using JSON3
using Dates

const DEFAULT_BASE_URL = "https://services.aircentre.org"

const VALID_METRICS = Set([
	"wind_speed_kmh",
	"temperature_c",
	"radiation_kjm2",
	"wind_direction_bin",
	"precipitation_accum_mm",
	"rel_humidity_pctg",
	"pressure_hpa",
])

"""
    AtlanticCloudError(message)

Exception thrown by AtlanticCloud when an API request fails.

Catch this type to handle all errors from the package in one place.
"""
struct AtlanticCloudError <: Exception
	message::String
end

Base.showerror(io::IO, e::AtlanticCloudError) = print(io, "AtlanticCloudError: ", e.message)

"""
    AtlanticCloudClient(; api_key, base_url)

Client for the AIR Centre Atlantic Cloud API.

The API key is resolved in this order:
1. Explicit `api_key` keyword argument
2. `ATLANTICCLOUD_API_KEY` environment variable
3. Error with registration URL if neither is present

# Example
```julia
client = AtlanticCloudClient(api_key="your_key")
```

Register at: https://services.aircentre.org/access/account
"""
struct AtlanticCloudClient
	base_url::String
	api_key::String
	http_get::Function

	function AtlanticCloudClient(;
		base_url::String = DEFAULT_BASE_URL,
		api_key::String = "",
		http_get::Function = HTTP.get,
	)
		resolved_key = if !isempty(api_key)
			api_key
		elseif haskey(ENV, "ATLANTICCLOUD_API_KEY")
			ENV["ATLANTICCLOUD_API_KEY"]
		else
			throw(AtlanticCloudError(
				"No API key provided. Pass api_key= directly or set the " *
				"ATLANTICCLOUD_API_KEY environment variable. " *
				"Register at https://services.aircentre.org/access/account",
			))
		end

		new(base_url, resolved_key, http_get)
	end
end

"""
    Station

A meteorological station in the AIR Centre network.

# Fields
- `station_id`: Unique identifier
- `place`: Human-readable location name
- `latitude_deg`: Latitude in decimal degrees
- `longitude_deg`: Longitude in decimal degrees
- `source`: Data source (e.g. `"IPMA"`, `"RHA"`, `"AIRC"`)
"""
struct Station
	station_id::String
	place::String
	latitude_deg::Float64
	longitude_deg::Float64
	source::String

	function Station(obj::JSON3.Object)
		new(
			obj[:station_id],
			obj[:place],
			obj[:latitude_deg],
			obj[:longitude_deg],
			obj[:source],
		)
	end
end

"""
    Observation

A single hourly meteorological observation from a station.

# Fields
- `station_id`: Station identifier
- `timestamp`: Observation time as `DateTime`
- `wind_speed_kmh`: Wind speed in km/h
- `temperature_c`: Air temperature in °C
- `radiation_kjm2`: Solar radiation in kJ/m²
- `wind_direction_bin`: Wind direction bin index (integer)
- `precipitation_accum_mm`: Accumulated precipitation in mm
- `rel_humidity_pctg`: Relative humidity as percentage
- `pressure_hpa`: Atmospheric pressure in hPa (may be `nothing`)

All metric fields are `Union{Float64, Nothing}` except `wind_direction_bin`
which is `Union{Int, Nothing}`.
"""
struct Observation
	station_id::String
	timestamp::DateTime
	wind_speed_kmh::Union{Float64, Nothing}
	temperature_c::Union{Float64, Nothing}
	radiation_kjm2::Union{Float64, Nothing}
	wind_direction_bin::Union{Int, Nothing}
	precipitation_accum_mm::Union{Float64, Nothing}
	rel_humidity_pctg::Union{Float64, Nothing}
	pressure_hpa::Union{Float64, Nothing}

	function Observation(obj::JSON3.Object)
		new(
			obj[:station_id],
			DateTime(obj[:timestamp], dateformat"yyyy-mm-dd HH:MM:SS"),
			haskey(obj, :wind_speed_kmh) ? Float64(obj[:wind_speed_kmh]) : nothing,
			haskey(obj, :temperature_c) ? Float64(obj[:temperature_c]) : nothing,
			haskey(obj, :radiation_kjm2) ? Float64(obj[:radiation_kjm2]) : nothing,
			haskey(obj, :wind_direction_bin) ? Int(obj[:wind_direction_bin]) : nothing,
			haskey(obj, :precipitation_accum_mm) ? Float64(obj[:precipitation_accum_mm]) : nothing,
			haskey(obj, :rel_humidity_pctg) ? Float64(obj[:rel_humidity_pctg]) : nothing,
			haskey(obj, :pressure_hpa) ? Float64(obj[:pressure_hpa]) : nothing,
		)
	end
end

function _get(client::AtlanticCloudClient, path::String)
	url = client.base_url * path
	try
		response = client.http_get(url, ["X-API-Key" => client.api_key])
		return String(response.body)
	catch e
		if e isa HTTP.Exceptions.StatusError
			throw(AtlanticCloudError(
				"HTTP $(e.status) error for $(path): $(String(e.response.body))",
			))
		else
			throw(AtlanticCloudError(
				"Network error for $(path): $(sprint(showerror, e))",
			))
		end
	end
end

function _parse(raw::String, path::String)
	try
		return JSON3.read(raw)
	catch e
		throw(AtlanticCloudError(
			"Failed to parse response from $(path): $(sprint(showerror, e))",
		))
	end
end

function _build_query(params::Dict{String, String})
	isempty(params) && return ""
	"?" * join(["$(k)=$(v)" for (k, v) in params], "&")
end

"""
    get_stations(client; station_id, source)

Retrieve meteorological stations from the AIR Centre network.

# Arguments
- `client`: An `AtlanticCloudClient` instance
- `station_id`: Filter by station ID (optional)
- `source`: Filter by data source, e.g. `"IPMA"`, `"RHA"` (optional)

# Returns
`Vector{Station}`

# Example
```julia
client = AtlanticCloudClient(api_key="your_key")
stations = get_stations(client)
ipma = get_stations(client, source="IPMA")
```
"""
function get_stations(client::AtlanticCloudClient;
	station_id::Union{String, Nothing} = nothing,
	source::Union{String, Nothing} = nothing,
)
	params = Dict{String, String}()
	!isnothing(station_id) && (params["station_id"] = station_id)
	!isnothing(source) && (params["source"] = source)

	raw = _get(client, "/meteorology/api/v1/stations" * _build_query(params))
	parsed = _parse(raw, "/meteorology/api/v1/stations")
	return [Station(s) for s in parsed.data]
end

"""
    get_observations(client, station_id; start_date, end_date, metrics)

Retrieve hourly meteorological observations for a station.

# Arguments
- `client`: An `AtlanticCloudClient` instance
- `station_id`: Required station identifier
- `start_date`: Start of date range as `Date` (optional)
- `end_date`: End of date range as `Date` (optional)
- `metrics`: Vector of metric names to include (optional). See `VALID_METRICS`.

# Returns
`Vector{Observation}`

# Example
```julia
using Dates
client = AtlanticCloudClient(api_key="your_key")
obs = get_observations(client, "11217160",
    start_date=Date(2024,1,1),
    end_date=Date(2024,1,31),
    metrics=["temperature_c", "wind_speed_kmh"])
```
"""
function get_observations(
	client::AtlanticCloudClient,
	station_id::String;
	start_date::Union{Date, Nothing} = nothing,
	end_date::Union{Date, Nothing} = nothing,
	metrics::Union{Vector{String}, Nothing} = nothing,
)
	params = Dict{String, String}()
	params["station_id"] = station_id
	!isnothing(start_date) && (params["start_date"] = Dates.format(start_date, "yyyy-mm-dd"))
	!isnothing(end_date) && (params["end_date"] = Dates.format(end_date, "yyyy-mm-dd"))

	if !isnothing(metrics)
		invalid = setdiff(Set(metrics), VALID_METRICS)
		if !isempty(invalid)
			throw(AtlanticCloudError(
				"Invalid metrics: $(join(invalid, ", ")). " *
				"Valid options are: $(join(sort(collect(VALID_METRICS)), ", "))",
			))
		end
		params["include_metrics"] = join(metrics, ",")
	end

	raw = _get(client, "/meteorology/api/v1/observations" * _build_query(params))
	parsed = _parse(raw, "/meteorology/api/v1/observations")
	return [Observation(o) for o in parsed.data]
end

export AtlanticCloudClient, AtlanticCloudError, Station, get_stations, Observation,
	get_observations, VALID_METRICS

end
