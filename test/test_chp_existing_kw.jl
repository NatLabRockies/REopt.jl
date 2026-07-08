# using Revise
# using REopt
# using JSON
# using Test
# using JuMP
# using HiGHS

###############   Existing CHP Sizing   ###################

input_base = JSON.parsefile("./scenarios/chp_sizing.json")
input_base["CHP"]["min_kw"] = 0.0
input_base["CHP"]["max_kw"] = 200.0

input_existing = deepcopy(input_base)
input_existing["CHP"]["existing_kw"] = 100.0

s_existing = Scenario(input_existing)
p_existing = REoptInputs(s_existing)
chp_name = s_existing.chps[1].name

# Bounds: max_kw is NEW capacity; internal max_sizes = existing + max_kw
@test p_existing.existing_sizes[chp_name] == 100.0
@test p_existing.min_sizes[chp_name] == 100.0
@test p_existing.max_sizes[chp_name] == 300.0

m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
r_base = run_reopt(m1, REoptInputs(Scenario(input_base)))

m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
r_existing = run_reopt(m2, p_existing)

new_purchase = r_existing["CHP"]["size_kw"] - 100.0
expected_capex = REopt.get_tech_initial_capex(s_existing.chps[1], new_purchase) +
    s_existing.chps[1].supplementary_firing_capital_cost_per_kw * r_existing["CHP"]["size_supplemental_firing_kw"]

@test r_existing["CHP"]["initial_capital_costs"] ≈ expected_capex atol=1e-2
@test r_existing["CHP"]["initial_capital_costs"] < r_base["CHP"]["initial_capital_costs"]
@test r_existing["Financial"]["initial_capital_costs"] < r_base["Financial"]["initial_capital_costs"]

###############   BAU Scenario   ###################

bau_s = REopt.BAUScenario(s_existing)
@test length(bau_s.chps) == 1
@test bau_s.chps[1].existing_kw == 100.0
@test bau_s.chps[1].supplementary_firing_capital_cost_per_kw == 0.0

bau_inputs = REopt.BAUInputs(p_existing)
@test bau_inputs.max_sizes[chp_name] == 100.0
@test bau_inputs.min_sizes[chp_name] == 100.0
@test bau_inputs.cap_cost_slope[chp_name] == 0.0

# With BAU: existing CHP reduces BAU LCC and yields smaller incremental NPV
m3 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
m4 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
r_full_existing = run_reopt([m3, m4], p_existing)

m5 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
m6 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
r_full_base = run_reopt([m5, m6], REoptInputs(Scenario(input_base)))

@test r_full_existing["Financial"]["lcc_bau"] < r_full_base["Financial"]["lcc_bau"]
@test r_full_existing["Financial"]["npv"] < r_full_base["Financial"]["npv"]
@test r_full_existing["Financial"]["npv"] > 0

###############   Existing Only (No additional  NEW CHP)   ###################

input_noexp = JSON.parsefile("./scenarios/chp_sizing.json")
input_noexp["CHP"]["existing_kw"] = 150.0
input_noexp["CHP"]["min_kw"] = 0.0
input_noexp["CHP"]["max_kw"] = 0.0

m7 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
m8 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
r_noexp = run_reopt([m7, m8], REoptInputs(Scenario(input_noexp)))

@test r_noexp["CHP"]["size_kw"] ≈ 150.0 atol=0.1
@test r_noexp["CHP"]["initial_capital_costs"] == 0.0
@test r_noexp["CHP"]["annual_electric_production_kwh"] > 0
@test r_noexp["CHP"]["annual_thermal_production_mmbtu"] > 0
@test r_noexp["CHP"]["year_one_fuel_cost_before_tax"] > 0
@test abs(r_noexp["Financial"]["npv"]) < 1000.0

###############   Outage Resilience   ###################

input_outage = JSON.parsefile("./scenarios/chp_sizing.json")
input_outage["CHP"]["existing_kw"] = 150.0
input_outage["CHP"]["min_kw"] = 0.0
input_outage["CHP"]["max_kw"] = 0.0
input_outage["Generator"] = Dict(
    "existing_kw" => 100.0, "min_kw" => 0.0, "max_kw" => 0.0,
    "installed_cost_per_kw" => 500.0, "om_cost_per_kw" => 10.0,
    "fuel_cost_per_gallon" => 3.0,
    "electric_efficiency_full_load" => 0.32, "electric_efficiency_half_load" => 0.32,
    "fuel_avail_gal" => 1000.0,
    "only_runs_during_grid_outage" => true, "sells_energy_back_to_grid" => false
)
input_outage["ElectricUtility"] = Dict(
    "outage_start_time_step" => 5000, "outage_end_time_step" => 5048,
    "co2_from_avert" => true
)
input_outage["ElectricLoad"] = Dict(
    "doe_reference_name" => "Hospital", "annual_kwh" => 1000000.0,
    "critical_load_fraction" => 0.5
)

m9 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
m10 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
r_outage = run_reopt([m9, m10], REoptInputs(Scenario(input_outage)))

@test r_outage["CHP"]["size_kw"] ≈ 150.0 atol=0.1
@test r_outage["Generator"]["size_kw"] ≈ 100.0 atol=0.1
@test r_outage["CHP"]["initial_capital_costs"] == 0.0
@test r_outage["CHP"]["annual_electric_production_kwh"] > 0
@test r_outage["ElectricLoad"]["bau_critical_load_met"] == true
@test abs(r_outage["Financial"]["npv"]) < 5000.0

###############   Multiple CHPs with Existing   ###################

input_multi = JSON.parsefile("./scenarios/multiple_chps.json")
input_multi["CHP"][1]["existing_kw"] = 150.0
input_multi["CHP"][1]["min_kw"] = 0.0
input_multi["CHP"][1]["max_kw"] = 0.0
input_multi["CHP"][2]["existing_kw"] = 0.0
input_multi["CHP"][2]["min_kw"] = 100.0
input_multi["CHP"][2]["max_kw"] = 100.0

s_multi = Scenario(input_multi)
p_multi = REoptInputs(s_multi)

bau_multi = REopt.BAUScenario(s_multi)
@test length(bau_multi.chps) == 1
@test bau_multi.chps[1].name == "CHP_recip_engine"

m11 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
m12 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
r_multi = run_reopt([m11, m12], p_multi)

chp_results = r_multi["CHP"]
recip = first(filter(c -> c["name"] == "CHP_recip_engine", chp_results))
micro = first(filter(c -> c["name"] == "CHP_micro_turbine", chp_results))

@test recip["size_kw"] ≈ 150.0 atol=0.1
@test recip["initial_capital_costs"] == 0.0
@test micro["size_kw"] ≈ 100.0 atol=0.1
@test micro["initial_capital_costs"] > 0.0
@test recip["annual_electric_production_kwh"] > 0
@test micro["annual_electric_production_kwh"] > 0
