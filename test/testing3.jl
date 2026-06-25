using JuMP
using REopt
using Test
using JSON
using Xpress
using DelimitedFiles
using Logging

ENV["NREL_DEVELOPER_API_KEY"]="WWJRoUfvzGSxUWdjNiv4ssaFXnWkMjuXnDGRGFF5"
ENV["NREL_DEVELOPER_EMAIL"]="azolan@nrel.gov"

# @testset "CSP-Exowatt" begin
#     d = JSON.parsefile("./scenarios/csp.json")
#     d["CST"]["production_factor"] = zeros(8760)
#     for day in 1:365
#         for h in 6:15
#             d["CST"]["production_factor"][(day-1)*24+h] = 1.0
#         end
#     end
#     d["CST"]["elec_consumption_factor_series"] = zeros(8760)
#     d["ElectricLoad"]["loads_kw"] = ones(8760)
#     d["ProcessHeatLoad"]["fuel_loads_mmbtu_per_hour"] = ones(8760) ./ 300
#     s = Scenario(d)
#     p = REoptInputs(s)
#     m = Model(HiGHS.Optimizer)
#     results = run_reopt(m, p)
#     println(results["Messages"])
#     @test results["CST"]["size_kw"] ≈ 8.0 atol=1e-3
#     @test results["SteamTurbine"]["size_kw"] ≈ 1.0 atol=1e-3
#     @test sum(results["CST"]["thermal_to_high_temp_thermal_storage_series_mmbtu_per_hour"]) ≈  8*3650.0/REopt.KWH_PER_MMBTU rtol=1e-2
#     for day in 1:365
#         println(results["CST"]["thermal_to_high_temp_thermal_storage_series_mmbtu_per_hour"][(day-1)*24+6:(day-1)*24+15])
#     end
#     @test sum(results["SteamTurbine"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈  0.0 rtol=1e-3
#     @test sum(results["CST"]["thermal_to_steamturbine_series_mmbtu_per_hour"]) ≈  0.0 atol=1e-3
#     @test sum(results["HighTempThermalStorage"]["storage_to_steamturbine_series_mmbtu_per_hour"]) ≈ 99.5637 atol=1e-3
#     @test sum(results["HighTempThermalStorage"]["storage_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=1e-3
#     @test sum(results["SteamTurbine"]["electric_to_load_series_kw"]) ≈  5250.971 atol=1e-3
#     @test sum(results["SteamTurbine"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈  19.832 rtol=1e-3
#     @test sum(results["ExistingBoiler"]["thermal_to_steamturbine_series_mmbtu_per_hour"]) ≈  0.0 atol=1e-3
#     @test sum(results["ExistingBoiler"]["thermal_to_storage_series_mmbtu_per_hour"]) ≈  0.0 atol=1e-3
# end

@testset "CHP load-following and absorption chiller flow" begin
    d = JSON.parsefile("./scenarios/chp-abschl-flow.json")
    s = Scenario(d)
    p = REoptInputs(s)
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01))
    results = run_reopt(m, p)
    @test sum(results["CHP"]["thermal_to_absorption_chiller_series_mmbtu_per_hour"]) ≈ 3756.73 rtol=1e-2
    @test sum(results["CHP"]["thermal_curtailed_series_mmbtu_per_hour"]) ≈ 269.35 rtol=1e-2
end