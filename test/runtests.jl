using Test
using Dates
using DataFrames
using AtlanticCloud
import GeoInterface as GI

include("test_helpers.jl")

@testset "AtlanticCloud" begin

	@testset "AtlanticCloudClient" begin

		@test AtlanticCloudClient(api_key = "testkey").api_key == "testkey"

		withenv("ATLANTICCLOUD_API_KEY" => "envkey") do
			@test AtlanticCloudClient().api_key == "envkey"
		end

		withenv("ATLANTICCLOUD_API_KEY" => nothing) do
			@test_throws AtlanticCloudError AtlanticCloudClient()
		end

	end

	@testset "Station" begin

		raw = read("test/fixtures/stations.json", String)
		parsed = AtlanticCloud.JSON3.read(raw)
		stations = [Station(s) for s in parsed.data]

		@test length(stations) > 0
		@test stations[1].station_id == "11217160"
		@test stations[1].place == "Santa Maria / Praia Formosa (DRAAC)"
		@test stations[1].latitude_deg ≈ 36.9542
		@test stations[1].longitude_deg ≈ -25.0917
		@test stations[1].source == "IPMA"
		@test all(s -> s isa Station, stations)
		@test all(s -> !isempty(something(s.station_id, "")), stations)

	end

	@testset "Station with nothing fields" begin

		json_null_id = AtlanticCloud.JSON3.read("""
			{"station_id": null, "place": "Test Place", "latitude_deg": 38.0, "longitude_deg": -9.0, "source": "IPMA"}
		""")
		s = Station(json_null_id)
		@test s.station_id === nothing
		@test s.place == "Test Place"
		@test s.source == "IPMA"

		json_null_place = AtlanticCloud.JSON3.read("""
			{"station_id": "12345", "place": null, "latitude_deg": 38.0, "longitude_deg": -9.0, "source": "IPMA"}
		""")
		s2 = Station(json_null_place)
		@test s2.station_id == "12345"
		@test s2.place === nothing

		json_null_source = AtlanticCloud.JSON3.read("""
			{"station_id": "12345", "place": "Test", "latitude_deg": 38.0, "longitude_deg": -9.0, "source": null}
		""")
		s3 = Station(json_null_source)
		@test s3.source === nothing

		json_all_null = AtlanticCloud.JSON3.read("""
			{"station_id": null, "place": null, "latitude_deg": 38.0, "longitude_deg": -9.0, "source": null}
		""")
		s4 = Station(json_all_null)
		@test s4.station_id === nothing
		@test s4.place === nothing
		@test s4.source === nothing
		@test s4.latitude_deg ≈ 38.0
		@test s4.longitude_deg ≈ -9.0

	end

	@testset "Observation" begin

		raw = read("test/fixtures/observations.json", String)
		parsed = AtlanticCloud.JSON3.read(raw)
		observations = [Observation(o) for o in parsed.data]

		@test length(observations) > 0
		@test all(o -> o isa Observation, observations)

		obs = observations[1]
		@test obs.station_id == "11217160"
		@test obs.timestamp == DateTime(2024, 1, 1, 0, 0, 0)
		@test obs.wind_speed_kmh isa Float64
		@test obs.temperature_c isa Float64
		@test obs.radiation_kjm2 isa Float64
		@test obs.wind_direction_bin isa Int
		@test obs.pressure_hpa === nothing

	end

	@testset "Observation with nothing fields" begin

		json_null_id = AtlanticCloud.JSON3.read("""
			{"station_id": null, "timestamp": "2024-01-01 00:00:00", "temperature_c": 15.0}
		""")
		o = Observation(json_null_id)
		@test o.station_id === nothing
		@test o.timestamp == DateTime(2024, 1, 1, 0, 0, 0)
		@test o.temperature_c == 15.0

		json_null_id_no_metrics = AtlanticCloud.JSON3.read("""
			{"station_id": null, "timestamp": "2024-01-01 12:00:00"}
		""")
		o2 = Observation(json_null_id_no_metrics)
		@test o2.station_id === nothing
		@test o2.timestamp == DateTime(2024, 1, 1, 12, 0, 0)
		@test o2.temperature_c === nothing
		@test o2.pressure_hpa === nothing

	end

	@testset "get_observations" begin

		raw = read("test/fixtures/observations.json", String)
		parsed = AtlanticCloud.JSON3.read(raw)
		observations = [Observation(o) for o in parsed.data]

		@test length(observations) > 0
		@test observations[1].station_id == "11217160"
		@test observations[1].timestamp == DateTime(2024, 1, 1, 0, 0, 0)
		@test observations[end].timestamp == DateTime(2024, 1, 3, 0, 0, 0)

	end

	@testset "get_observations — date parameters" begin

		client = make_mock_client("test/fixtures/observations.json")

		obs = get_observations(client, "11217160",
			start_date=Date(2024, 1, 1), end_date=Date(2024, 1, 3))
		@test length(obs) > 0

		obs2 = get_observations(client, "11217160",
			start_date=DateTime(2024, 1, 1), end_date=DateTime(2024, 1, 3))
		@test length(obs2) > 0

		obs3 = get_observations(client, "11217160",
			start_date=Date(2024, 1, 1), end_date=DateTime(2024, 1, 3, 12, 0, 0))
		@test length(obs3) > 0

		obs4 = get_observations(client, "11217160",
			start_date=DateTime(2024, 1, 1, 6, 30, 0))
		@test length(obs4) > 0

		@test_throws ArgumentError get_observations(client, "11217160",
			start_date=Date(2024, 2, 1), end_date=Date(2024, 1, 1))

		@test_throws ArgumentError get_observations(client, "11217160",
			start_date=DateTime(2024, 2, 1), end_date=DateTime(2024, 1, 1))

		obs5 = get_observations(client, "11217160",
			start_date=Date(2024, 1, 1), end_date=Date(2024, 1, 1))
		@test length(obs5) > 0

	end

	@testset "VALID_METRICS" begin
		@test "temperature_c" in VALID_METRICS
		@test "pressure_hpa" in VALID_METRICS
		@test !("invalid_metric" in VALID_METRICS)
	end

	@testset "Error handling" begin

		@testset "_get HTTP errors" begin
			client = AtlanticCloudClient(api_key = "invalid")
			@test_throws AtlanticCloudError get_stations(client)
		end

		@testset "_parse JSON errors" begin
			@test_throws AtlanticCloudError AtlanticCloud._parse("not valid json", "/test")
		end

		@testset "_extract_data with API error response" begin
			error_json = AtlanticCloud.JSON3.read("""{"error": "date range too large"}""")
			@test_throws AtlanticCloudError AtlanticCloud._extract_data(error_json, "/test")

			try
				AtlanticCloud._extract_data(error_json, "/test")
			catch e
				@test e isa AtlanticCloudError
				@test occursin("date range too large", e.message)
			end
		end

		@testset "_extract_data with missing data field" begin
			bad_json = AtlanticCloud.JSON3.read("""{"something": "else"}""")
			@test_throws AtlanticCloudError AtlanticCloud._extract_data(bad_json, "/test")
		end

		@testset "_extract_data with valid response" begin
			valid_json = AtlanticCloud.JSON3.read("""{"data": []}""")
			data = AtlanticCloud._extract_data(valid_json, "/test")
			@test length(data) == 0
		end

	end

	@testset "Integration tests (fixture-based)" begin

		@testset "get_stations with mock" begin
			client = make_mock_client("test/fixtures/stations.json")
			stations = get_stations(client)
			@test length(stations) > 0
			@test stations[1] isa Station
			@test stations[1].station_id == "11217160"
		end

		@testset "get_observations with mock" begin
			client = make_mock_client("test/fixtures/observations.json")
			observations = get_observations(client, "11217160")
			@test length(observations) > 0
			@test observations[1] isa Observation
			@test observations[1].station_id == "11217160"
			@test observations[1].pressure_hpa === nothing
		end

		@testset "API error response handled gracefully" begin
			client = make_mock_client("test/fixtures/error_response.json")
			@test_throws AtlanticCloudError get_observations(client, "11217160")
			@test_throws AtlanticCloudError get_stations(client)
		end

	end

	@testset "Multi-station fixtures" begin

		@testset "stations_multi.json" begin
			raw = read("test/fixtures/stations_multi.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			stations = [Station(s) for s in parsed.data]

			@test length(stations) == 6
			@test all(s -> s isa Station, stations)

			ids = [s.station_id for s in stations]
			@test "11217160" in ids
			@test "1200521" in ids
			@test "1200535" in ids

			sources = Set(s.source for s in stations)
			@test "IPMA" in sources
			@test "RHA" in sources
			@test "DSCIG" in sources
		end

		@testset "observations_multi.json" begin
			raw = read("test/fixtures/observations_multi.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			observations = [Observation(o) for o in parsed.data]

			@test length(observations) == 9

			station_ids = Set(o.station_id for o in observations)
			@test length(station_ids) == 3
			@test "11217160" in station_ids
			@test "1200535" in station_ids
			@test "1200533" in station_ids

			lisboa_obs = filter(o -> o.station_id == "1200535", observations)
			@test all(o -> o.pressure_hpa !== nothing, lisboa_obs)

			azores_obs = filter(o -> o.station_id == "11217160", observations)
			@test all(o -> o.pressure_hpa === nothing, azores_obs)

			sagres_obs = filter(o -> o.station_id == "1200533", observations)
			@test all(o -> o.temperature_c !== nothing, sagres_obs)
			@test all(o -> o.wind_speed_kmh === nothing, sagres_obs)
		end

		@testset "observations_empty.json" begin
			raw = read("test/fixtures/observations_empty.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			observations = [Observation(o) for o in parsed.data]

			@test length(observations) == 0
		end

	end

	@testset "Multi-mock client" begin

		@testset "per-station fixture routing" begin
			client = make_multi_mock_client(
				station_fixtures=Dict(
					"11217160" => "test/fixtures/observations.json",
				),
				default_fixture="test/fixtures/observations_empty.json",
			)

			obs = get_observations(client, "11217160")
			@test length(obs) == 49
			@test obs[1].station_id == "11217160"

			obs_empty = get_observations(client, "UNKNOWN")
			@test length(obs_empty) == 0
		end

		@testset "error station handling" begin
			client = make_multi_mock_client(
				default_fixture="test/fixtures/observations_empty.json",
				error_stations=Set(["BADSTATION"]),
			)

			@test_throws AtlanticCloudError get_observations(client, "BADSTATION")

			obs = get_observations(client, "GOODSTATION")
			@test length(obs) == 0
		end

		@testset "stations endpoint (no station_id)" begin
			client = make_multi_mock_client(
				default_fixture="test/fixtures/stations_multi.json",
			)

			stations = get_stations(client)
			@test length(stations) == 6
		end

	end

	@testset "get_observations_bulk" begin

		@testset "basic multi-station fetch" begin
			client = make_multi_mock_client(
				station_fixtures=Dict(
					"11217160" => "test/fixtures/observations.json",
					"1200535" => "test/fixtures/observations_multi.json",
				),
				default_fixture="test/fixtures/observations_empty.json",
			)

			obs = get_observations_bulk(client,
				["11217160", "1200535", "UNKNOWN"],
				progress=false)

			@test length(obs) == 58
			@test all(o -> o isa Observation, obs)

			ids = Set(o.station_id for o in obs)
			@test "11217160" in ids
			@test "1200535" in ids
		end

		@testset "empty station list" begin
			client = make_mock_client("test/fixtures/observations.json")
			obs = get_observations_bulk(client, String[], progress=false)
			@test length(obs) == 0
		end

		@testset "passes filter parameters" begin
			client = make_multi_mock_client(
				station_fixtures=Dict(
					"11217160" => "test/fixtures/observations.json",
				),
				default_fixture="test/fixtures/observations_empty.json",
			)

			obs = get_observations_bulk(client, ["11217160"],
				start_date=Date(2024, 1, 1),
				end_date=Date(2024, 1, 3),
				metrics=["temperature_c"],
				progress=false)
			@test length(obs) > 0
		end

		@testset "on_error = :warn (default)" begin
			client = make_multi_mock_client(
				station_fixtures=Dict(
					"11217160" => "test/fixtures/observations.json",
				),
				default_fixture="test/fixtures/observations_empty.json",
				error_stations=Set(["BADSTATION"]),
			)

			obs = get_observations_bulk(client,
				["11217160", "BADSTATION", "11217160"],
				progress=false)
			@test length(obs) == 98
		end

		@testset "on_error = :throw" begin
			client = make_multi_mock_client(
				default_fixture="test/fixtures/observations_empty.json",
				error_stations=Set(["BADSTATION"]),
			)

			@test_throws AtlanticCloudError get_observations_bulk(client,
				["BADSTATION"],
				on_error=:throw,
				progress=false)
		end

		@testset "on_error = :skip" begin
			client = make_multi_mock_client(
				station_fixtures=Dict(
					"11217160" => "test/fixtures/observations.json",
				),
				default_fixture="test/fixtures/observations_empty.json",
				error_stations=Set(["BADSTATION"]),
			)

			obs = get_observations_bulk(client,
				["BADSTATION", "11217160"],
				on_error=:skip,
				progress=false)
			@test length(obs) == 49
		end

		@testset "invalid on_error value" begin
			client = make_mock_client("test/fixtures/observations.json")

			@test_throws ArgumentError get_observations_bulk(client,
				["11217160"],
				on_error=:invalid,
				progress=false)
		end

	end

	@testset "GeoInterface traits — Station" begin

		raw = read("test/fixtures/stations_multi.json", String)
		parsed = AtlanticCloud.JSON3.read(raw)
		stations = [Station(s) for s in parsed.data]
		s = stations[1]

		@test GI.isgeometry(Station) == true
		@test GI.geomtrait(s) == GI.PointTrait()
		@test GI.ncoord(GI.PointTrait(), s) == 2
		@test GI.ngeom(GI.PointTrait(), s) == 0
		@test GI.getgeom(GI.PointTrait(), s, 1) === nothing

		@test GI.getcoord(GI.PointTrait(), s, 1) ≈ -25.0917
		@test GI.getcoord(GI.PointTrait(), s, 2) ≈ 36.9542

		@test GI.x(GI.PointTrait(), s) ≈ -25.0917
		@test GI.y(GI.PointTrait(), s) ≈ 36.9542

		failures = check_geointerface_point(GI, s, -25.0917, 36.9542)
		@test isempty(failures)

		lisboa = stations[5]
		@test GI.x(GI.PointTrait(), lisboa) ≈ -9.149722
		@test GI.y(GI.PointTrait(), lisboa) ≈ 38.719078

		@test all(s -> GI.geomtrait(s) == GI.PointTrait(), stations)

	end

	@testset "to_dataframe — Station" begin

		client = make_mock_client("test/fixtures/stations_multi.json")
		stations = get_stations(client)
		df = to_dataframe(stations)

		@test df isa DataFrame
		@test nrow(df) == 6
		@test ncol(df) == 11
		@test names(df) == ["station_id", "place", "latitude_deg", "longitude_deg", "source", "country", "state", "elevation_m", "responsible", "utc_offset", "temporal_resolution_min"]

		@test eltype(df.latitude_deg) == Float64
		@test eltype(df.longitude_deg) == Float64

		@test df.station_id[1] == "11217160"
		@test df.latitude_deg[1] ≈ 36.9542

		@test nonmissingtype(eltype(df.station_id)) == String
		@test nonmissingtype(eltype(df.place)) == String
		@test nonmissingtype(eltype(df.source)) == String

	end

	@testset "to_dataframe — Station with nothing fields" begin

		json = AtlanticCloud.JSON3.read("""
			{"data": [
				{"station_id": null, "place": "Test", "latitude_deg": 38.0, "longitude_deg": -9.0, "source": "IPMA"},
				{"station_id": "12345", "place": null, "latitude_deg": 39.0, "longitude_deg": -8.0, "source": null}
			]}
		""")
		stations = [Station(s) for s in json.data]
		df = to_dataframe(stations)

		@test nrow(df) == 2
		@test ismissing(df.station_id[1])
		@test df.place[1] == "Test"
		@test df.station_id[2] == "12345"
		@test ismissing(df.place[2])
		@test ismissing(df.source[2])

	end

	@testset "to_dataframe — Observation" begin

		client = make_mock_client("test/fixtures/observations_multi.json")
		obs = get_observations(client, "any")
		df = to_dataframe(obs)

		@test df isa DataFrame
		@test nrow(df) == 9
		@test ncol(df) == 9

		expected_cols = ["station_id", "timestamp", "wind_speed_kmh", "temperature_c",
			"radiation_kjm2", "wind_direction_bin", "precipitation_accum_mm",
			"rel_humidity_pctg", "pressure_hpa"]
		@test names(df) == expected_cols

		@test eltype(df.timestamp) == DateTime

		@test !ismissing(df.pressure_hpa[4])
		@test df.pressure_hpa[4] ≈ 1013.2
		@test ismissing(df.pressure_hpa[1])

		@test !ismissing(df.temperature_c[7])
		@test ismissing(df.wind_speed_kmh[7])
		@test ismissing(df.wind_direction_bin[7])

	end

	@testset "to_dataframe — empty vectors" begin

		df_stations = to_dataframe(Station[])
		@test df_stations isa DataFrame
		@test nrow(df_stations) == 0
		@test ncol(df_stations) == 11

		df_obs = to_dataframe(Observation[])
		@test df_obs isa DataFrame
		@test nrow(df_obs) == 0
		@test ncol(df_obs) == 9

	end

	@testset "to_dataframe — check_dataframe helper" begin

		client = make_mock_client("test/fixtures/stations_multi.json")
		stations = get_stations(client)
		df = to_dataframe(stations)

		failures = check_dataframe(df,
			[:station_id, :place, :latitude_deg, :longitude_deg, :source, :country, :state, :elevation_m, :responsible, :utc_offset, :temporal_resolution_min],
			6)
		@test isempty(failures)

	end

	# -----------------------------------------------------------------------
	# BR fixtures and routing mock (#21)
	# -----------------------------------------------------------------------

	@testset "BR fixtures — JSON structure" begin

		@testset "stations_br.json" begin
			raw = read("test/fixtures/stations_br.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			@test haskey(parsed, :data)
			@test length(parsed.data) == 6

			# All records have the extended 11-field shape
			for s in parsed.data
				@test haskey(s, :station_id)
				@test haskey(s, :latitude_deg)
				@test haskey(s, :longitude_deg)
				@test haskey(s, :source)
				@test haskey(s, :country)
				@test haskey(s, :state)
				@test haskey(s, :elevation_m)
				@test haskey(s, :responsible)
				@test haskey(s, :utc_offset)
				@test haskey(s, :temporal_resolution_min)
			end

			# All are Brazilian
			@test all(s -> s[:country] == "BR", parsed.data)

			# Network diversity (one per network)
			sources = Set(s[:source] for s in parsed.data)
			@test "Telemetria" in sources
			@test "CEMADEN" in sources
			@test "ICEA" in sources
			@test "INMET diário" in sources
			@test "INMET subdiário" in sources
			@test "Hidroweb diário" in sources
		end

		@testset "stations_pt_extended.json" begin
			raw = read("test/fixtures/stations_pt_extended.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			@test haskey(parsed, :data)
			@test length(parsed.data) == 4

			# All PT, new fields present but null
			for s in parsed.data
				@test s[:country] == "PT"
				@test s[:state] === nothing
				@test s[:elevation_m] === nothing
				@test s[:responsible] === nothing
				@test s[:utc_offset] === nothing
				@test s[:temporal_resolution_min] === nothing
			end
		end

		@testset "observations_br_hourly.json" begin
			raw = read("test/fixtures/observations_br_hourly.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			@test haskey(parsed, :data)
			@test length(parsed.data) == 61

			# Verify expected fields on every record
			for o in parsed.data
				@test haskey(o, :station_id)
				@test haskey(o, :timestamp)
				@test haskey(o, :precipitation_accum_mm)
				@test haskey(o, :qc_flag)
				@test haskey(o, :flagged)
				@test haskey(o, :state)
			end

			# Single station, SP
			@test all(o -> o[:station_id] == "350960101A", parsed.data)
			@test all(o -> o[:state] == "SP", parsed.data)

			# Both QC flag types present
			flags = Set(o[:qc_flag] for o in parsed.data)
			@test "PASS" in flags
			@test "SUSPECT_INCOMPLETE_HOUR" in flags

			# Both flagged values present
			flagged_vals = Set(o[:flagged] for o in parsed.data)
			@test true in flagged_vals
			@test false in flagged_vals
		end

		@testset "observations_br_daily.json" begin
			raw = read("test/fixtures/observations_br_daily.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			@test haskey(parsed, :data)
			@test length(parsed.data) == 15

			@test all(o -> o[:station_id] == "1442032", parsed.data)
			@test all(o -> o[:state] == "MG", parsed.data)
			@test all(o -> o[:qc_flag] == "PASS", parsed.data)
		end

		@testset "observations_br_state.json" begin
			raw = read("test/fixtures/observations_br_state.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			@test haskey(parsed, :data)
			@test length(parsed.data) == 20

			# Multiple stations, all in AC
			sids = Set(o[:station_id] for o in parsed.data)
			@test length(sids) == 20
			@test all(o -> o[:state] == "AC", parsed.data)
		end

		@testset "observations_br_empty.json" begin
			raw = read("test/fixtures/observations_br_empty.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			@test haskey(parsed, :data)
			@test length(parsed.data) == 0
		end

	end

	@testset "Station — extended fields (#22)" begin

		@testset "BR stations have all 11 fields" begin
			raw = read("test/fixtures/stations_br.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			stations = [Station(s) for s in parsed.data]

			@test length(stations) == 6
			@test all(s -> s isa Station, stations)

			s = stations[1]
			@test s.station_id == "02042051"
			@test s.latitude_deg ≈ -20.97888
			@test s.longitude_deg ≈ -42.50944
			@test s.source == "Telemetria"
			@test s.country == "BR"
			@test s.state == "MG"
			@test s.elevation_m ≈ 694.0
			@test s.responsible == "Telemetria"
			@test s.utc_offset == -3
			@test s.temporal_resolution_min == 15

			# Fractional elevation
			@test stations[5].elevation_m ≈ 1160.96

			@test all(s -> s.country == "BR", stations)
			@test all(s -> s.state !== nothing, stations)
		end

		@testset "PT stations have new fields as nothing" begin
			raw = read("test/fixtures/stations_pt_extended.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			stations = [Station(s) for s in parsed.data]

			@test length(stations) == 4
			@test stations[1].station_id == "11217160"
			@test stations[1].country == "PT"

			for s in stations
				@test s.state === nothing
				@test s.elevation_m === nothing
				@test s.responsible === nothing
				@test s.utc_offset === nothing
				@test s.temporal_resolution_min === nothing
			end
		end

		@testset "old 5-field JSON still parses" begin
			raw = read("test/fixtures/stations.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			stations = [Station(s) for s in parsed.data]

			@test length(stations) > 0
			@test stations[1].station_id == "11217160"
			@test stations[1].country === nothing
			@test stations[1].state === nothing
			@test stations[1].elevation_m === nothing
		end

	end

	@testset "get_stations — country and state filters (#23)" begin

		@testset "country filter" begin
			client = make_routing_mock_client(
				stations_fixture="test/fixtures/stations_br.json",
			)
			stations = get_stations(client, country="BR")
			@test length(stations) == 6
			@test all(s -> s.country == "BR", stations)
		end

		@testset "state filter" begin
			client = make_routing_mock_client(
				stations_fixture="test/fixtures/stations_br.json",
			)
			stations = get_stations(client, country="BR", state="MG")
			@test length(stations) == 6
		end

		@testset "no filters still works" begin
			client = make_routing_mock_client(
				stations_fixture="test/fixtures/stations_multi.json",
			)
			stations = get_stations(client)
			@test length(stations) == 6
			@test stations[1].station_id == "11217160"
		end

		@testset "combining all filters" begin
			client = make_routing_mock_client(
				stations_fixture="test/fixtures/stations_br.json",
			)
			stations = get_stations(client,
				source="CEMADEN", country="BR", state="RO")
			@test length(stations) == 6
			@test all(s -> s isa Station, stations)
		end

	end

		@testset "BrObservation (#24)" begin

		@testset "parse hourly fixture" begin
			raw = read("test/fixtures/observations_br_hourly.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			obs = [BrObservation(o) for o in parsed.data]

			@test length(obs) == 61
			@test all(o -> o isa BrObservation, obs)

			o = obs[1]
			@test o.station_id == "350960101A"
			@test o.timestamp == DateTime(2020, 1, 1, 0, 0, 0)
			@test o.precipitation_accum_mm == 0.6
			@test o.qc_flag == "SUSPECT_INCOMPLETE_HOUR"
			@test o.flagged == true
			@test o.state == "SP"
		end

		@testset "parse daily fixture" begin
			raw = read("test/fixtures/observations_br_daily.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			obs = [BrObservation(o) for o in parsed.data]

			@test length(obs) == 15
			@test obs[1].station_id == "1442032"
			@test obs[1].state == "MG"
			@test obs[1].qc_flag == "PASS"
			@test obs[1].flagged == false

			# Precipitation values
			@test obs[1].precipitation_accum_mm == 0.0
			@test obs[2].precipitation_accum_mm == 41.2
		end

		@testset "parse state fixture — multiple stations" begin
			raw = read("test/fixtures/observations_br_state.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			obs = [BrObservation(o) for o in parsed.data]

			@test length(obs) == 20
			sids = Set(o.station_id for o in obs)
			@test length(sids) == 20
			@test all(o -> o.state == "AC", obs)
		end

		@testset "QC flag and flagged correlation" begin
			raw = read("test/fixtures/observations_br_hourly.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			obs = [BrObservation(o) for o in parsed.data]

			flags = Set(o.qc_flag for o in obs)
			@test "PASS" in flags
			@test "SUSPECT_INCOMPLETE_HOUR" in flags

			for o in obs
				if o.qc_flag == "PASS"
					@test o.flagged == false
				else
					@test o.flagged == true
				end
			end
		end

		@testset "null station_id" begin
			json = AtlanticCloud.JSON3.read("""
				{"station_id": null, "timestamp": "2020-01-01 00:00:00",
				 "precipitation_accum_mm": 1.5, "qc_flag": "PASS",
				 "flagged": false, "state": "SP"}
			""")
			o = BrObservation(json)
			@test o.station_id === nothing
			@test o.precipitation_accum_mm == 1.5
			@test o.state == "SP"
		end

		@testset "empty fixture" begin
			raw = read("test/fixtures/observations_br_empty.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			obs = [BrObservation(o) for o in parsed.data]
			@test length(obs) == 0
		end

	end

		@testset "get_br_observations (#25)" begin

		@testset "station-based hourly query" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_hourly.json",
			)
			obs = get_br_observations(client,
				resolution="hourly", station_id="350960101A")
			@test length(obs) == 61
			@test all(o -> o isa BrObservation, obs)
			@test obs[1].station_id == "350960101A"
		end

		@testset "state-based query" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_state.json",
			)
			obs = get_br_observations(client,
				resolution="hourly", state="AC")
			@test length(obs) == 20
			@test all(o -> o.state == "AC", obs)
		end

		@testset "daily resolution" begin
			client = make_routing_mock_client(
				br_station_fixtures=Dict(
					"1442032" => "test/fixtures/observations_br_daily.json",
				),
				br_fixture="test/fixtures/observations_br_empty.json",
			)
			obs = get_br_observations(client,
				resolution="daily", station_id="1442032")
			@test length(obs) == 15
			@test obs[1].state == "MG"
		end

		@testset "with date parameters" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_hourly.json",
			)
			obs = get_br_observations(client,
				resolution="hourly", station_id="350960101A",
				start_date=Date(2020, 1, 1), end_date=Date(2020, 1, 8))
			@test length(obs) == 61
		end

		@testset "with DateTime parameters" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_hourly.json",
			)
			obs = get_br_observations(client,
				resolution="hourly", station_id="350960101A",
				start_date=DateTime(2020, 1, 1), end_date=DateTime(2020, 1, 8))
			@test length(obs) == 61
		end

		@testset "with flagged filter" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_hourly.json",
			)
			obs = get_br_observations(client,
				resolution="hourly", station_id="350960101A",
				flagged=false)
			@test length(obs) == 61  # mock ignores params
		end

		@testset "with qc_flag filter" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_hourly.json",
			)
			obs = get_br_observations(client,
				resolution="hourly", station_id="350960101A",
				qc_flag="PASS")
			@test length(obs) == 61  # mock ignores params
		end

		@testset "both station_id and state" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_hourly.json",
			)
			obs = get_br_observations(client,
				resolution="hourly", station_id="350960101A", state="SP")
			@test length(obs) == 61
		end

		@testset "empty result" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_empty.json",
			)
			obs = get_br_observations(client,
				resolution="hourly", station_id="NONE")
			@test length(obs) == 0
		end

		@testset "API error response" begin
			client = make_mock_client("test/fixtures/error_response.json")
			@test_throws AtlanticCloudError get_br_observations(client,
				resolution="hourly", station_id="X")
		end

		@testset "validation — invalid resolution" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_empty.json",
			)
			@test_throws ArgumentError get_br_observations(client,
				resolution="weekly", station_id="X")
		end

		@testset "validation — neither station_id nor state" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_empty.json",
			)
			@test_throws ArgumentError get_br_observations(client,
				resolution="hourly")
		end

		@testset "validation — start_date after end_date" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_empty.json",
			)
			@test_throws ArgumentError get_br_observations(client,
				resolution="hourly", station_id="X",
				start_date=Date(2020, 6, 1), end_date=Date(2020, 1, 1))
		end

	end

		@testset "Routing mock client" begin

		@testset "routes /stations requests" begin
			client = make_routing_mock_client(
				stations_fixture="test/fixtures/stations_br.json",
				observations_fixture="test/fixtures/observations.json",
				br_fixture="test/fixtures/observations_br_hourly.json",
			)

			stations = get_stations(client)
			@test length(stations) == 6
			@test stations[1].station_id == "02042051"
		end

		@testset "routes /observations requests to PT fixture" begin
			client = make_routing_mock_client(
				stations_fixture="test/fixtures/stations_multi.json",
				observations_fixture="test/fixtures/observations.json",
			)

			obs = get_observations(client, "11217160")
			@test length(obs) == 49
			@test obs[1].station_id == "11217160"
		end

		@testset "routes /observations/br to BR fixture" begin
			# Cannot test via get_br_observations yet (function doesn't exist),
			# so test the mock routing directly via _get.
			client = make_routing_mock_client(
				stations_fixture="test/fixtures/stations_multi.json",
				observations_fixture="test/fixtures/observations.json",
				br_fixture="test/fixtures/observations_br_hourly.json",
			)

			raw = AtlanticCloud._get(client, "/meteorology/api/v1/observations/br?resolution=hourly&station_id=350960101A")
			parsed = AtlanticCloud._parse(raw, "/test")
			@test haskey(parsed, :data)
			@test length(parsed.data) == 61
		end

		@testset "BR station-specific fixture routing" begin
			client = make_routing_mock_client(
				br_fixture="test/fixtures/observations_br_empty.json",
				br_station_fixtures=Dict(
					"350960101A" => "test/fixtures/observations_br_hourly.json",
					"1442032" => "test/fixtures/observations_br_daily.json",
				),
			)

			# Known station gets its fixture
			raw1 = AtlanticCloud._get(client, "/meteorology/api/v1/observations/br?resolution=hourly&station_id=350960101A")
			parsed1 = AtlanticCloud._parse(raw1, "/test")
			@test length(parsed1.data) == 61

			# Different station gets its fixture
			raw2 = AtlanticCloud._get(client, "/meteorology/api/v1/observations/br?resolution=daily&station_id=1442032")
			parsed2 = AtlanticCloud._parse(raw2, "/test")
			@test length(parsed2.data) == 15

			# Unknown station falls back to default BR fixture
			raw3 = AtlanticCloud._get(client, "/meteorology/api/v1/observations/br?resolution=hourly&station_id=UNKNOWN")
			parsed3 = AtlanticCloud._parse(raw3, "/test")
			@test length(parsed3.data) == 0
		end

		@testset "error stations work across paths" begin
			client = make_routing_mock_client(
				stations_fixture="test/fixtures/stations_multi.json",
				observations_fixture="test/fixtures/observations_empty.json",
				br_fixture="test/fixtures/observations_br_empty.json",
				error_stations=Set(["BADSTATION"]),
			)

			# Error on PT path
			@test_throws AtlanticCloudError get_observations(client, "BADSTATION")

			# Error on BR path
			@test_throws AtlanticCloudError AtlanticCloud._get(client,
				"/meteorology/api/v1/observations/br?resolution=hourly&station_id=BADSTATION")
		end

	end

end
