# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

input_base = JSON.parsefile("./scenarios/chp_sizing.json")
input_base["CHP"]["min_kw"] = 0.0
input_base["CHP"]["max_kw"] = 200.0

input_existing = deepcopy(input_base)
input_existing["CHP"]["existing_kw"] = 100.0

s_base = Scenario(input_base)
p_base = REoptInputs(s_base)

s_existing = Scenario(input_existing)
p_existing = REoptInputs(s_existing)

chp_name = s_existing.chps[1].name

# Bounds semantics are aligned with Generator/PV: min/max are NEW capacity above existing.
@test p_existing.existing_sizes[chp_name] == 100.0
@test p_existing.min_sizes[chp_name] == 100.0
@test p_existing.max_sizes[chp_name] == 300.0

m_base = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
r_base = run_reopt(m_base, p_base)

m_existing = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
r_existing = run_reopt(m_existing, p_existing)

size_total = r_existing["CHP"]["size_kw"]
new_purchase = size_total - input_existing["CHP"]["existing_kw"]

# Technical feasibility checks
@test new_purchase <= input_existing["CHP"]["max_kw"] + 1e-3
@test size_total <= input_existing["CHP"]["existing_kw"] + input_existing["CHP"]["max_kw"] + 1e-3

# Financial consistency check: existing CHP should not be charged as new CHP capex
@test r_existing["CHP"]["initial_capital_costs"] < r_base["CHP"]["initial_capital_costs"]
@test r_existing["Financial"]["initial_capital_costs"] < r_base["Financial"]["initial_capital_costs"]

finalize(backend(m_base))
empty!(m_base)
finalize(backend(m_existing))
empty!(m_existing)
GC.gc()
