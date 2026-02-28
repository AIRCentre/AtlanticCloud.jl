module AtlanticCloud

using HTTP

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

function _get(client::AtlanticCloudClient, path::String)
    url = client.base_url * path
    response = HTTP.get(url, ["X-API-Key" => client.api_key])
    return String(response.body)
end

export AtlanticCloudClient, AtlanticCloudError

end