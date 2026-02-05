using Revise
using JSON
using Test
using JuMP
using HiGHS
using REopt

###############   Independent Thermal CHP Testing   ################
println("\n========== Testing Independent Thermal CHP ==========")
d = JSON.parsefile("./scenarios/chp_independent_thermal.json")
s = Scenario(d)
p = REoptInputs(s)

println("CHP fuel cost: ", p.s.chp.fuel_cost_per_mmbtu)
println("Boiler fuel cost: ", p.s.existing_boiler.fuel_cost_per_mmbtu)
println("CHP thermal efficiency: ", p.s.chp.thermal_efficiency_full_load)
println("CHP electric (thermal-to-elec, not fuel-to-elec) efficiency: ", p.s.chp.electric_efficiency_full_load)
println("CHP max thermal capacity: ", p.s.chp.max_thermal_kw, " kW")
println("CHP max electric capacity: ", p.s.chp.max_kw, " kW")

m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.005))
results = run_reopt(m1, p)

# Extract key results
chp_elec_size = results["CHP"]["size_kw"]
chp_thermal_size = results["CHP"]["size_thermal_kw"]
chp_annual_electric_production = results["CHP"]["annual_electric_production_kwh"]
chp_annual_thermal_production = results["CHP"]["annual_thermal_production_mmbtu"]
chp_annual_thermal_from_source = results["CHP"]["annual_thermal_production_from_source_mmbtu"]
chp_annual_fuel_consumption = results["CHP"]["annual_fuel_consumption_mmbtu"]

# Display results
println("\n=== Optimization Results ===")
println("CHP Electric Capacity: ", round(chp_elec_size, digits=2), " kW")
println("CHP Thermal Capacity: ", round(chp_thermal_size, digits=2), " kW")
println("Annual Electric Production: ", round(chp_annual_electric_production, digits=2), " kWh")
println("Annual Thermal to Loads: ", round(chp_annual_thermal_production, digits=2), " MMBtu")
println("Annual Thermal from Source (total): ", round(chp_annual_thermal_from_source, digits=2), " MMBtu")
println("Annual Fuel Consumption: ", round(chp_annual_fuel_consumption, digits=2), " MMBtu")

# Check if boiler is being used instead
if haskey(results, "ExistingBoiler")
    boiler_thermal = results["ExistingBoiler"]["annual_thermal_production_mmbtu"]
    println("Existing Boiler Thermal Production: ", round(boiler_thermal, digits=2), " MMBtu")
end

# Check time-series to see if any thermal is produced in any timestep
println("\nTime-Series Analysis:")
println("Max thermal production in any hour: ", round(maximum(results["CHP"]["thermal_production_series_mmbtu_per_hour"]), digits=3), " MMBtu/hr")
println("Number of hours with thermal production > 0: ", sum(results["CHP"]["thermal_production_series_mmbtu_per_hour"] .> 0.001))
println("Max electric production in any hour: ", round(maximum(results["CHP"]["electric_production_series_kw"]), digits=3), " kW")

# Calculate efficiencies to verify coupled thermal-electric physics
# For nuclear/geothermal: total thermal from source = thermal_to_loads + thermal_for_electric
# where thermal_for_electric = electric_production / electric_efficiency
thermal_for_electric_mmbtu = chp_annual_electric_production * REopt.KWH_PER_MMBTU^-1 / p.s.chp.electric_efficiency_full_load
total_thermal_from_source_mmbtu = chp_annual_thermal_production + thermal_for_electric_mmbtu
estimated_fuel_consumption_mmbtu = total_thermal_from_source_mmbtu / p.s.chp.thermal_efficiency_full_load

println("\nPhysics Verification (Nuclear/Geothermal Model):")
println("Thermal to loads directly: ", round(chp_annual_thermal_production, digits=2), " MMBtu")
println("Thermal consumed for electric: ", round(thermal_for_electric_mmbtu, digits=2), " MMBtu")
println("Total thermal from source: ", round(total_thermal_from_source_mmbtu, digits=2), " MMBtu")
println("Estimated fuel consumption: ", round(estimated_fuel_consumption_mmbtu, digits=2), " MMBtu")
println("Actual fuel consumption: ", round(chp_annual_fuel_consumption, digits=2), " MMBtu")
println("Difference: ", round(abs(estimated_fuel_consumption_mmbtu - chp_annual_fuel_consumption), digits=2), " MMBtu")
println("Overall fuel→electric efficiency: ", round(p.s.chp.thermal_efficiency_full_load * p.s.chp.electric_efficiency_full_load, digits=4))

# Test assertions
@test chp_thermal_size > 0  # Should have thermal capacity
@test haskey(results["CHP"], "size_thermal_kw")  # Key should exist
@test chp_annual_thermal_production > 0  # Should produce thermal energy
@test abs(estimated_fuel_consumption_mmbtu - chp_annual_fuel_consumption) / chp_annual_fuel_consumption < 0.05  # Fuel calculation should be within 5%

println("\n✓ Independent Thermal CHP test completed successfully")
println("======================================================\n")


###############   Boiler + SteamTurbine Comparison Test   ################
println("\n========== Testing Boiler + SteamTurbine (Comparison) ==========")
d_boiler = JSON.parsefile("./scenarios/boiler_steamturbine_comparison.json")
s_boiler = Scenario(d_boiler)
p_boiler = REoptInputs(s_boiler)

println("Boiler fuel cost: ", p_boiler.s.boiler.fuel_cost_per_mmbtu)
println("Boiler efficiency: ", p_boiler.boiler_efficiency["Boiler"])
println("SteamTurbine electric_produced_to_thermal_consumed_ratio: ", p_boiler.s.steam_turbine.electric_produced_to_thermal_consumed_ratio)
println("Overall fuel→electric efficiency (Boiler × ST): ", round(p_boiler.boiler_efficiency["Boiler"] * p_boiler.s.steam_turbine.electric_produced_to_thermal_consumed_ratio, digits=4))
println("SteamTurbine max electric capacity: ", p_boiler.s.steam_turbine.max_kw, " kW")
println("\nComparison with CHP:")
println("CHP fuel→electric efficiency: ", round(p.s.chp.thermal_efficiency_full_load * p.s.chp.electric_efficiency_full_load, digits=4))
println("Should match: Boiler.eff × ST.elec_ratio = ", round(p_boiler.boiler_efficiency["Boiler"] * p_boiler.s.steam_turbine.electric_produced_to_thermal_consumed_ratio, digits=4))

m_boiler = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.005))
results_boiler = run_reopt(m_boiler, p_boiler)

# Extract key results
boiler_size = results_boiler["Boiler"]["size_mmbtu_per_hour"]
steamturbine_size = results_boiler["SteamTurbine"]["size_kw"]
boiler_annual_thermal = results_boiler["Boiler"]["annual_thermal_production_mmbtu"]
steamturbine_annual_electric = results_boiler["SteamTurbine"]["annual_electric_production_kwh"]
boiler_annual_fuel = results_boiler["Boiler"]["annual_fuel_consumption_mmbtu"]

println("\n=== Boiler + SteamTurbine Results ===")
println("Boiler Thermal Capacity: ", round(boiler_size, digits=2), " MMBtu/hr (", round(boiler_size * REopt.KWH_PER_MMBTU, digits=2), " kW)")
println("SteamTurbine Electric Capacity: ", round(steamturbine_size, digits=2), " kW")
println("Annual Thermal Production: ", round(boiler_annual_thermal, digits=2), " MMBtu")
println("Annual Electric Production: ", round(steamturbine_annual_electric, digits=2), " kWh")
println("Annual Fuel Consumption: ", round(boiler_annual_fuel, digits=2), " MMBtu")

# Compare with CHP results
println("\n=== Comparison: CHP vs Boiler+SteamTurbine ===")
println("Total Thermal from Source - CHP: ", round(chp_annual_thermal_from_source, digits=2), " MMBtu | Boiler: ", round(boiler_annual_thermal, digits=2), " MMBtu")
println("  (CHP breakdown: ", round(chp_annual_thermal_production, digits=2), " to loads + ", round(chp_annual_thermal_from_source - chp_annual_thermal_production, digits=2), " for electric)")
println("Electric Production - CHP: ", round(chp_annual_electric_production, digits=2), " kWh | SteamTurbine: ", round(steamturbine_annual_electric, digits=2), " kWh")
println("Fuel Consumption - CHP: ", round(chp_annual_fuel_consumption, digits=2), " MMBtu | Boiler: ", round(boiler_annual_fuel, digits=2), " MMBtu")

# Calculate differences (using total thermal from source for apples-to-apples comparison)
thermal_diff_pct = abs(chp_annual_thermal_from_source - boiler_annual_thermal) / max(chp_annual_thermal_from_source, boiler_annual_thermal) * 100
electric_diff_pct = abs(chp_annual_electric_production - steamturbine_annual_electric) / max(chp_annual_electric_production, steamturbine_annual_electric) * 100
fuel_diff_pct = abs(chp_annual_fuel_consumption - boiler_annual_fuel) / max(chp_annual_fuel_consumption, boiler_annual_fuel) * 100

println("\nDifferences (%):")
println("Total Thermal from Source: ", round(thermal_diff_pct, digits=2), "%")
println("Electric: ", round(electric_diff_pct, digits=2), "%")
println("Fuel: ", round(fuel_diff_pct, digits=2), "%")

println("\n✓ Boiler + SteamTurbine comparison test completed")
println("======================================================\n")
