# using Revise
# using REopt
# using JSON
# using Test
# using JuMP
# using HiGHS

###############   Existing CHP Net Load Adjustment   ###################

input_net = JSON.parsefile("./scenarios/chp_sizing.json")
input_net["CHP"]["existing_kw"] = 100.0
input_net["ElectricLoad"]["loads_kw_is_net"] = true

s_net = Scenario(input_net)
orig_load = copy(s_net.electric_load.loads_kw)
REoptInputs(s_net)
@test s_net.electric_load.loads_kw ≈ orig_load .+ min.(orig_load, 100.0)

input_crit = deepcopy(input_net)
input_crit["ElectricLoad"]["critical_loads_kw_is_net"] = true

s_crit = Scenario(input_crit)
orig_crit = copy(s_crit.electric_load.critical_loads_kw)
REoptInputs(s_crit)
@test s_crit.electric_load.critical_loads_kw ≈ orig_crit .+ min.(orig_crit, 100.0)

###############   Existing CHP Sizing   ###################

input_base = JSON.parsefile("./scenarios/chp_sizing.json")
input_base["CHP"]["min_kw"] = 0.0
input_base["CHP"]["max_kw"] = 200.0

input_existing = deepcopy(input_base)
input_existing["CHP"]["existing_kw"] = 100.0

s_existing = Scenario(input_existing)
p_existing = REoptInputs(s_existing)
chp_name = s_existing.chps[1].name

@test p_existing.existing_sizes[chp_name] == 100.0
@test p_existing.min_sizes[chp_name] == 100.0
@test p_existing.max_sizes[chp_name] == 300.0

m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
r_existing = run_reopt(m, p_existing)

new_purchase = r_existing["CHP"]["size_kw"] - 100.0
expected_capex = REopt.get_tech_initial_capex(s_existing.chps[1], new_purchase) +
    s_existing.chps[1].supplementary_firing_capital_cost_per_kw * r_existing["CHP"]["size_supplemental_firing_kw"]

@test r_existing["CHP"]["initial_capital_costs"] ≈ expected_capex atol=1e-2

###############   BAU Scenario   ###################

bau_s = REopt.BAUScenario(s_existing)
@test length(bau_s.chps) == 1
@test bau_s.chps[1].existing_kw == 100.0
@test bau_s.chps[1].supplementary_firing_capital_cost_per_kw == 0.0

bau_inputs = REopt.BAUInputs(p_existing)
@test bau_inputs.max_sizes[chp_name] == 100.0
@test bau_inputs.min_sizes[chp_name] == 100.0
@test bau_inputs.cap_cost_slope[chp_name] == 0.0

finalize(backend(m)); empty!(m)
GC.gc()