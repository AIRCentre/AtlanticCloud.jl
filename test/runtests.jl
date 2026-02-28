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

end