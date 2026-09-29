# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
using Test
using JuMP
using HiGHS
using JSON
using REopt
using DotEnv
DotEnv.load!()
using Random
using DelimitedFiles
using Logging
using CSV
using DataFrames
Random.seed!(42)

@testset verbose=true "REopt test set using HiGHS solver" begin

    @testset "OffGrid" begin

        ## Scenario 1: Solar, Storage, Fixed Generator
        post_name = "off_grid.json" 
        post = JSON.parsefile("./scenarios/$post_name")
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        scen = Scenario(post)
        r = run_reopt(m, scen)
        
        # Test default values 
        @test scen.electric_utility.outage_start_time_step ≈ 1
        @test scen.electric_utility.outage_end_time_step ≈ 8760 * scen.settings.time_steps_per_hour
        @test scen.storage.attr["ElectricStorage"].soc_init_fraction ≈ 1
        @test scen.storage.attr["ElectricStorage"].can_grid_charge ≈ false
        @test scen.generator.fuel_avail_gal ≈ 1.0e9
        @test scen.generator.min_turn_down_fraction ≈ 0.15
        @test sum(scen.electric_load.loads_kw) - sum(scen.electric_load.critical_loads_kw) ≈ 0 # critical loads should equal loads_kw
        @test scen.financial.microgrid_upgrade_cost_fraction ≈ 0

        # Test outputs
        @test r["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ 0 # no interaction with grid
        @test r["Financial"]["lifecycle_offgrid_other_capital_costs"] ≈ 2617.092 atol=0.01 # Check straight line depreciation calc
        @test sum(r["ElectricLoad"]["offgrid_annual_oper_res_provided_series_kwh"]) >= sum(r["ElectricLoad"]["offgrid_annual_oper_res_required_series_kwh"]) # OR provided >= required
        @test r["ElectricLoad"]["offgrid_load_met_fraction"] >= scen.electric_load.min_load_met_annual_fraction
        @test r["PV"]["size_kw"] ≈ 10886.1611
        f = r["Financial"]
        @test f["lifecycle_generation_tech_capital_costs"] + f["lifecycle_storage_capital_costs"] + f["lifecycle_om_costs_after_tax"] +
                f["lifecycle_fuel_costs_after_tax"] + f["lifecycle_chp_standby_cost_after_tax"] + f["lifecycle_elecbill_after_tax"] + 
                f["lifecycle_offgrid_other_annual_costs_after_tax"] + f["lifecycle_offgrid_other_capital_costs"] + 
                f["lifecycle_outage_cost"] + f["lifecycle_MG_upgrade_and_fuel_cost"] - 
                f["lifecycle_production_incentive_after_tax"] ≈ f["lcc"] atol=1.0


        old = JSON.parsefile("./debug_offgrid_results1_old.json")
        new = JSON.parsefile("./debug_offgrid_results1.json")
        internal_efficiency_fraction = 0.975
        inverter_efficiency_fraction = 0.96
        rectifier_efficiency_fraction = 0.96
        battery_RT_effic = internal_efficiency_fraction * inverter_efficiency_fraction * rectifier_efficiency_fraction
        discharge_effic = inverter_efficiency_fraction * internal_efficiency_fraction^0.5
        free_energy = old["ElectricStorage"]["size_kwh"] * (1 - old["ElectricStorage"]["soc_series_fraction"][8760]) * discharge_effic
        old_pv_used = sum(old["PV"]["electric_to_load_series_kw"]) + sum(old["PV"]["electric_to_storage_series_kw"]) * battery_RT_effic
        new_pv_used = sum(new["PV"]["electric_to_load_series_kw"]) + sum(new["PV"]["electric_to_storage_series_kw"]) * battery_RT_effic
        old_gen_used = sum(old["Generator"]["electric_to_load_series_kw"]) + sum(old["Generator"]["electric_to_storage_series_kw"]) * battery_RT_effic
        new_gen_used = sum(new["Generator"]["electric_to_load_series_kw"]) + sum(new["Generator"]["electric_to_storage_series_kw"]) * battery_RT_effic
        println(free_energy)
        println(new_pv_used + new_gen_used - old_pv_used - old_gen_used)
        @test free_energy ≈ new_pv_used + new_gen_used - old_pv_used - old_gen_used rtol=0.01
    end
end