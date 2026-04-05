# test/test_helpers.jl — Shared test infrastructure for AtlanticCloud.jl
#
# Include this file in runtests.jl before any test sets that need it.

using AtlanticCloud

"""
    make_mock_client(fixture_path::String) -> AtlanticCloudClient

Create a mock client that returns the same fixture data for every request.
The original v0.1 helper — kept for simple cases where all requests
return the same fixture.
"""
function make_mock_client(fixture_path::String)
    fixture = read(fixture_path, String)
    mock_response = (url, headers) -> (body = Vector{UInt8}(fixture),)
    return AtlanticCloudClient(api_key="testkey", http_get=mock_response)
end

"""
    make_multi_mock_client(;
        station_fixtures::Dict{String, String} = Dict(),
        default_fixture::String = "",
        error_stations::Set{String} = Set{String}(),
    ) -> AtlanticCloudClient

Create a mock client that routes responses based on the `station_id` query
parameter. Used for PT observation tests where different stations return
different fixtures.

# Arguments
- `station_fixtures`: Maps station ID → fixture file path.
- `default_fixture`: Fallback when station_id is absent or not in the map.
- `error_stations`: Station IDs that trigger a simulated network error.
"""
function make_multi_mock_client(;
    station_fixtures::Dict{String, String} = Dict{String, String}(),
    default_fixture::String = "",
    error_stations::Set{String} = Set{String}(),
)
    function mock_get(url, headers)
        station_id = nothing
        if occursin("station_id=", url)
            m = match(r"station_id=([^&]+)", url)
            if m !== nothing
                station_id = m.captures[1]
            end
        end

        if station_id !== nothing && station_id in error_stations
            error("Simulated API error for station $station_id")
        end

        fixture_path = if station_id !== nothing && haskey(station_fixtures, station_id)
            station_fixtures[station_id]
        elseif !isempty(default_fixture)
            default_fixture
        else
            error("No fixture configured for station_id=$station_id and no default_fixture set")
        end

        fixture = read(fixture_path, String)
        return (body = Vector{UInt8}(fixture),)
    end

    return AtlanticCloudClient(api_key="testkey", http_get=mock_get)
end

"""
    make_routing_mock_client(;
        stations_fixture = "",
        observations_fixture = "",
        br_fixture = "",
        br_station_fixtures = Dict(),
        error_stations = Set{String}(),
    ) -> AtlanticCloudClient

Create a mock client that routes responses based on the URL path, then
by query parameters within that path. Supports both PT and BR endpoints.

# Routing logic
1. URL contains `/observations/br` → BR observation path:
   - Check `br_station_fixtures` for a station_id-specific fixture.
   - Fall back to `br_fixture`.
2. URL contains `/observations` (not `/br`) → `observations_fixture`.
3. URL contains `/stations` → `stations_fixture`.

# Arguments
- `stations_fixture`: Fixture for `/stations` requests.
- `observations_fixture`: Fixture for PT `/observations` requests.
- `br_fixture`: Default fixture for `/observations/br` requests.
- `br_station_fixtures`: Maps station ID → fixture for BR requests.
- `error_stations`: Station IDs that trigger a simulated network error
  (applies to both PT and BR observation endpoints).
"""
function make_routing_mock_client(;
    stations_fixture::String = "",
    observations_fixture::String = "",
    br_fixture::String = "",
    br_station_fixtures::Dict{String, String} = Dict{String, String}(),
    error_stations::Set{String} = Set{String}(),
)
    function mock_get(url, headers)
        # Extract station_id if present
        station_id = nothing
        if occursin("station_id=", url)
            m = match(r"station_id=([^&]+)", url)
            if m !== nothing
                station_id = m.captures[1]
            end
        end

        if station_id !== nothing && station_id in error_stations
            error("Simulated API error for station $station_id")
        end

        # Route by URL path, then by query params
        fixture_path = if occursin("/observations/br", url)
            if station_id !== nothing && haskey(br_station_fixtures, station_id)
                br_station_fixtures[station_id]
            elseif !isempty(br_fixture)
                br_fixture
            else
                error("No BR fixture configured for URL: $url")
            end
        elseif occursin("/observations", url)
            if !isempty(observations_fixture)
                observations_fixture
            else
                error("No observations fixture configured for URL: $url")
            end
        elseif occursin("/stations", url)
            if !isempty(stations_fixture)
                stations_fixture
            else
                error("No stations fixture configured for URL: $url")
            end
        else
            error("Unrecognised URL path: $url")
        end

        fixture = read(fixture_path, String)
        return (body = Vector{UInt8}(fixture),)
    end

    return AtlanticCloudClient(api_key="testkey", http_get=mock_get)
end

# ---------------------------------------------------------------------------
# DataFrame test helpers
# ---------------------------------------------------------------------------

"""
    check_dataframe(df, expected_cols::Vector{Symbol}, expected_nrow::Int;
        expected_types::Dict{Symbol, Type} = Dict())

Verify that a DataFrame has the expected columns, row count, and optionally
column types. Returns a list of failure messages (empty if all checks pass).
"""
function check_dataframe(df, expected_cols::Vector{Symbol}, expected_nrow::Int;
    expected_types::Dict{Symbol, Type} = Dict{Symbol, Type}())

    failures = String[]

    actual_cols = Symbol.(names(df))
    if Set(actual_cols) != Set(expected_cols)
        missing_cols = setdiff(Set(expected_cols), Set(actual_cols))
        extra_cols = setdiff(Set(actual_cols), Set(expected_cols))
        !isempty(missing_cols) && push!(failures, "Missing columns: $(join(missing_cols, ", "))")
        !isempty(extra_cols) && push!(failures, "Unexpected columns: $(join(extra_cols, ", "))")
    end

    if nrow(df) != expected_nrow
        push!(failures, "Expected $expected_nrow rows, got $(nrow(df))")
    end

    for (col, expected_type) in expected_types
        if col in actual_cols
            actual_type = eltype(df[!, col])
            if !(actual_type <: expected_type)
                push!(failures, "Column $col: expected <: $expected_type, got $actual_type")
            end
        end
    end

    return failures
end

# ---------------------------------------------------------------------------
# GeoInterface test helpers
# ---------------------------------------------------------------------------

"""
    check_geointerface_point(GI, geom, expected_x::Float64, expected_y::Float64)

Verify that a geometry implements GeoInterface.jl PointTrait correctly.
Returns a list of failure messages (empty if all checks pass).
"""
function check_geointerface_point(GI, geom, expected_x::Float64, expected_y::Float64)
    failures = String[]

    trait = GI.geomtrait(geom)
    if trait != GI.PointTrait()
        push!(failures, "geomtrait: expected PointTrait(), got $trait")
    end

    nc = GI.ncoord(trait, geom)
    if nc != 2
        push!(failures, "ncoord: expected 2, got $nc")
    end

    x = GI.getcoord(trait, geom, 1)
    if !(x ≈ expected_x)
        push!(failures, "getcoord(_, 1) [x/lon]: expected $expected_x, got $x")
    end

    y = GI.getcoord(trait, geom, 2)
    if !(y ≈ expected_y)
        push!(failures, "getcoord(_, 2) [y/lat]: expected $expected_y, got $y")
    end

    ng = GI.ngeom(trait, geom)
    if ng != 0
        push!(failures, "ngeom: expected 0, got $ng")
    end

    return failures
end
