using JuMP
using REopt
using Test
using JSON
using HiGHS
using DelimitedFiles
using Logging

# You'll want to change these to your own keys
ENV["NREL_DEVELOPER_API_KEY"]="WWJRoUfvzGSxUWdjNiv4ssaFXnWkMjuXnDGRGFF5"
ENV["NREL_DEVELOPER_EMAIL"]="azolan@nrel.gov"

@testset "CSP" begin
    d = JSON.parsefile("./scenarios/csp.json")

    ### This is where you can import the production_factor and elec_consumption_factor_series so you can bypass SSC.  Other things like loads, etc, are probably best done in the .json.
    d["CST"]["production_factor"] = zeros(8760)
    for day in 1:365
        for h in 6:15
            d["CST"]["production_factor"][(day-1)*24+h] = 1.0
        end
    end
    d["CST"]["elec_consumption_factor_series"] = zeros(8760)
    d["ElectricLoad"]["loads_kw"] = ones(8760)
    d["ProcessHeatLoad"]["fuel_loads_mmbtu_per_hour"] = ones(8760) ./ 300
    s = Scenario(d)
    p = REoptInputs(s)
    m = Model(HiGHS.Optimizer)
    results = run_reopt(m, p)
    # these tests are intended to make sure that heat flows match what we expect.
    # for now, I have a small heating load present that's met by an existing boiler.  I haven't tried a zero heating load scenario, 
    # but a very small number with free fuel should not break the system - the Existing Boiler can't serve storage or the turbine as we test.
    @test results["CST"]["size_kw"] ≈ 8.0 atol=1e-3
    @test results["SteamTurbine"]["size_kw"] ≈ 1.0 atol=1e-3
    @test sum(results["CST"]["thermal_to_high_temp_thermal_storage_series_mmbtu_per_hour"]) ≈  results["CST"]["annual_thermal_production_mmbtu"] rtol=1e-2
    @test sum(results["CST"]["thermal_to_steamturbine_series_mmbtu_per_hour"]) ≈  0.0 atol=1e-3
    @test sum(results["HighTempThermalStorage"]["storage_to_steamturbine_series_mmbtu_per_hour"]) ≈ 99.56 rtol=1e-2
    @test sum(results["HighTempThermalStorage"]["storage_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=1e-3
    @test sum(results["HighTempThermalStorage"]["storage_to_steamturbine_series_mmbtu_per_hour"]) ≈ sum(results["SteamTurbine"]["thermal_consumption_series_mmbtu_per_hour"]) rtol=1e-3
    @test sum(results["SteamTurbine"]["electric_to_load_series_kw"]) ≈ 5835.13 rtol=1e-2
    @test sum(results["SteamTurbine"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈  19.832 rtol=1e-2
    @test sum(results["ExistingBoiler"]["thermal_to_steamturbine_series_mmbtu_per_hour"]) ≈  0.0 atol=1e-3
    @test sum(results["ExistingBoiler"]["thermal_to_storage_series_mmbtu_per_hour"]) ≈  0.0 atol=1e-3
end