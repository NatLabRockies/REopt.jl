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

###############   Off-Grid CHP with Operating Reserves Test    ###################

# Test off-grid scenario with CHP and ElectricStorage where CHP requires 10% operating reserves
# This tests that ElectricStorage provides the required reserves for CHP generation

input_data = JSON.parsefile("./scenarios/chp_offgrid.json")
input_data["ElectricLoad"]["min_load_met_annual_fraction"] = 0.999
input_data["ElectricLoad"]["operating_reserve_required_fraction"] = 0.0
# TODO see if no battery shows up when below is set to 0 so CHP can provide SR
input_data["CHP"]["operating_reserve_required_fraction"] = 0.2

println("\n" * "="^80)
println("Testing Off-Grid CHP with Operating Reserves")
println("="^80)

# Create scenario and run optimization
s = Scenario(input_data)
inputs = REoptInputs(s)

println("\nScenario Setup:")
println("  - CHP operating_reserve_required_fraction: ", s.chp.operating_reserve_required_fraction)
println("  - ElectricLoad operating_reserve_required_fraction: ", s.electric_load.operating_reserve_required_fraction)
println("  - Off-grid flag: ", s.settings.off_grid_flag)

m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
results = run_reopt(m, inputs)

# Check that the model solved successfully
@test termination_status(m) == MOI.OPTIMAL || termination_status(m) == MOI.LOCALLY_SOLVED

println("\nOptimization Results:")
println("  - Termination status: ", termination_status(m))
println("  - CHP size: ", round(results["CHP"]["size_kw"], digits=1), " kW")
println("  - Battery power: ", round(results["ElectricStorage"]["size_kw"], digits=1), " kW")
println("  - Battery energy: ", round(results["ElectricStorage"]["size_kwh"], digits=1), " kWh")
println("  - Load met fraction: ", round(results["ElectricLoad"]["offgrid_load_met_fraction"], digits=4))

# Calculate operating reserve requirements
chp_production_to_load = results["CHP"]["electric_to_load_series_kw"]
chp_or_required = sum(chp_production_to_load .* s.chp.operating_reserve_required_fraction)
load_or_required = sum(s.electric_load.critical_loads_kw .* s.electric_load.operating_reserve_required_fraction)
total_or_required = chp_or_required + load_or_required

# Get operating reserve provided
or_provided = sum(results["ElectricLoad"]["offgrid_annual_oper_res_provided_series_kwh"])

println("\nOperating Reserve Analysis:")
println("  - CHP OR required: ", round(chp_or_required, digits=1), " kWh")
println("  - Load OR required: ", round(load_or_required, digits=1), " kWh")
println("  - Total OR required: ", round(total_or_required, digits=1), " kWh")
println("  - Total OR provided: ", round(or_provided, digits=1), " kWh")
println("  - OR margin: ", round(or_provided - total_or_required, digits=1), " kWh")

# Test 1: Operating reserves provided >= operating reserves required (with tolerance for solver gap)
@test or_provided >= total_or_required * (1 - 0.02)  # Allow 2% gap due to mip_rel_gap and rounding
println("\n✓ Test 1 PASSED: Operating reserves provided (", round(or_provided, digits=1), 
        " kWh) >= required (", round(total_or_required, digits=1), " kWh) within tolerance")

# Test 2: CHP produces electricity in off-grid scenario
chp_annual_production = sum(results["CHP"]["electric_to_load_series_kw"]) + 
                        sum(results["CHP"]["electric_to_storage_series_kw"])
@test chp_annual_production > 0
println("✓ Test 2 PASSED: CHP produces electricity (", round(chp_annual_production, digits=1), " kWh)")

# Test 3: Battery is sized to provide operating reserves
battery_sized = results["ElectricStorage"]["size_kw"] > 0 || results["ElectricStorage"]["size_kwh"] > 0
@test battery_sized
println("✓ Test 3 PASSED: Battery is sized (", round(results["ElectricStorage"]["size_kw"], digits=1), 
        " kW, ", round(results["ElectricStorage"]["size_kwh"], digits=1), " kWh)")

# Test 4: Load is met according to minimum fraction
@test results["ElectricLoad"]["offgrid_load_met_fraction"] >= s.electric_load.min_load_met_annual_fraction
println("✓ Test 4 PASSED: Load met fraction (", round(results["ElectricLoad"]["offgrid_load_met_fraction"], digits=4), 
        ") >= minimum (", s.electric_load.min_load_met_annual_fraction, ")")

# Test 5: No grid interaction in off-grid scenario
@test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ 0.0 atol=0.01
println("✓ Test 5 PASSED: No grid interaction (", results["ElectricUtility"]["annual_energy_supplied_kwh"], " kWh)")

# Test 6: Financial calculation includes off-grid costs
f = results["Financial"]
lcc_check = f["lifecycle_generation_tech_capital_costs"] + f["lifecycle_storage_capital_costs"] + 
            f["lifecycle_om_costs_after_tax"] + f["lifecycle_fuel_costs_after_tax"] + 
            f["lifecycle_chp_standby_cost_after_tax"] + f["lifecycle_elecbill_after_tax"] + 
            f["lifecycle_offgrid_other_annual_costs_after_tax"] + f["lifecycle_offgrid_other_capital_costs"] + 
            f["lifecycle_outage_cost"] + f["lifecycle_MG_upgrade_and_fuel_cost"] - 
            f["lifecycle_production_incentive_after_tax"]
@test lcc_check ≈ f["lcc"] atol=1.0
println("✓ Test 6 PASSED: Financial calculations consistent (LCC: \$", round(f["lcc"], digits=0), ")")

println("\n" * "="^80)
println("All tests PASSED for Off-Grid CHP with Operating Reserves!")
println("="^80 * "\n")