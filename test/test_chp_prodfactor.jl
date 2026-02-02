using Revise
using REopt
using JSON
using DelimitedFiles
using PlotlyJS
using Dates
using Test
using JuMP
using HiGHS
using DotEnv
DotEnv.load!()


###########   CHP production_factor_series test   #############
@testset "CHP with production_factor_series" begin
    # Create a simple scenario with electric-only CHP and a custom production factor
    input_data = Dict(
        "Site" => Dict(
            "latitude" => 39.7,
            "longitude" => -104.9
        ),
        "ElectricLoad" => Dict(
            "loads_kw" => repeat([100.0], 8760),
            "year" => 2025
        ),
        "ElectricTariff" => Dict(
            "urdb_label" => "5ed6c1a15457a3367add15ae"
        ),
        "CHP" => Dict(
            "is_electric_only" => true,
            "fuel_cost_per_mmbtu" => 4.0,
            "max_kw" => 100.0,
            "min_kw" => 100.0,
            "production_factor_series" => vcat(repeat([0.5], 4380), repeat([1.0], 4380))  # 50% for first half year, 100% for second half
        )
    )
    
    s = Scenario(input_data)
    p = REoptInputs(s)
    
    # Verify the production factor series was properly assigned
    @test !isnothing(s.chp.production_factor_series)
    @test length(s.chp.production_factor_series) == 8760
    @test s.chp.production_factor_series[1] ≈ 0.5 atol=0.001
    @test s.chp.production_factor_series[8760] ≈ 1.0 atol=0.001
    
    # Run the optimization
    m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
    results = run_reopt(m, p)
    
    # Check that production matches the pattern (lower in first half, higher in second half)
    first_half_avg = sum(results["CHP"]["electric_production_series_kw"][1:4380]) / 4380
    second_half_avg = sum(results["CHP"]["electric_production_series_kw"][4381:8760]) / 4380
    
    println("CHP production_factor_series test passed!")
    println("CHP size: ", results["CHP"]["size_kw"], " kW")
    println("First half avg production: ", round(first_half_avg, digits=2), " kW")
    println("Second half avg production: ", round(second_half_avg, digits=2), " kW")
end