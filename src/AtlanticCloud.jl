module AtlanticCloud

using HTTP
using JSON3

const DEFAULT_BASE_URL = "https://services.aircentre.org"

struct AtlanticCloudError <: Exception
    message::String
end

Base.showerror(io::IO, e::AtlanticCloudError) = print(io, "AtlanticCloudError: ", e.message)

struct AtlanticCloudClient
    base_url::String
    api_key::String

    function AtlanticCloudClient(;
        base_url::String = DEFAULT_BASE_URL,
        api_key::String = ""
    )
        resolved_key = if !isempty(api_key)
            api_key
        elseif haskey(ENV, "ATLANTICCLOUD_API_KEY")
            ENV["ATLANTICCLOUD_API_KEY"]
        else
            throw(AtlanticCloudError(
                "No API key provided. Pass api_key= directly or set the " *
                "ATLANTICCLOUD_API_KEY environment variable. " *
                "Register at https://services.aircentre.org/access/account"
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
            obj[:source]
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
    source::Union{String, Nothing} = nothing
)
    params = Dict{String, String}()
    !isnothing(station_id) && (params["station_id"] = station_id)
    !isnothing(source) && (params["source"] = source)

    raw = _get(client, "/meteorology/api/v1/stations" * _build_query(params))
    parsed = JSON3.read(raw)
    return [Station(s) for s in parsed.data]
end

export AtlanticCloudClient, AtlanticCloudError, Station, get_stations

end