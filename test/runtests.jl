using Test
using AtlanticCloud

@testset "AtlanticCloud" begin

    @testset "AtlanticCloudClient" begin

        @test AtlanticCloudClient(api_key="testkey").api_key == "testkey"

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

end
