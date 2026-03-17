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

	end

	@testset "Multi-station fixtures" begin

		@testset "stations_multi.json" begin
			raw = read("test/fixtures/stations_multi.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			stations = [Station(s) for s in parsed.data]

			@test length(stations) == 6
			@test all(s -> s isa Station, stations)

			# Verify geographic spread
			ids = [s.station_id for s in stations]
			@test "11217160" in ids   # Azores
			@test "1200521" in ids    # Madeira
			@test "1200535" in ids    # Mainland

			# Verify source diversity
			sources = Set(s.source for s in stations)
			@test "IPMA" in sources
			@test "RHA" in sources
			@test "DSCIG" in sources
		end

		@testset "observations_multi.json" begin
			raw = read("test/fixtures/observations_multi.json", String)
			parsed = AtlanticCloud.JSON3.read(raw)
			observations = [Observation(o) for o in parsed.data]

			@test length(observations) == 9  # 3 stations × 3 hours

			# Verify multiple stations present
			station_ids = Set(o.station_id for o in observations)
			@test length(station_ids) == 3
			@test "11217160" in station_ids
			@test "1200535" in station_ids
			@test "1200533" in station_ids

			# Verify varied metric coverage
			# 1200535 has pressure_hpa
			lisboa_obs = filter(o -> o.station_id == "1200535", observations)
			@test all(o -> o.pressure_hpa !== nothing, lisboa_obs)

			# 11217160 has no pressure
			azores_obs = filter(o -> o.station_id == "11217160", observations)
			@test all(o -> o.pressure_hpa === nothing, azores_obs)

			# 1200533 has only temperature and humidity
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

			# Known station returns its fixture
			obs = get_observations(client, "11217160")
			@test length(obs) == 49
			@test obs[1].station_id == "11217160"

			# Unknown station returns empty default
			obs_empty = get_observations(client, "UNKNOWN")
			@test length(obs_empty) == 0
		end

		@testset "error station handling" begin
			client = make_multi_mock_client(
				default_fixture="test/fixtures/observations_empty.json",
				error_stations=Set(["BADSTATION"]),
			)

			# Error station triggers AtlanticCloudError
			@test_throws AtlanticCloudError get_observations(client, "BADSTATION")

			# Non-error station still works
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

	@testset "GeoInterface traits — Station" begin

		raw = read("test/fixtures/stations_multi.json", String)
		parsed = AtlanticCloud.JSON3.read(raw)
		stations = [Station(s) for s in parsed.data]
		s = stations[1]  # Santa Maria, Azores: lon=-25.0917, lat=36.9542

		# Core trait
		@test GI.isgeometry(Station) == true
		@test GI.geomtrait(s) == GI.PointTrait()
		@test GI.ncoord(GI.PointTrait(), s) == 2
		@test GI.ngeom(GI.PointTrait(), s) == 0
		@test GI.getgeom(GI.PointTrait(), s, 1) === nothing

		# Coordinate access (index 1 = X/lon, index 2 = Y/lat)
		@test GI.getcoord(GI.PointTrait(), s, 1) ≈ -25.0917
		@test GI.getcoord(GI.PointTrait(), s, 2) ≈ 36.9542

		# Convenience accessors
		@test GI.x(GI.PointTrait(), s) ≈ -25.0917
		@test GI.y(GI.PointTrait(), s) ≈ 36.9542

		# check_geointerface_point helper
		failures = check_geointerface_point(GI, s, -25.0917, 36.9542)
		@test isempty(failures)

		# Verify a different station (Lisboa: lon=-9.149722, lat=38.719078)
		lisboa = stations[5]
		@test GI.x(GI.PointTrait(), lisboa) ≈ -9.149722
		@test GI.y(GI.PointTrait(), lisboa) ≈ 38.719078

		# Verify all stations are valid geometries
		@test all(s -> GI.geomtrait(s) == GI.PointTrait(), stations)

	end

	@testset "to_dataframe — Station" begin

		client = make_mock_client("test/fixtures/stations_multi.json")
		stations = get_stations(client)
		df = to_dataframe(stations)

		@test df isa DataFrame
		@test nrow(df) == 6
		@test ncol(df) == 5
		@test names(df) == ["station_id", "place", "latitude_deg", "longitude_deg", "source"]

		# Verify types
		@test eltype(df.latitude_deg) == Float64
		@test eltype(df.longitude_deg) == Float64

		# Verify data
		@test df.station_id[1] == "11217160"
		@test df.latitude_deg[1] ≈ 36.9542

		# Verify nothing → missing conversion for nullable fields
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

		# timestamp stays DateTime (non-nullable)
		@test eltype(df.timestamp) == DateTime

		# Verify nothing → missing for metrics
		# 1200535 (rows 4–6) has pressure
		@test !ismissing(df.pressure_hpa[4])
		@test df.pressure_hpa[4] ≈ 1013.2

		# 11217160 (rows 1–3) has no pressure
		@test ismissing(df.pressure_hpa[1])

		# 1200533 (rows 7–9) has only temperature and humidity
		@test !ismissing(df.temperature_c[7])
		@test ismissing(df.wind_speed_kmh[7])
		@test ismissing(df.wind_direction_bin[7])

	end

	@testset "to_dataframe — empty vectors" begin

		df_stations = to_dataframe(Station[])
		@test df_stations isa DataFrame
		@test nrow(df_stations) == 0
		@test ncol(df_stations) == 5

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
			[:station_id, :place, :latitude_deg, :longitude_deg, :source],
			6)
		@test isempty(failures)

	end

end
