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

###############   Boiler + SteamTurbine with simplified parameters   ###################
# This test uses the simpler SteamTurbine setup with electric_produced_to_thermal_consumed_ratio
# and thermal_produced_to_thermal_consumed_ratio instead of detailed steam parameters

input_data = JSON.parsefile("./scenarios/boiler_steamturbine.json")
s = Scenario(input_data)
inputs = REoptInputs(s)

m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.001, "output_flag" => false, "log_to_console" => false))
m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.001, "output_flag" => false, "log_to_console" => false))
results = run_reopt([m1,m2], inputs)

println("\n=== Boiler + SteamTurbine Test Results ===")
println("Financial NPV: ", round(results["Financial"]["npv"], digits=2))
println("Financial LCC: ", round(results["Financial"]["lcc"], digits=2))
println("\nBoiler:")
println("  Size (MMBtu/hr): ", round(results["Boiler"]["size_mmbtu_per_hour"], digits=2))
println("  Annual thermal production (MMBtu): ", round(results["Boiler"]["annual_thermal_production_mmbtu"], digits=2))
println("  Annual fuel consumption (MMBtu): ", round(results["Boiler"]["annual_fuel_consumption_mmbtu"], digits=2))
println("  Thermal to SteamTurbine (MMBtu): ", round(sum(results["Boiler"]["thermal_to_steamturbine_series_mmbtu_per_hour"]), digits=2))
println("\nSteamTurbine:")
println("  Size (kW): ", round(results["SteamTurbine"]["size_kw"], digits=2))
println("  Annual electric production (kWh): ", round(results["SteamTurbine"]["annual_electric_production_kwh"], digits=2))
println("  Annual thermal consumption (MMBtu): ", round(results["SteamTurbine"]["annual_thermal_consumption_mmbtu"], digits=2))
println("  Annual thermal production (MMBtu): ", round(results["SteamTurbine"]["annual_thermal_production_mmbtu"], digits=2))

# Verify energy balance: Boiler thermal to ST should match ST thermal consumption
boiler_to_st = sum(results["Boiler"]["thermal_to_steamturbine_series_mmbtu_per_hour"])
st_thermal_in = results["SteamTurbine"]["annual_thermal_consumption_mmbtu"]
println("\nEnergy Balance Check:")
println("  Boiler->SteamTurbine: ", round(boiler_to_st, digits=2), " MMBtu")
println("  SteamTurbine thermal in: ", round(st_thermal_in, digits=2), " MMBtu")
println("  Difference: ", round(abs(boiler_to_st - st_thermal_in), digits=2), " MMBtu")

println("=============================================\n")
