# test/test_helpers.jl — Shared test infrastructure for AtlanticCloud.jl
#
# Include this file in runtests.jl before any test sets that need it.

using AtlanticCloud

"""
    make_mock_client(fixture_path::String) -> AtlanticCloudClient

Create a mock client that returns the same fixture data for every request.
This is the original v0.1 helper — kept for backward compatibility.
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

Create a mock client that returns different fixture data depending on the
`station_id` query parameter in the request URL.

# Arguments
- `station_fixtures`: Maps station ID → fixture file path. When a request
  includes `station_id=X` and X is a key, that fixture is returned.
- `default_fixture`: Fixture file path used when the URL has no `station_id`
  parameter, or when the station ID isn't in `station_fixtures`.
- `error_stations`: Set of station IDs that should trigger an error.
  When a request includes `station_id=X` and X is in this set, the mock
  throws an error that `_get` wraps as `AtlanticCloudError`.

# Example
```julia
client = make_multi_mock_client(
    station_fixtures=Dict(
        "11217160" => "test/fixtures/observations.json",
        "1200535"  => "test/fixtures/observations_multi.json",
    ),
    default_fixture="test/fixtures/observations_empty.json",
    error_stations=Set(["BADSTATION"]),
)
```
"""
function make_multi_mock_client(;
    station_fixtures::Dict{String, String} = Dict{String, String}(),
    default_fixture::String = "",
    error_stations::Set{String} = Set{String}(),
)
    function mock_get(url, headers)
        # Extract station_id from query string
        station_id = nothing
        if occursin("station_id=", url)
            m = match(r"station_id=([^&]+)", url)
            if m !== nothing
                station_id = m.captures[1]
            end
        end

        # Simulate error for specific stations
        if station_id !== nothing && station_id in error_stations
            error("Simulated API error for station $station_id")
        end

        # Return station-specific fixture or default
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

# ---------------------------------------------------------------------------
# DataFrame test helpers (for use with issue #13)
# ---------------------------------------------------------------------------

"""
    check_dataframe(df, expected_cols::Vector{Symbol}, expected_nrow::Int;
        expected_types::Dict{Symbol, Type} = Dict())

Verify that a DataFrame has the expected columns, row count, and optionally
column types. Returns a list of failure messages (empty if all checks pass).

Designed to be used inside @testset blocks:
```julia
failures = check_dataframe(df, [:station_id, :place], 6)
@test isempty(failures)
```
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
# GeoInterface test helpers (for use with issue #14)
# ---------------------------------------------------------------------------

"""
    check_geointerface_point(GI, geom, expected_x::Float64, expected_y::Float64)

Verify that a geometry object correctly implements the GeoInterface.jl
PointTrait protocol. Returns a list of failure messages (empty if all
checks pass).

`GI` is the GeoInterface module — pass it explicitly so this helper
works without GeoInterface being a package dependency (it won't be
until issue #14 adds it).

Checks:
- `geomtrait` returns `PointTrait()`
- `ncoord` returns 2
- `getcoord(_, 1)` returns expected_x (longitude)
- `getcoord(_, 2)` returns expected_y (latitude)
- `ngeom` returns 0

```julia
import GeoInterface as GI
failures = check_geointerface_point(GI, station, -25.0917, 36.9542)
@test isempty(failures)
```
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
