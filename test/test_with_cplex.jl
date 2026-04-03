# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
using CPLEX
# using GAMS

#=
add a time-of-export rate that is greater than retail rate for the month of January,
check to make sure that PV does NOT export unless the site load is met first for the month of January.
=#
@testset "Do not allow_simultaneous_export_import" begin
    model = Model(optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_SCRIND" => 0))
    data = JSON.parsefile("./scenarios/monthly_rate.json")

    # create wholesale_rate with compensation in January > retail rate
    jan_rate = data["ElectricTariff"]["monthly_energy_rates"][1]
    data["ElectricTariff"]["wholesale_rate"] =
        append!(repeat([jan_rate + 0.1], 31 * 24), repeat([0.0], 8760 - 31*24))
    data["ElectricTariff"]["monthly_demand_rates"] = repeat([0], 12)
    data["ElectricUtility"]["allow_simultaneous_export_import"] = false

    s = Scenario(data)
    inputs = REoptInputs(s)
    results = run_reopt(model, inputs)

    @test all(x == 0.0 for (i,x) in enumerate(results["ElectricUtility"]["electric_to_load_series_kw"][1:744]) 
              if results["PV"]["electric_to_grid_series_kw"][i] > 0)
end


@testset "Solar and Storage" begin
    model = Model(optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_SCRIND" => 0))
    results = run_reopt(model, "./scenarios/pv_storage.json")

    @test results["PV"]["size_kw"] ≈ 217 atol=1
    @test results["Financial"]["lcc"] ≈ 1.239151e7 rtol=1e-5
    @test results["ElectricStorage"]["size_kw"] ≈ 49 atol=1
    @test results["ElectricStorage"]["size_kwh"] ≈ 83 atol=1
end


@testset "Minimize Unserved Load" begin
    m = Model(optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_SCRIND" => 0))
    results = run_reopt(m, "./scenarios/outage.json")

    @test results["expected_outage_cost"] ≈ 0
    @test sum(results["unserved_load_per_outage"]) ≈ 0
    @test value(m[:binMGTechUsed]["Generator"]) == 1
    @test value(m[:binMGTechUsed]["PV"]) == 1
    @test value(m[:binMGStorageUsed]) == 1
    @test results["Financial"]["lcc"] ≈ 6.82164056207e7 atol=5e4
    
    #=
    Scenario with $0/kWh value_of_lost_load_per_kwh, 12x169 hour outages, 1kW load/hour, and min_resil_time_steps = 168
    - should meet 168 kWh in each outage such that the total unserved load is 12 kWh
    =#
    m = Model(optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_SCRIND" => 0))
    results = run_reopt(m, "./scenarios/nogridcost_minresilhours.json")
    @test sum(results["unserved_load_per_outage"]) ≈ 12
    
    # testing dvUnserved load, which would output 100 kWh for this scenario before output fix
    m = Model(optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_SCRIND" => 0))
    results = run_reopt(m, "./scenarios/nogridcost_multiscenario.json")
    @test sum(results["unserved_load_per_outage"]) ≈ 60
end


@testset "Multiple Sites" begin
    m = Model(optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_SCRIND" => 0))
    ps = [
        REoptInputs("./scenarios/pv_storage.json"),
        REoptInputs("./scenarios/monthly_rate.json"),
    ];
    results = run_reopt(m, ps)
    @test results[3]["Financial"]["lcc"] + results[10]["Financial"]["lcc"] ≈ 1.2830872235e7 rtol=1e-5
end


# TODO implement LinDistFlow test in Xpress (and Cbc?)
@testset "LinDistFlow" begin
    m = Model(optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_SCRIND" => 0))
    ps = [
        REoptInputs("./scenarios/pv_storage.json"),
        REoptInputs("./scenarios/monthly_rate.json"),
    ];
    # make dummy REoptInputs with fixed systems for other nodes in network?
    load_nodes = Dict(
        "3" => [],
        "10" => [],
    )
    ldf_inputs = LinDistFlow.Inputs(
        "data/car10lines.dss", 
        "0", 
        "data/car10linecodes.dss";
        Pload=load_nodes, 
        Qload=load_nodes,
        Sbase=1e6, 
        Vbase=12.5e3, 
        v0 = 1.00,
        v_uplim = 1.05,
        v_lolim = 0.95,
        Ntimesteps = 8760
    );
    build_reopt!(m, ps)
    LinDistFlow.build_ldf!(m, ldf_inputs, ps)
    add_objective!(m, ps)
    optimize!(m)

    results = reopt_results(m, ps)
    @test results[10]["Financial"]["lcc"] + results[3]["Financial"]["lcc"] ≈ 1.23887e7 + 437169.0 rtol=1e-5
    P0 = value.(m[:Pⱼ]["0",:]).data * ldf_inputs.Sbase / 1e3;  # converting to kW
    TotalGridPurchases = value.(m[:dvGridPurchase_3]).data + value.(m[:dvGridPurchase_10]).data; 
    @test maximum(TotalGridPurchases) ≈ maximum(P0) rtol = 1e-5  # lossless model
end


@testset "TieredRates" begin
    expected_year_one_energy_cost = 2342.88
    m = Model(optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_SCRIND" => 0))
    results = run_reopt(m, "./scenarios/tiered_energy_rate.json")
    @test results["ElectricTariff"]["year_one_energy_cost_before_tax"] ≈ 2342.88

    urdb_label = "59bc22705457a3372642da67"  # tiered monthly demand rate
end

@testset "Lookback Demand Charges" begin
    # 1. Testing custom rate from user with demand_lookback_months
    d = JSON.parsefile("./scenarios/lookback_rate.json")
    d["ElectricTariff"] = Dict()
    d["ElectricTariff"]["demand_lookback_percent"] = 0.75
    d["ElectricLoad"]["loads_kw"] = [100 for i in range(1,8760)]
    d["ElectricLoad"]["loads_kw"][22] = 200 # Jan peak
    d["ElectricLoad"]["loads_kw"][2403] = 400 # April peak (Should set dvPeakDemandLookback)
    d["ElectricLoad"]["loads_kw"][4088] = 500 # June peak (not in peak month lookback)
    d["ElectricLoad"]["loads_kw"][8333] = 300 # Dec peak 
    d["ElectricTariff"]["monthly_demand_rates"] = [10,10,20,50,20,10,20,20,20,20,20,5]
    d["ElectricTariff"]["demand_lookback_months"] = [1,0,0,1,0,0,0,0,0,0,0,1] # Jan, April, Dec
    d["ElectricTariff"]["blended_annual_energy_rate"] = 0.01

    m = Model(optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_SCRIND" => 0))
    r = run_reopt(m, REoptInputs(Scenario(d)))

    monthly_peaks = [300,300,300,400,300,500,300,300,300,300,300,300] # 300 = 400*0.75. Sets peak in all months excpet April and June
    expected_demand_cost = sum(monthly_peaks.*d["ElectricTariff"]["monthly_demand_rates"]) 
    @test r["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ expected_demand_cost

    # 2. Testing custom rate from user with demand_lookback_range
    d = JSON.parsefile("./scenarios/lookback_rate.json")
    d["ElectricTariff"] = Dict()
    d["ElectricTariff"]["demand_lookback_percent"] = 0.75
    d["ElectricLoad"]["loads_kw"] = [100 for i in range(1,8760)]
    d["ElectricLoad"]["loads_kw"][22] = 200 # Jan peak
    d["ElectricLoad"]["loads_kw"][2403] = 400 # April peak (Should set dvPeakDemandLookback)
    d["ElectricLoad"]["loads_kw"][4088] = 500 # June peak (not in peak month lookback)
    d["ElectricLoad"]["loads_kw"][8333] = 300 # Dec peak 
    d["ElectricTariff"]["monthly_demand_rates"] = [10,10,20,50,20,10,20,20,20,20,20,5]
    d["ElectricTariff"]["blended_annual_energy_rate"] = 0.01
    d["ElectricTariff"]["demand_lookback_range"] = 6

    m = Model(optimizer_with_attributes(CPLEX.Optimizer, "CPX_PARAM_SCRIND" => 0))
    r = run_reopt(m, REoptInputs(Scenario(d)))

    monthly_peaks = [225, 225, 225, 400, 300, 500, 375, 375, 375, 375, 375, 375]
    expected_demand_cost = sum(monthly_peaks.*d["ElectricTariff"]["monthly_demand_rates"]) 
    @test r["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ expected_demand_cost
end

## equivalent REopt API Post for test 2:
#   NOTE have to hack in API levelization_factor to get LCC within 5e-5 (Mosel tol)
# {"Scenario": {
#     "Site": {
#         "longitude": -118.1164613,
#         "latitude": 34.5794343,
#         "roof_squarefeet": 5000.0,
#         "land_acres": 1.0,
#     "PV": {
#         "macrs_bonus_fraction": 0.4,
#         "installed_cost_per_kw": 2000.0,
#         "tilt": 34.579,
#         "degradation_fraction": 0.005,
#         "macrs_option_years": 5,
#         "federal_itc_fraction": 0.3,
#         "module_type": 0,
#         "array_type": 1,
#         "om_cost_per_kw": 16.0,
#         "macrs_itc_reduction": 0.5,
#         "azimuth": 180.0,
#         "federal_rebate_per_kw": 350.0,
#         "dc_ac_ratio": 1.1
#     },
#     "LoadProfile": {
#         "doe_reference_name": "RetailStore",
#         "annual_kwh": 10000000.0,
#         "city": "LosAngeles"
#     },
#     "ElectricStorage": {
#         "total_rebate_per_kw": 100.0,
#         "macrs_option_years": 5,
#         "can_grid_charge": true,
#         "macrs_bonus_fraction": 0.4,
#         "macrs_itc_reduction": 0.5,
#         "total_itc_fraction": 0,
#         "installed_cost_per_kw": 1000.0,
#         "installed_cost_per_kwh": 500.0,
#         "replace_cost_per_kw": 460.0,
#         "replace_cost_per_kwh": 230.0
#     },
#     "ElectricTariff": {
#         "urdb_label": "5ed6c1a15457a3367add15ae"
#     },
#     "Financial": {
#         "escalation_rate_fraction": 0.026,
#         "offtaker_discount_rate_fraction": 0.081,
#         "owner_discount_rate_fraction": 0.081,
#         "analysis_years": 20,
#         "offtaker_tax_rate_fraction": 0.4,
#         "owner_tax_rate_fraction": 0.4,
#         "om_cost_escalation_rate_fraction": 0.025
#     }
# }}}