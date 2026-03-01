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

struct AtlanticCloudError <: Exception
	message::String
end

Base.showerror(io::IO, e::AtlanticCloudError) = print(io, "AtlanticCloudError: ", e.message)

struct AtlanticCloudClient
	base_url::String
	api_key::String

	function AtlanticCloudClient(;
		base_url::String = DEFAULT_BASE_URL,
		api_key::String = "",
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

		new(base_url, resolved_key)
	end
end

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
	response = HTTP.get(url, ["X-API-Key" => client.api_key])
	return String(response.body)
end

function _build_query(params::Dict{String, String})
	isempty(params) && return ""
	"?" * join(["$(k)=$(v)" for (k, v) in params], "&")
end

function get_stations(client::AtlanticCloudClient;
	station_id::Union{String, Nothing} = nothing,
	source::Union{String, Nothing} = nothing,
)
	params = Dict{String, String}()
	!isnothing(station_id) && (params["station_id"] = station_id)
	!isnothing(source) && (params["source"] = source)

	raw = _get(client, "/meteorology/api/v1/stations" * _build_query(params))
	parsed = JSON3.read(raw)
	return [Station(s) for s in parsed.data]
end

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
	parsed = JSON3.read(raw)
	return [Observation(o) for o in parsed.data]
end

export AtlanticCloudClient, AtlanticCloudError, Station, get_stations, Observation,
	get_observations, VALID_METRICS

end
