using Test
using Dates
using AtlanticCloud

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

		function make_mock_client(fixture_path::String)
			fixture = read(fixture_path, String)
			mock_response = (url, headers) -> (body = Vector{UInt8}(fixture),)
			return AtlanticCloudClient(api_key = "testkey", http_get = mock_response)
		end

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

end