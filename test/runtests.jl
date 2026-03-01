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
		@test all(s -> !isempty(s.station_id), stations)

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

end
