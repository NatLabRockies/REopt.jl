# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
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

if "Xpress" in ARGS
    @testset "test_with_xpress" begin
        # @test true  #skipping Xpress while import to HiGHS takes place
        include("test_with_xpress.jl")
    end

elseif "CPLEX" in ARGS
    @testset "test_with_cplex" begin
        include("test_with_cplex.jl")
    end
else  # run HiGHS tests
    @testset verbose=true "REopt test set using HiGHS solver" begin
        @testset "Sector defaults" begin
            input_data = JSON.parsefile("scenarios/sector_defaults.json")
            
            # Fill in GHP so don't have to call GHPGHX.jl
            ghp_response = JSON.parsefile("scenarios/ghpghx_response.json")
            input_data["GHP"]["ghpghx_responses"] = [ghp_response]

            #Commercial
            input_data["Site"]["sector"] = "commercial/industrial"
            s = Scenario(input_data)
            @test s.financial.owner_tax_rate_fraction == 0.26
            @test s.financial.offtaker_tax_rate_fraction == 0.26
            @test s.financial.chp_fuel_cost_escalation_rate_fraction == 0.0348
            @test s.financial.elec_cost_escalation_rate_fraction == 0.0166
            @test s.financial.om_cost_escalation_rate_fraction == 0.025
            @test s.financial.offtaker_discount_rate_fraction == 0.0624
            for tech_struct in (s.pvs[1], s.wind, s.chp, s.steam_turbine)
                for incentive_input_name in (:macrs_option_years, :macrs_bonus_fraction)
                    @test getfield(tech_struct, incentive_input_name) != 0 
                end
            end
            for tech_struct in (s.pvs[1], s.wind, s.ghp_option_list[1])
                @test getfield(tech_struct, :federal_itc_fraction) != 0
            end
            for stor_name in ("ElectricStorage", "ColdThermalStorage", "HotThermalStorage", "HighTempThermalStorage")
                stor_struct = s.storage.attr[stor_name]
                for incentive_input_name in (:macrs_option_years, :macrs_bonus_fraction, :total_itc_fraction)
                    @test getfield(stor_struct, incentive_input_name) != 0
                end
            end

            # Federal sector, third party private owned
            input_data["Site"]["sector"] = "federal"
            input_data["Site"]["federal_procurement_type"] = "privateowned_thirdparty"
            s = Scenario(input_data)
            @test s.financial.owner_tax_rate_fraction == 0.26
            @test s.financial.offtaker_tax_rate_fraction == 0.0
            @test s.financial.chp_fuel_cost_escalation_rate_fraction == 0.024 #national avg
            @test s.financial.elec_cost_escalation_rate_fraction == 0.0074 #national avg
            @test s.financial.om_cost_escalation_rate_fraction == 0.015
            @test s.financial.offtaker_discount_rate_fraction == 0.045
            for tech_struct in (s.pvs[1], s.wind, s.chp, s.steam_turbine)
                for incentive_input_name in (:macrs_option_years, :macrs_bonus_fraction)
                    @test getfield(tech_struct, incentive_input_name) != 0 
                end
            end
            for tech_struct in (s.pvs[1], s.wind, s.ghp_option_list[1])
                @test getfield(tech_struct, :federal_itc_fraction) != 0
            end
            for stor_name in ("ElectricStorage", "ColdThermalStorage", "HotThermalStorage", "HighTempThermalStorage")
                stor_struct = s.storage.attr[stor_name]
                for incentive_input_name in (:macrs_option_years, :macrs_bonus_fraction, :total_itc_fraction)
                    @test getfield(stor_struct, incentive_input_name) != 0
                end
            end

            # Federal direct purchase
            input_data["Site"]["federal_procurement_type"] = "fedowned_dirpurch"
            input_data["Site"]["federal_sector_state"] = "CA"
            s = Scenario(input_data)
            @test s.financial.owner_tax_rate_fraction == 0.0
            @test s.financial.offtaker_tax_rate_fraction == 0.0
            @test s.financial.chp_fuel_cost_escalation_rate_fraction == 0.0079
            @test s.financial.elec_cost_escalation_rate_fraction == -0.0062
            @test s.financial.om_cost_escalation_rate_fraction == 0.015
            @test s.financial.offtaker_discount_rate_fraction == 0.045
            for tech_struct in (s.pvs[1], s.wind, s.chp, s.ghp_option_list[1], s.steam_turbine)
                for incentive_input_name in (:macrs_option_years, :macrs_bonus_fraction, :federal_itc_fraction)
                    default = 0
                    try
                        #need try catch b/c SteamTurbine does not have federal_itc_fraction input
                        default = getfield(tech_struct, incentive_input_name)
                    catch
                        continue
                    end
                    @test default == 0 
                end
            end
            for stor_name in ("ElectricStorage", "ColdThermalStorage", "HotThermalStorage", "HighTempThermalStorage")
                stor_struct = s.storage.attr[stor_name]
                for incentive_input_name in (:macrs_option_years, :macrs_bonus_fraction, :total_itc_fraction)
                    @test getfield(stor_struct, incentive_input_name) == 0
                end
            end
        end

        @testset "Prevent simultaneous charge and discharge" begin
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(model, "./scenarios/simultaneous_charge_discharge.json")
            @test any(.&(
                    results["ElectricStorage"]["storage_to_load_series_kw"] .!= 0.0,
                    (
                        results["ElectricUtility"]["electric_to_storage_series_kw"] .+ 
                        results["PV"]["electric_to_storage_series_kw"]
                    ) .!= 0.0
                )
                ) ≈ false
            @test any(.&(
                    results["Outages"]["storage_discharge_series_kw"] .!= 0.0,
                    results["Outages"]["pv_to_storage_series_kw"] .!= 0.0
                )
                ) ≈ false
            finalize(backend(model))
            empty!(model)
            GC.gc()                
        end
        @testset "hybrid profile" begin
            electric_load = REopt.ElectricLoad(; 
                blended_doe_reference_percents = [0.2, 0.2, 0.2, 0.2, 0.2],
                blended_doe_reference_names    = ["RetailStore", "LargeOffice", "MediumOffice", "SmallOffice", "Warehouse"],
                annual_kwh                     = 50000.0,
                year                           = 2017,
                city                           = "Atlanta",
                latitude                       = 35.2468, 
                longitude                      = -91.7337
            )
            @test sum(electric_load.loads_kw) ≈ 50000.0
        end
        @testset "Solar dataset" begin

            # 1. Dallas TX 
            latitude, longitude = 32.775212075983646, -96.78105623767185
            radius = 0
            dataset, distance, datasource = REopt.call_solar_dataset_api(latitude, longitude, radius)
            @test dataset == "nsrdb"

            # 2. Merefa, Ukraine 
            latitude, longitude = 49.80670544975866, 36.05418033509974
            radius = 0
            dataset, distance, datasource = REopt.call_solar_dataset_api(latitude, longitude, radius)
            @test dataset == "nsrdb"

            # 3. Oulu, Findland
            latitude, longitude = 65.0102196310875, 25.465387094897675
            radius = 0
            dataset, distance, datasource = REopt.call_solar_dataset_api(latitude, longitude, radius)
            @test dataset == "intl"

            # 4. Fairbanks, AK 
            site = "Fairbanks"
            latitude, longitude = 64.84112047064114, -147.71570239058084 
            radius = 20
            dataset, distance, datasource = REopt.call_solar_dataset_api(latitude, longitude, radius)
            @test dataset == "tmy3"  
        end

        @testset "ASHP min allowable size and COP, CF Profiles" begin
            #Heating profiles
            heating_reference_temps_degF = [10,20,30]
            heating_cop_reference = [1,3,4]
            heating_cf_performance = [1.2,1.3,1.5]
            back_up_temp_threshold_degF = 10
            test_temps = [5,15,25,35]
            test_cops = [1.0,2.0,3.5,4.0]
            test_cfs = [1.0,1.25,1.4,1.5]
            heating_cop, heating_cf = REopt.get_ashp_performance(heating_cop_reference,
                heating_cf_performance,
                heating_reference_temps_degF,
                test_temps,
                back_up_temp_threshold_degF)
            @test all(heating_cop .== test_cops)
            @test all(heating_cf .== test_cfs)
            #Cooling profiles
            cooling_reference_temps_degF = [30,20,10]
            cooling_cop_reference = [1,3,4]
            cooling_cf_performance = [1.2,1.3,1.5]
            back_up_temp_threshold_degF = -200
            test_temps = [35,25,15,5]
            test_cops = [1.0,2.0,3.5,4.0]
            test_cfs = [1.2,1.25,1.4,1.5]
            cooling_cop, cooling_cf = REopt.get_ashp_performance(cooling_cop_reference,
                cooling_cf_performance,
                cooling_reference_temps_degF,
                test_temps,
                back_up_temp_threshold_degF)
            @test all(cooling_cop .== test_cops)
            @test all(cooling_cf .== test_cfs)
            # min allowable size
            heating_load = Array{Real}([10.0,10.0,10.0,10.0])
            cooling_load = Array{Real}([10.0,10.0,10.0,10.0])
            space_heating_min_allowable_size = REopt.get_ashp_default_min_allowable_size(heating_load, heating_cf, cooling_load, cooling_cf, 0.5)
            wh_min_allowable_size = REopt.get_ashp_default_min_allowable_size(heating_load, heating_cf, Real[], Real[], 0.5)
            @test space_heating_min_allowable_size ≈ 9.166666666666666 atol=1e-8
            @test wh_min_allowable_size ≈ 5.0 atol=1e-8
        end

        @testset "January Export Rates" begin
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            data = JSON.parsefile("./scenarios/monthly_rate.json")

            # create wholesale_rate with compensation in January > retail rate
            jan_rate = data["ElectricTariff"]["monthly_energy_rates"][1]
            data["ElectricTariff"]["wholesale_rate"] =
                append!(repeat([jan_rate + 0.1], 31 * 24), repeat([0.0], 8760 - 31*24))
            data["ElectricTariff"]["monthly_demand_rates"] = repeat([0], 12)

            s = Scenario(data)
            inputs = REoptInputs(s)
            results = run_reopt(model, inputs)

            @test results["PV"]["size_kw"] ≈ 68.9323 atol=0.01
            @test results["Financial"]["lcc"] ≈ 432681.26 rtol=1e-5 # with levelization_factor hack the LCC is within 5e-5 of REopt API LCC
            @test all(x == 0.0 for x in results["PV"]["electric_to_load_series_kw"][1:744])
            finalize(backend(model))
            empty!(model)
            GC.gc()
        end

        @testset "Blended tariff" begin
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(model, "./scenarios/no_techs.json")
            @test results["ElectricTariff"]["year_one_energy_cost_before_tax"] ≈ 1000.0
            @test results["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ 136.99
            finalize(backend(model))
            empty!(model)
            GC.gc()            
        end

        @testset "Solar and Storage" begin
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            inputs = REoptInputs("./scenarios/pv_storage.json")
            r = run_reopt(model, inputs)

            @test r["PV"]["size_kw"] ≈ 216.6667 atol=0.01
            @test r["Financial"]["lcc"] ≈ 1.2391786e7 rtol=1e-5
            @test r["ElectricStorage"]["size_kw"] ≈ 49.0 atol=0.1
            @test r["ElectricStorage"]["size_kwh"] ≈ 83.3 atol=0.1

            # Test constrained CAPEX 
            initial_capex_no_incentives = r["Financial"]["initial_capital_costs"]
            max_capex = initial_capex_no_incentives * 0.60
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            data = JSON.parsefile("./scenarios/pv_storage.json")
            data["Financial"]["max_initial_capital_costs_before_incentives"] = max_capex
            r = run_reopt(model, data)
            @test r["Financial"]["initial_capital_costs"] ≈ max_capex rtol=1e-5
            finalize(backend(model))
            empty!(model)
            GC.gc()            
        end
    
        @testset "Solar and ElectricStorage with cost constants" begin
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            d = JSON.parsefile("./scenarios/pv_storage.json");
            
            d["ElectricStorage"]["installed_cost_constant"] = 7500
            d["ElectricStorage"]["replace_cost_constant"] = 5025
            d["ElectricStorage"]["cost_constant_replacement_year"] = 10
        
            s = Scenario(d)
            inputs = REoptInputs(s)
            results = run_reopt([m1,m2], inputs)
            
            UpfrontCosts_NoIncentive = (results["ElectricStorage"]["size_kw"]*d["ElectricStorage"]["installed_cost_per_kw"] ) +
                                    (results["ElectricStorage"]["size_kwh"]*d["ElectricStorage"]["installed_cost_per_kwh"]) + 
                                    d["ElectricStorage"]["installed_cost_constant"] +
                                    (results["PV"]["size_kw"]*d["PV"]["installed_cost_per_kw"])
            
            ReplacementCosts_NoIncentive = (results["ElectricStorage"]["size_kw"]*d["ElectricStorage"]["replace_cost_per_kw"] ) +
                                    (results["ElectricStorage"]["size_kwh"]*d["ElectricStorage"]["replace_cost_per_kwh"]) + 
                                    d["ElectricStorage"]["replace_cost_constant"] 

            @test results["Financial"]["initial_capital_costs"] ≈ UpfrontCosts_NoIncentive rtol=1e-5
            @test results["Financial"]["replacements_future_cost_after_tax"] ≈ ReplacementCosts_NoIncentive  rtol=1e-5
        
        end 

        @testset "Solar and ElectricStorage with cost constants but zero-out ElectricStorage" begin
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            d = JSON.parsefile("./scenarios/pv_storage.json");
            
            d["ElectricStorage"]["installed_cost_constant"] = 7500
            d["ElectricStorage"]["replace_cost_constant"] = 5025
            d["ElectricStorage"]["cost_constant_replacement_year"] = 10
            d["ElectricStorage"]["max_kw"] = 0

            s = Scenario(d)
            inputs = REoptInputs(s)
            results = run_reopt([m1,m2], inputs)
            
            UpfrontCosts_NoIncentive = results["PV"]["size_kw"]*d["PV"]["installed_cost_per_kw"]
            
            ReplacementCosts_NoIncentive = 0

            @test results["Financial"]["initial_capital_costs"] ≈ UpfrontCosts_NoIncentive rtol=1e-5
            @test results["Financial"]["replacements_future_cost_after_tax"] ≈ ReplacementCosts_NoIncentive  rtol=1e-5
        
        end 

        # TODO test MPC with outages
        @testset "MPC" begin
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            r = run_mpc(model, "./scenarios/mpc.json")
            @test maximum(r["ElectricUtility"]["to_load_series_kw"][1:15]) <= 98.0 
            @test maximum(r["ElectricUtility"]["to_load_series_kw"][16:24]) <= 97.0
            @test sum(r["PV"]["to_grid_series_kw"]) ≈ 0
            grid_draw = r["ElectricUtility"]["to_load_series_kw"] .+ r["ElectricUtility"]["to_battery_series_kw"]
            # the grid draw limit in the 10th time step is set to 90
            # without the 90 limit the grid draw is 98 in the 10th time step
            @test grid_draw[10] <= 90
            finalize(backend(model))
            empty!(model)
            GC.gc()            
        end

        @testset "MPC Multi-node" begin
            # not doing much yet; just testing that two identical sites have the same costs
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            ps = MPCInputs[]
            push!(ps, MPCInputs("./scenarios/mpc_multinode1.json"));
            push!(ps, MPCInputs("./scenarios/mpc_multinode2.json"));
            r = run_mpc(model, ps)
            @test r[1]["Costs"] ≈ r[2]["Costs"]
            finalize(backend(model))
            empty!(model)
            GC.gc()            
        end

        @testset "Complex Incentives" begin
            """
            This test was compared against the API test:
                reo.tests.test_reopt_url.EntryResourceTest.test_complex_incentives
            when using the hardcoded levelization_factor in this package's REoptInputs function.
            The two LCC's matched within 0.00005%. (The Julia pkg LCC is 1.0971991e7)
            """
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(model, "./scenarios/incentives.json")
            @test results["Financial"]["lcc"] ≈ 1.096852612e7 atol=1e4  
            finalize(backend(model))
            empty!(model)
            GC.gc()
        end
        @testset "Production Based Incentives" begin
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            d = JSON.parsefile("scenarios/pbi.json")
            results = run_reopt(model, d)
            s = Scenario(d)
            i = REoptInputs(s)
            @test i.pbi_benefit_per_kwh["Wind"] == 0.05
            @test i.pbi_benefit_per_kwh["Generator"] == 0.08
            @test i.pbi_benefit_per_kwh["CHP"] == 0.02
            @test i.pbi_benefit_per_kwh["PV"] == 0.1
            @test i.pbi_benefit_per_kwh["SteamTurbine"] == 0.07
            
            @test i.pbi_max_benefit["Wind"] == 1000000
            @test i.pbi_max_benefit["Generator"] == 100
            @test i.pbi_max_benefit["CHP"] == 10000
            @test i.pbi_max_benefit["PV"] == 10
            @test i.pbi_pwf["Wind"] < i.pbi_pwf["PV"]  #PV has more years of benefit than wind
            @test i.pbi_pwf["PV"] < i.pbi_pwf["SteamTurbine"]  #SteamTurbine has more years of benefit than PV

            # No generator or CHP production and SteamTurbine min size is larger than prod incentive max size, so just testing against wind prod plus the PV max benefit
            @test results["Financial"]["lifecycle_production_incentive_after_tax"] ≈ i.pbi_pwf["PV"]*i.pbi_max_benefit["PV"] + i.pbi_pwf["Wind"]*d["Wind"]["production_incentive_per_kwh"]*results["Wind"]["annual_energy_produced_kwh"] rtol=1e-4
            finalize(backend(model))
            empty!(model)
            GC.gc()            
        end

        @testset "Fifteen minute load" begin
            d = JSON.parsefile("scenarios/no_techs.json")
            d["ElectricLoad"] = Dict("loads_kw" => repeat([1.0], 35040), "year" => 2017)
            d["Settings"] = Dict("time_steps_per_hour" => 4)
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(model, d)
            @test results["ElectricLoad"]["annual_calculated_kwh"] ≈ 8760
            finalize(backend(model))
            empty!(model)
            GC.gc()            
        end

        try
            rm("Highs.log", force=true)
        catch
            @warn "Could not delete test/Highs.log"
        end

        @testset "AVERT region abberviations" begin
            """
            This test checks 5 scenarios (in order)
            1. Coordinate pair inside an AVERT polygon
            2. Coordinate pair near a US border
            3. Coordinate pair < 5 miles from US border
            4. Coordinate pair > 5 miles from US border
            5. Coordinate pair >> 5 miles from US border
            """
            (r, d) = REopt.avert_region_abbreviation(65.27661752129738, -149.59278391820223)
            @test r == "AKGD"
            (r, d) = REopt.avert_region_abbreviation(21.45440792261567, -157.93648793163402)
            @test r == "HIOA"
            (r, d) = REopt.avert_region_abbreviation(19.686877556659436, -155.4223641905743)
            @test r == "HIMS"
            (r, d) = REopt.avert_region_abbreviation(39.86357200140234, -104.67953917092028)
            @test r == "RM"
            @test d ≈ 0.0 atol=1
            (r, d) = REopt.avert_region_abbreviation(47.49137892652077, -69.3240287592685)
            @test r == "NE"
            @test d ≈ 7986 atol=1
            (r, d) = REopt.avert_region_abbreviation(47.50448307102053, -69.34882434376593)
            @test r === nothing
            @test d ≈ 10297 atol=1
            (r, d) = REopt.avert_region_abbreviation(55.860334445251354, -4.286554357755312)
            @test r === nothing
        end

        @testset "PVspecs" begin
            ## Scenario 1: Palmdale, CA; array-type = 0 (Ground-mount)
            post_name = "pv.json" 
            post = JSON.parsefile("./scenarios/$post_name")
            scen = Scenario(post)
            @test scen.pvs[1].tilt ≈ 20
            @test scen.pvs[1].azimuth ≈ 180
        
            ## Scenario 2: Palmdale, CA; array-type = 1 (roof)
            post["PV"]["array_type"] = 1 
            scen = Scenario(post)
        
            @test scen.pvs[1].tilt ≈ 20 # Correct tilt value for array_type = 1
        
            ## Scenario 3: Palmdale, CA; array-type = 2 (axis-tracking)
            post["PV"]["array_type"] = 2
            scen = Scenario(post)
        
            @test scen.pvs[1].tilt ≈ 0 # Correct tilt value for array_type = 2
        
            ## Scenario 4: Cape Town; array-type = 0 (ground)
            post["Site"]["latitude"] = -33.974732
            post["Site"]["longitude"] = 19.130050
            post["PV"]["array_type"] = 0 
            scen = Scenario(post)
        
            @test scen.pvs[1].tilt ≈ 20
            @test scen.pvs[1].azimuth ≈ 0
            @test sum(scen.electric_utility.emissions_factor_series_lb_CO2_per_kwh) ≈ 0

            ## Scenario 4:Cape Town; array-type = 0 (ground); user-provided tilt (should not get overwritten)
            post["PV"]["tilt"] = 17
            scen = Scenario(post)
            @test scen.pvs[1].tilt ≈ 17
        end

        @testset "AlternativeFlatLoads" begin
            input_data = JSON.parsefile("./scenarios/flatloads.json")
            s = Scenario(input_data)
            inputs = REoptInputs(s)

            # FlatLoad_8_5 => 8 hrs/day, 5 days/week, 52 weeks/year
            active_hours_8_5 = 8 * 5 * 52
            @test count(x->x>0, s.space_heating_load.loads_kw, dims=1)[1] == active_hours_8_5
            # FlatLoad_16_7 => only hours 6-22 should be >0, and each day is the same portion of the total year
            @test sum(s.electric_load.loads_kw[1:5]) + sum(s.electric_load.loads_kw[23:24]) == 0.0
            @test sum(s.electric_load.loads_kw[6:22]) / sum(s.electric_load.loads_kw) - 1/365 ≈ 0.0 atol=0.000001
        end
        
        # removed Wind test for two reasons
        # 1. reduce WindToolKit calls in tests
        # 2. HiGHS does not support SOS or indicator constraints, which are needed for export constraints
        
        @testset "Simulated load function consistency with REoptInputs.s (Scenario)" begin
            """

            This tests the consistency between getting DOE commercial reference building (CRB) load data
                from the simulated_load function and the processing of REoptInputs.s (Scenario struct).
                    
            The simulated_load function is used for the /simulated_load endpoint in the REopt API,
                in particular for the webtool/UI to display loads before running REopt, but is also generally
                an external way to access CRB load data without running REopt.

            One particular test specifically for the webtool/UI is for the heating load because there is just a 
                single heating load instead of separated space heating and domestic hot water loads.
            
            """
            input_data = JSON.parsefile("./scenarios/simulated_load.json")

            input_data["ElectricLoad"] = Dict([("blended_doe_reference_names", ["Hospital", "FlatLoad_16_5"]),
                                            ("blended_doe_reference_percents", [0.2, 0.8])
                                        ])
            
            input_data["CoolingLoad"] = Dict([("blended_doe_reference_names", ["Warehouse", "FlatLoad"]),
                                            ("blended_doe_reference_percents", [0.5, 0.5])
                                        ])
            
            # Heating load from the UI will call the /simulated_load endpoint first to parse single heating mmbtu into separate Space and DHW mmbtu
            annual_mmbtu_hvac = 7000.0
            annual_mmbtu_process = 3000.0
            doe_reference_name_heating = ["Warehouse", "FlatLoad"]
            percent_share_heating = [0.3, 0.7]
            
            d_sim_load_heating = Dict([("latitude", input_data["Site"]["latitude"]),
                                        ("longitude", input_data["Site"]["longitude"]),
                                        ("load_type", "heating"),  # since annual_tonhour is not given
                                        ("doe_reference_name", doe_reference_name_heating),
                                        ("percent_share", percent_share_heating),
                                        ("annual_mmbtu", annual_mmbtu_hvac)
                                        ])
            
            sim_load_response_heating = simulated_load(d_sim_load_heating)
            
            d_sim_load_process = copy(d_sim_load_heating)
            d_sim_load_process["load_type"] = "process_heat"
            delete!(d_sim_load_process, "doe_reference_name")
            d_sim_load_process["industrial_reference_name"] = doe_reference_name_heating            
            d_sim_load_process["annual_mmbtu"] = annual_mmbtu_process
            sim_load_response_process = simulated_load(d_sim_load_process)
            
            input_data["SpaceHeatingLoad"] = Dict([("blended_doe_reference_names", doe_reference_name_heating),
                                            ("blended_doe_reference_percents", percent_share_heating),
                                            ("annual_mmbtu", sim_load_response_heating["space_annual_mmbtu"])
                                        ])
            
            input_data["DomesticHotWaterLoad"] = Dict([("blended_doe_reference_names", doe_reference_name_heating),
                                            ("blended_doe_reference_percents", percent_share_heating),
                                            ("annual_mmbtu", sim_load_response_heating["dhw_annual_mmbtu"])
                                        ])
            
            input_data["ProcessHeatLoad"] = Dict([("blended_industrial_reference_names", doe_reference_name_heating),
                                            ("blended_industrial_reference_percents", percent_share_heating),
                                            ("annual_mmbtu", annual_mmbtu_process)
                                        ])                            
                            
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            
            # Call simulated_load function to check cooling
            d_sim_load_elec_and_cooling = Dict([("latitude", input_data["Site"]["latitude"]),
                                                ("longitude", input_data["Site"]["longitude"]),
                                                ("load_type", "electric"),  # since annual_tonhour is not given
                                                ("doe_reference_name", input_data["ElectricLoad"]["blended_doe_reference_names"]),
                                                ("percent_share", input_data["ElectricLoad"]["blended_doe_reference_percents"]),
                                                ("cooling_doe_ref_name", input_data["CoolingLoad"]["blended_doe_reference_names"]),
                                                ("cooling_pct_share", input_data["CoolingLoad"]["blended_doe_reference_percents"]),                    
                                                ])
            
            sim_load_response_elec_and_cooling = simulated_load(d_sim_load_elec_and_cooling)
            sim_electric_kw = sim_load_response_elec_and_cooling["loads_kw"]
            sim_cooling_ton = sim_load_response_elec_and_cooling["cooling_defaults"]["loads_ton"]
            
            total_heating_thermal_load_reopt_inputs = (s.space_heating_load.loads_kw + s.dhw_load.loads_kw + s.process_heat_load.loads_kw) ./ REopt.KWH_PER_MMBTU ./ REopt.EXISTING_BOILER_EFFICIENCY
            
            @test round.(sim_load_response_heating["loads_mmbtu_per_hour"] + 
                    sim_load_response_process["loads_mmbtu_per_hour"], digits=2) ≈ 
                    round.(total_heating_thermal_load_reopt_inputs, digits=2) rtol=0.02
            
            @test sim_electric_kw ≈ s.electric_load.loads_kw atol=0.1
            @test sim_cooling_ton ≈ s.cooling_load.loads_kw_thermal ./ REopt.KWH_THERMAL_PER_TONHOUR atol=0.1   
        end

        @testset verbose=true "Backup Generator Reliability" begin

            @testset "Compare backup_reliability and simulate_outages" begin
                # Tests ensure `backup_reliability()` consistent with `simulate_outages()`
                # First, just battery
                reopt_inputs = Dict(
                    "Site" => Dict(
                        "longitude" => -106.42077256104001,
                        "latitude" => 31.810468380036337
                    ),
                    "ElectricStorage" => Dict(
                        "min_kw" => 4000,
                        "max_kw" => 4000,
                        "min_kwh" => 400000,
                        "max_kwh" => 400000,
                        "soc_min_fraction" => 0.8,
                        "soc_init_fraction" => 0.9
                    ),
                    "ElectricLoad" => Dict(
                        "doe_reference_name" => "FlatLoad",
                        "annual_kwh" => 175200000.0,
                        "critical_load_fraction" => 0.2
                    ),
                    "ElectricTariff" => Dict(
                        "urdb_label" => "5ed6c1a15457a3367add15ae"
                    ),
                )
                p = REoptInputs(reopt_inputs)
                model = Model(optimizer_with_attributes(HiGHS.Optimizer,"output_flag" => false, "log_to_console" => false))
                results = run_reopt(model, p)
                simresults = simulate_outages(results, p)

                reliability_inputs = Dict(
                    "generator_size_kw" => 0,
                    "max_outage_duration" => 100,
                    "generator_operational_availability" => 1.0, 
                    "generator_failure_to_start" => 0.0, 
                    "generator_mean_time_to_failure" => 10000000000,
                    "fuel_limit" => 0,
                    "battery_size_kw" => 4000,
                    "battery_size_kwh" => 400000,
                    "battery_charge_efficiency" => 1,
                    "battery_discharge_efficiency" => 1,
                    "battery_operational_availability" => 1.0,
                    "battery_minimum_soc_fraction" => 0.0,
                    "battery_starting_soc_series_fraction" => results["ElectricStorage"]["soc_series_fraction"],
                    "critical_loads_kw" => results["ElectricLoad"]["critical_load_series_kw"]#4000*ones(8760)#p.s.electric_load.critical_loads_kw
                )
                reliability_results = backup_reliability(reliability_inputs)

                #TODO: resolve bug where unlimted fuel markov portion of results goes to zero 1 timestep early
                for i = 1:99#min(length(simresults["probs_of_surviving"]), reliability_inputs["max_outage_duration"])
                    @test simresults["probs_of_surviving"][i] ≈ reliability_results["mean_cumulative_survival_by_duration"][i] atol=0.01
                    @test simresults["probs_of_surviving"][i] ≈ reliability_results["unlimited_fuel_mean_cumulative_survival_by_duration"][i] atol=0.01
                    @test simresults["probs_of_surviving"][i] ≈ reliability_results["mean_fuel_survival_by_duration"][i] atol=0.01
                end
                finalize(backend(model))
                empty!(model)
                GC.gc()                

                # Second, gen, PV, Wind, battery
                reopt_inputs = JSON.parsefile("./scenarios/backup_reliability_reopt_inputs.json")
                reopt_inputs["ElectricLoad"]["annual_kwh"] = 4*reopt_inputs["ElectricLoad"]["annual_kwh"]
                p = REoptInputs(reopt_inputs)
                model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(model, p)
                simresults = simulate_outages(results, p)
                reliability_inputs = Dict(
                    "max_outage_duration" => 48,
                    "generator_operational_availability" => 1.0, 
                    "generator_failure_to_start" => 0.0, 
                    "generator_mean_time_to_failure" => 10000000000,
                    "fuel_limit" => 1000000000,
                    "battery_operational_availability" => 1.0,
                    "battery_minimum_soc_fraction" => 0.0,
                    "pv_operational_availability" => 1.0,
                    "wind_operational_availability" => 1.0
                )
                reliability_results = backup_reliability(results, p, reliability_inputs)
                for i = 1:min(length(simresults["probs_of_surviving"]), reliability_inputs["max_outage_duration"])
                    @test simresults["probs_of_surviving"][i] ≈ reliability_results["mean_cumulative_survival_by_duration"][i] atol=0.001
                end
                finalize(backend(model))
                empty!(model)
                GC.gc()                
            end

            # Test survival with no generator decreasing and same as with generator but no fuel
            reliability_inputs = Dict(
                "critical_loads_kw" => 200 .* (2 .+ sin.(collect(1:8760)*2*pi/24)),
                "num_generators" => 0,
                "generator_size_kw" => 312.0,
                "fuel_limit" => 0.0,
                "max_outage_duration" => 10,
                "battery_size_kw" => 428.0,
                "battery_size_kwh" => 1585.0,
                "num_battery_bins" => 5
            )
            reliability_results1 = backup_reliability(reliability_inputs)
            reliability_inputs["generator_size_kw"] = 0
            reliability_inputs["fuel_limit"] = 1e10
            reliability_results2 = backup_reliability(reliability_inputs)
            for i in 1:reliability_inputs["max_outage_duration"]
                if i != 1
                    @test reliability_results1["mean_fuel_survival_by_duration"][i] <= reliability_results1["mean_fuel_survival_by_duration"][i-1]
                    @test reliability_results1["mean_cumulative_survival_by_duration"][i] <= reliability_results1["mean_cumulative_survival_by_duration"][i-1]
                end
                @test reliability_results2["mean_fuel_survival_by_duration"][i] == reliability_results1["mean_fuel_survival_by_duration"][i]
            end

            #test fuel limit
            input_dict = JSON.parsefile("./scenarios/erp_fuel_limit_inputs.json")
            results = backup_reliability(input_dict)
            @test results["unlimited_fuel_cumulative_survival_final_time_step"][1] ≈ 1
            @test results["cumulative_survival_final_time_step"][1] ≈ 1

            input_dict = Dict(
                "critical_loads_kw" => [1,2,2,1],
                "battery_starting_soc_series_fraction" => [0.75,0.75,0.75,0.75],
                "max_outage_duration" => 3,
                "num_generators" => 2, "generator_size_kw" => 1,
                "generator_operational_availability" => 1,
                "generator_failure_to_start" => 0.0,
                "generator_mean_time_to_failure" => 5,
                "battery_operational_availability" => 1,
                "num_battery_bins" => 3,
                "battery_size_kwh" => 4,
                "battery_size_kw" => 1,
                "battery_charge_efficiency" => 1,
                "battery_discharge_efficiency" => 1,
                "battery_minimum_soc_fraction" => 0.5)
            

            #Given outage starts in time period 1
            #____________________________________
            #Outage hour 1:
            #2 generators:         Prob = 0.64,     Battery = 2, Survived
            #1 generator:          Prob = 0.32,     Battery = 1, Survived
            #0 generator:          Prob = 0.04,     Battery = 0, Survived
            #Survival Probability 1.0

            #Outage hour 2:
            #2 generators:         Prob = 0.4096,   Battery = 2, Survived
            #2 gen -> 1 gen:       Prob = 0.2048,   Battery = 1, Survived
            #1 gen -> 1 gen:       Prob = 0.256,    Battery = 0, Survived
            #0 generators:         Prob = 0.1296,   Battery = -1, Failed
            #Survival Probability: 0.8704

            #Outage hour 3:
            #2 generators:         Prob = 0.262144, Battery = 0, Survived
            #2 gen -> 2 -> 1       Prob = 0.131072, Battery = 1, Survived
            #2 gen -> 1 -> 1       Prob = 0.16384,  Battery = 0, Survived
            #1 gen -> 1 -> 1       Prob = 0.2048,   Battery = -1, Failed
            #0 generators          Prob = 0.238144, Battery = -1, Failed
            #Survival Probability: 0.557056        
            @test backup_reliability(input_dict)["unlimited_fuel_cumulative_survival_final_time_step"][1] ≈ 0.557056

            #Test multiple generator types
            input_dict = Dict(
                "critical_loads_kw" => [1,2,2,1], 
                "battery_starting_soc_series_fraction" => [0.5,0.5,0.5,0.5],
                "max_outage_duration" => 3,
                "num_generators" => [1,1],
                "generator_size_kw" => [1,1],
                "generator_operational_availability" => [1,1],
                "generator_failure_to_start" => [0.0, 0.0],
                "generator_mean_time_to_failure" => [5, 5], 
                "battery_operational_availability" => 1.0,
                "num_battery_bins" => 3,
                "battery_size_kwh" => 2,
                "battery_size_kw" => 1,
                "battery_charge_efficiency" => 1,
                "battery_discharge_efficiency" => 1,
                "battery_minimum_soc_fraction" => 0)

            @test backup_reliability(input_dict)["unlimited_fuel_cumulative_survival_final_time_step"][1] ≈ 0.557056

            #8760 of flat load. Battery can survive 4 hours. 
            #Survival after 24 hours should be chance of generator surviving 20 or more hours
            input_dict = Dict(
                "critical_loads_kw" => 100 .* ones(8760),
                "max_outage_duration" => 24,
                "num_generators" => 1,
                "generator_size_kw" => 100,
                "generator_operational_availability" => 0.98,
                "generator_failure_to_start" => 0.1,
                "generator_mean_time_to_failure" => 100,
                "battery_operational_availability" => 1.0,
                "num_battery_bins" => 101,
                "battery_size_kwh" => 400,
                "battery_size_kw" => 100,
                "battery_charge_efficiency" => 1,
                "battery_discharge_efficiency" => 1,
                "battery_minimum_soc_fraction" => 0)

            reliability_results = backup_reliability(input_dict)
            @test reliability_results["unlimited_fuel_mean_cumulative_survival_by_duration"][24] ≈ (0.99^20)*(0.9*0.98) atol=0.00001

            #More complex case of hospital load with 2 generators, PV, wind, and battery
            reliability_inputs = JSON.parsefile("./scenarios/backup_reliability_inputs.json")
            reliability_results = backup_reliability(reliability_inputs)
            @test reliability_results["unlimited_fuel_cumulative_survival_final_time_step"][1] ≈ 0.858756 atol=0.0001
            @test reliability_results["cumulative_survival_final_time_step"][1] ≈ 0.858756 atol=0.0001
            @test reliability_results["mean_cumulative_survival_final_time_step"] ≈ 0.904242 atol=0.0001#0.833224
                    
            # Test gens+pv+wind+batt with 3 arg version of backup_reliability
            # Attention! REopt optimization results are presaved in erp_gens_batt_pv_wind_reopt_results.json
            # If you modify backup_reliability_reopt_inputs.json, you must add this before JSON.parsefile:
            # results = run_reopt(model, p)
            # open("scenarios/erp_gens_batt_pv_wind_reopt_results.json","w") do f
            #     JSON.print(f, results, 4)
            # end
            for input_key in [
                        "generator_size_kw",
                        "battery_size_kw",
                        "battery_size_kwh",
                        "pv_size_kw",
                        "wind_size_kw",
                        "critical_loads_kw",
                        "pv_production_factor_series",
                        "wind_production_factor_series"
                    ]
                delete!(reliability_inputs, input_key)
            end
            # note: the wind prod series in backup_reliability_reopt_inputs.json is actually a PV profile (to in order to test a wind scenario that should give same results as an existing PV one)
            p = REoptInputs("./scenarios/backup_reliability_reopt_inputs.json")
            results = JSON.parsefile("./scenarios/erp_gens_batt_pv_wind_reopt_results.json")
            reliability_results = backup_reliability(results, p, reliability_inputs)

            @test reliability_results["unlimited_fuel_cumulative_survival_final_time_step"][1] ≈ 0.802997 atol=0.0001
            @test reliability_results["cumulative_survival_final_time_step"][1] ≈ 0.802997 atol=0.0001
            @test reliability_results["mean_cumulative_survival_final_time_step"] ≈ 0.817586 atol=0.001
        end  

        @testset verbose=true "Disaggregated Heating Loads" begin
            @testset "Process Heat Load Inputs" begin
                d = JSON.parsefile("./scenarios/electric_heater.json")
                d["SpaceHeatingLoad"]["annual_mmbtu"] = 0.5 * 8760
                d["DomesticHotWaterLoad"]["annual_mmbtu"] = 0.5 * 8760
                d["ProcessHeatLoad"]["annual_mmbtu"] = 0.5 * 8760
                s = Scenario(d)
                inputs = REoptInputs(s)
                @test inputs.heating_loads_kw["ProcessHeat"][1] ≈ 117.228428 atol=1.0e-3
            end
            @testset "Separate Heat Load Results" begin
                d = JSON.parsefile("./scenarios/electric_heater.json")
                d["SpaceHeatingLoad"]["annual_mmbtu"] = 0.5 * 8760
                d["DomesticHotWaterLoad"]["annual_mmbtu"] = 0.5 * 8760
                d["ProcessHeatLoad"]["annual_mmbtu"] = 0.5 * 8760
                d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = 100
                d["ElectricHeater"]["installed_cost_per_mmbtu_per_hour"] = 1.0
                d["ElectricTariff"]["monthly_energy_rates"] = [0,0,0,0,0,0,0,0,0,0,0,0]
                d["HotThermalStorage"]["max_gal"] = 0.0
                d["HotThermalStorage"]["min_gal"] = 0.0
                s = Scenario(d)
                inputs = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, inputs)
                @test sum(results["ExistingBoiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.01
                @test sum(results["ExistingBoiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.01
                @test sum(results["ExistingBoiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 0.8*4380.0 atol=0.01
                @test sum(results["ElectricHeater"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 0.8*4380.0 atol=0.01
                @test sum(results["ElectricHeater"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 0.8*4380.0 atol=0.01
                @test sum(results["ElectricHeater"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.01
                finalize(backend(m))
                empty!(m)
                GC.gc()                
            end
        end

        @testset verbose=true "Net Metering" begin
            @testset "Net Metering Limit and Wholesale" begin
                #case 1: net metering limit is met by PV
                d = JSON.parsefile("./scenarios/net_metering.json")
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, d)
                @test results["PV"]["size_kw"] ≈ 30.0 atol=1e-3
        
                #case 2: wholesale rate is high, big-M is met
                d["ElectricTariff"]["wholesale_rate"] = 5.0
                d["PV"]["can_wholesale"] = true
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, d)
                @test results["PV"]["size_kw"] ≈ 7440.0 atol=1e-3  #max benefit provides the upper bound

                #case 3: net metering limit is exceeded, no WHL, and min RE % 
                d["ElectricTariff"]["wholesale_rate"] = 0
                d["PV"]["min_kw"] = 50
                d["Site"]["renewable_electricity_min_fraction"] = 0.35
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, d)
                @test sum(results["PV"]["electric_to_grid_series_kw"]) ≈ 0.0 atol=1e-3
                @test results["ElectricTariff"]["lifecycle_export_benefit_after_tax"] ≈ 0.0 atol=1e-3        
                finalize(backend(m))
                empty!(m)
                GC.gc()    
            end
        end

        @testset "Heating loads and addressable load fraction" begin
            # Default LargeOffice CRB with SpaceHeatingLoad and DomesticHotWaterLoad are served by ExistingBoiler
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, "./scenarios/thermal_load.json")
        
            @test round(results["ExistingBoiler"]["annual_fuel_consumption_mmbtu"], digits=0) ≈ 12904
            finalize(backend(m))
            empty!(m)
            GC.gc()
            
            # Hourly fuel load inputs with addressable_load_fraction are served as expected
            data = JSON.parsefile("./scenarios/thermal_load.json")

            data["DomesticHotWaterLoad"]["fuel_loads_mmbtu_per_hour"] = repeat([0.5], 8760)
            data["DomesticHotWaterLoad"]["addressable_load_fraction"] = 0.6
            data["SpaceHeatingLoad"]["fuel_loads_mmbtu_per_hour"] = repeat([0.5], 8760)
            data["SpaceHeatingLoad"]["addressable_load_fraction"] = 0.8
            data["ProcessHeatLoad"]["fuel_loads_mmbtu_per_hour"] = repeat([0.3], 8760)
            data["ProcessHeatLoad"]["addressable_load_fraction"] = 0.7

            s = Scenario(data)
            inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, inputs)
            @test round(results["ExistingBoiler"]["annual_fuel_consumption_mmbtu"], digits=0) ≈ 8760 * (0.5 * 0.6 + 0.5 * 0.8 + 0.3 * 0.7) atol = 1.0
            
            # Test for unaddressable heating load fuel and emissions outputs
            unaddressable = results["HeatingLoad"]["annual_total_unaddressable_heating_load_mmbtu"]
            addressable = results["HeatingLoad"]["annual_calculated_total_heating_boiler_fuel_load_mmbtu"]
            total = unaddressable + addressable
            # Find the weighted average addressable_load_fraction from the fractions and loads above
            weighted_avg_addressable_fraction = (0.5 * 0.6 + 0.5 * 0.8 + 0.3 * 0.7) / (0.5 + 0.5 + 0.3)
            @test round(abs(addressable / total - weighted_avg_addressable_fraction), digits=3) == 0

            unaddressable_emissions = results["HeatingLoad"]["annual_emissions_from_unaddressable_heating_load_tonnes_CO2"]
            addressable_site_fuel_emissions = results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"]
            total_site_emissions = unaddressable_emissions + addressable_site_fuel_emissions
            @test round(abs(addressable_site_fuel_emissions / total_site_emissions - weighted_avg_addressable_fraction), digits=3) == 0
            
            # Monthly fuel load input with addressable_load_fraction is processed to expected thermal load
            data = JSON.parsefile("./scenarios/thermal_load.json")
            data["DomesticHotWaterLoad"]["monthly_mmbtu"] = repeat([100], 12)
            data["DomesticHotWaterLoad"]["addressable_load_fraction"] = repeat([0.6], 12)
            data["SpaceHeatingLoad"]["monthly_mmbtu"] = repeat([200], 12)
            data["SpaceHeatingLoad"]["addressable_load_fraction"] = repeat([0.8], 12)
            data["ProcessHeatLoad"]["monthly_mmbtu"] = repeat([150], 12)
            data["ProcessHeatLoad"]["addressable_load_fraction"] = repeat([0.7], 12)

            # Assuming Scenario and REoptInputs are defined functions/classes in your code
            s = Scenario(data)
            inputs = REoptInputs(s)

            dhw_thermal_load_expected = sum(data["DomesticHotWaterLoad"]["monthly_mmbtu"] .* data["DomesticHotWaterLoad"]["addressable_load_fraction"]) * s.existing_boiler.efficiency
            space_thermal_load_expected = sum(data["SpaceHeatingLoad"]["monthly_mmbtu"] .* data["SpaceHeatingLoad"]["addressable_load_fraction"]) * s.existing_boiler.efficiency
            process_thermal_load_expected = sum(data["ProcessHeatLoad"]["monthly_mmbtu"] .* data["ProcessHeatLoad"]["addressable_load_fraction"]) * s.existing_boiler.efficiency

            @test round(sum(s.dhw_load.loads_kw) / REopt.KWH_PER_MMBTU) ≈ sum(dhw_thermal_load_expected)
            @test round(sum(s.space_heating_load.loads_kw) / REopt.KWH_PER_MMBTU) ≈ sum(space_thermal_load_expected)
            @test round(sum(s.process_heat_load.loads_kw) / REopt.KWH_PER_MMBTU) ≈ sum(process_thermal_load_expected)
            finalize(backend(m))
            empty!(m)
            GC.gc()             
        end
        
        @testset verbose=true "CHP" begin
            @testset "CHP Sizing" begin
                # Sizing CHP with non-constant efficiency, no cost curve, no unavailability_periods
                data_sizing = JSON.parsefile("./scenarios/chp_sizing.json")
                s = Scenario(data_sizing)
                inputs = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01, "presolve" => "on"))
                results = run_reopt(m, inputs)
            
                @test round(results["CHP"]["size_kw"], digits=0) ≈ 263.0 atol=50.0
                @test round(results["Financial"]["lcc"], digits=0) ≈ 1.11e7 rtol=0.05
                finalize(backend(m))
                empty!(m)
                GC.gc()

                # Test constrained CAPEX
                initial_capex_no_incentives = results["Financial"]["initial_capital_costs"]
                min_capex = initial_capex_no_incentives * 1.3
                model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                data_sizing["Financial"]["min_initial_capital_costs_before_incentives"] = min_capex
                results = run_reopt(model, data_sizing)
                @test results["Financial"]["initial_capital_costs"] ≈ min_capex rtol=1e-5
                finalize(backend(model))
                empty!(model)
                GC.gc()                
            end
        
            @testset "CHP Cost Curve and Min Allowable Size" begin
                # Fixed size CHP with cost curve, no unavailability_periods
                data_cost_curve = JSON.parsefile("./scenarios/chp_sizing.json")
                data_cost_curve["CHP"] = Dict()
                data_cost_curve["CHP"]["prime_mover"] = "recip_engine"
                data_cost_curve["CHP"]["size_class"] = 1
                data_cost_curve["CHP"]["fuel_cost_per_mmbtu"] = 8.0
                data_cost_curve["CHP"]["min_kw"] = 0
                data_cost_curve["CHP"]["min_allowable_kw"] = 555.5
                data_cost_curve["CHP"]["max_kw"] = 555.51
                data_cost_curve["CHP"]["installed_cost_per_kw"] = 1800.0
                data_cost_curve["CHP"]["installed_cost_per_kw"] = [2300.0, 1800.0, 1500.0]
                data_cost_curve["CHP"]["tech_sizes_for_cost_curve"] = [100.0, 300.0, 1140.0]
            
                data_cost_curve["CHP"]["federal_itc_fraction"] = 0.1
                data_cost_curve["CHP"]["macrs_option_years"] = 0
                data_cost_curve["CHP"]["macrs_bonus_fraction"] = 0.0
                data_cost_curve["CHP"]["macrs_itc_reduction"] = 0.0
            
                expected_x = data_cost_curve["CHP"]["min_allowable_kw"]
                cap_cost_y = data_cost_curve["CHP"]["installed_cost_per_kw"]
                cap_cost_x = data_cost_curve["CHP"]["tech_sizes_for_cost_curve"]
                slope = (cap_cost_x[3] * cap_cost_y[3] - cap_cost_x[2] * cap_cost_y[2]) / (cap_cost_x[3] - cap_cost_x[2])
                init_capex_chp_expected = cap_cost_x[2] * cap_cost_y[2] + (expected_x - cap_cost_x[2]) * slope
                lifecycle_capex_chp_expected = init_capex_chp_expected - 
                    REopt.npv(data_cost_curve["Financial"]["offtaker_discount_rate_fraction"], 
                    [0, init_capex_chp_expected * data_cost_curve["CHP"]["federal_itc_fraction"]])
            
                #PV
                data_cost_curve["PV"] = Dict()
                data_cost_curve["PV"]["min_kw"] = 1500
                data_cost_curve["PV"]["max_kw"] = 1500
                data_cost_curve["PV"]["installed_cost_per_kw"] = 1600
                data_cost_curve["PV"]["federal_itc_fraction"] = 0.26
                data_cost_curve["PV"]["macrs_option_years"] = 0
                data_cost_curve["PV"]["macrs_bonus_fraction"] = 0.0
                data_cost_curve["PV"]["macrs_itc_reduction"] = 0.0
            
                init_capex_pv_expected = data_cost_curve["PV"]["max_kw"] * data_cost_curve["PV"]["installed_cost_per_kw"]
                lifecycle_capex_pv_expected = init_capex_pv_expected - 
                    REopt.npv(data_cost_curve["Financial"]["offtaker_discount_rate_fraction"], 
                    [0, init_capex_pv_expected * data_cost_curve["PV"]["federal_itc_fraction"]])
            
                s = Scenario(data_cost_curve)
                inputs = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
                results = run_reopt(m, inputs)
            
                init_capex_total_expected = init_capex_chp_expected + init_capex_pv_expected
                lifecycle_capex_total_expected = lifecycle_capex_chp_expected + lifecycle_capex_pv_expected
            
                # Check initial CapEx (pre-incentive/tax) and life cycle CapEx (post-incentive/tax) cost with expect
                @test init_capex_total_expected ≈ results["Financial"]["initial_capital_costs"] atol=0.0001*init_capex_total_expected
                @test lifecycle_capex_total_expected ≈ results["Financial"]["initial_capital_costs_after_incentives"] atol=0.0001*lifecycle_capex_total_expected
            
                # Test CHP.min_allowable_kw - the size would otherwise be ~100 kW less by setting min_allowable_kw to zero
                @test results["CHP"]["size_kw"] ≈ data_cost_curve["CHP"]["min_allowable_kw"] atol=0.1
                finalize(backend(m))
                empty!(m)
                GC.gc()
            end
        
            @testset "CHP Unavailability and Outage" begin
                """
                Validation to ensure that:
                    1) CHP meets load during outage without exporting
                    2) CHP never exports if chp.can_wholesale and chp.can_net_meter inputs are False (default)
                    3) CHP does not "curtail", i.e. send power to a load bank when chp.can_curtail is False (default)
                    4) CHP min_turn_down_fraction is ignored during an outage
                    5) Cooling tech production gets zeroed out during the outage period because we ignore the cooling load balance for outage
                    6) Unavailability intervals that intersect with grid-outages get ignored
                    7) Unavailability intervals that do not intersect with grid-outages result in no CHP production
                """
                # Sizing CHP with non-constant efficiency, no cost curve, no unavailability_periods
                data = JSON.parsefile("./scenarios/chp_unavailability_outage.json")
            
                # Add unavailability periods that 1) intersect (ignored) and 2) don't intersect with outage period
                data["CHP"]["unavailability_periods"] = [Dict([("month", 1), ("start_week_of_month", 2),
                        ("start_day_of_week", 1), ("start_hour", 1), ("duration_hours", 8)]),
                        Dict([("month", 1), ("start_week_of_month", 2),
                        ("start_day_of_week", 3), ("start_hour", 9), ("duration_hours", 8)])]
            
                # Manually doing the math from the unavailability defined above
                unavail_1_start = 24 + 1
                unavail_1_end = unavail_1_start + 8 - 1
                unavail_2_start = 24*3 + 9
                unavail_2_end = unavail_2_start + 8 - 1
                
                # Specify the CHP.min_turn_down_fraction which is NOT used during an outage
                data["CHP"]["min_turn_down_fraction"] = 0.5
                # Specify outage period; outage time_steps are 1-indexed
                outage_start = unavail_1_start
                data["ElectricUtility"]["outage_start_time_step"] = outage_start
                outage_end = unavail_1_end
                data["ElectricUtility"]["outage_end_time_step"] = outage_end
                data["ElectricLoad"]["critical_load_fraction"] = 0.25
            
                s = Scenario(data)
                inputs = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
                results = run_reopt(m, inputs)
            
                tot_elec_load = results["ElectricLoad"]["load_series_kw"]
                chp_total_elec_prod = results["CHP"]["electric_production_series_kw"]
                chp_to_load = results["CHP"]["electric_to_load_series_kw"]
                chp_export = results["CHP"]["electric_to_grid_series_kw"]
                cooling_elec_consumption = results["ExistingChiller"]["electric_consumption_series_kw"]
            
                # The values compared to the expected values
                @test sum([(chp_to_load[i] - tot_elec_load[i]*data["ElectricLoad"]["critical_load_fraction"]) for i in outage_start:outage_end]) ≈ 0.0 atol=0.001
                critical_load = tot_elec_load[outage_start:outage_end] * data["ElectricLoad"]["critical_load_fraction"]
                @test sum(chp_to_load[outage_start:outage_end]) ≈ sum(critical_load) atol=0.1
                @test sum(chp_export) == 0.0
                @test sum(chp_total_elec_prod) ≈ sum(chp_to_load) atol=1.0e-5*sum(chp_total_elec_prod)
                @test sum(cooling_elec_consumption[outage_start:outage_end]) == 0.0
                @test sum(chp_total_elec_prod[unavail_2_start:unavail_2_end]) == 0.0  
                finalize(backend(m))
                empty!(m)
                GC.gc()
            end
        
            @testset "CHP Supplementary firing and standby" begin
                """
                Test to ensure that supplementary firing and standby charges work as intended.  The thermal and 
                electrical loads are constant, and the CHP system size is fixed; the supplementary firing has a
                similar cost to the boiler and is purcahsed and used when the boiler efficiency is set to a lower 
                value than that of the supplementary firing. The test also ensures that demand charges are  
                correctly calculated when CHP is and is not allowed to reduce demand charges.
                """
                data = JSON.parsefile("./scenarios/chp_supplementary_firing.json")
                data["CHP"]["supplementary_firing_capital_cost_per_kw"] = 10000
                data["ElectricLoad"]["loads_kw"] = repeat([800.0], 8760)
                data["ElectricLoad"]["year"] = 2022
                data["DomesticHotWaterLoad"]["fuel_loads_mmbtu_per_hour"] = repeat([6.0], 8760)
                data["SpaceHeatingLoad"]["fuel_loads_mmbtu_per_hour"] = repeat([6.0], 8760)
                #part 1: supplementary firing not used when less efficient than the boiler and expensive 
                m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                s = Scenario(data)
                inputs = REoptInputs(s)
                results = run_reopt(m1, inputs)
                @test results["CHP"]["size_kw"] == 800
                @test results["CHP"]["size_supplemental_firing_kw"] == 0
                @test results["CHP"]["annual_electric_production_kwh"] ≈ 800*8760 rtol=1e-5
                @test results["CHP"]["annual_thermal_production_mmbtu"] ≈ 800*(0.4418/0.3573)*8760/293.07107 rtol=1e-5
                @test results["ElectricTariff"]["lifecycle_demand_cost_after_tax"] == 0
                @test results["HeatingLoad"]["annual_calculated_total_heating_thermal_load_mmbtu"] == 12.0 * 8760 * data["ExistingBoiler"]["efficiency"]
                @test results["HeatingLoad"]["annual_calculated_dhw_thermal_load_mmbtu"] == 6.0 * 8760 * data["ExistingBoiler"]["efficiency"]
                @test results["HeatingLoad"]["annual_calculated_space_heating_thermal_load_mmbtu"] == 6.0 * 8760 * data["ExistingBoiler"]["efficiency"]
            
                #part 2: supplementary firing used when more efficient than the boiler and low-cost; demand charges not reduced by CHP
                data["CHP"]["supplementary_firing_capital_cost_per_kw"] = 10
                data["CHP"]["reduces_demand_charges"] = false
                data["ExistingBoiler"]["efficiency"] = 0.85
                m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                s = Scenario(data)
                inputs = REoptInputs(s)
                results = run_reopt(m2, inputs)
                @test results["CHP"]["size_supplemental_firing_kw"] ≈ 321.71 atol=0.1
                @test results["CHP"]["annual_thermal_production_mmbtu"] ≈ 149136.6 rtol=1e-5
                @test results["ElectricTariff"]["lifecycle_demand_cost_after_tax"] ≈ 5212.7 rtol=1e-5
                finalize(backend(m1))
                empty!(m1)
                finalize(backend(m2))
                empty!(m2)
                GC.gc()
            end

            @testset "CHP to Waste Heat" begin
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
                d = JSON.parsefile("./scenarios/chp_waste.json")
                results = run_reopt(m, d)
                @test sum(results["CHP"]["thermal_curtailed_series_mmbtu_per_hour"]) ≈ 4174.455 atol=1e-3
                finalize(backend(m))
                empty!(m)
                GC.gc()
            end

            @testset "CHP Proforma Metrics" begin
                # This test compares the resulting simple payback period (years) for CHP to a proforma spreadsheet model which has been verified
                # All financial parameters which influence this calc have been input to avoid breaking with changing defaults
                input_data = JSON.parsefile("./scenarios/chp_payback.json")
                s = Scenario(input_data)
                inputs = REoptInputs(s)

                m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
                m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
                results = run_reopt([m1,m2], inputs)
                @test abs(results["Financial"]["simple_payback_years"] - 8.31) <= 0.02
                finalize(backend(m1))
                empty!(m1)
                finalize(backend(m2))
                empty!(m2)
                GC.gc()
            end
        end
        
        @testset verbose=true "FlexibleHVAC" begin
        
            @testset "Single RC Model heating only" begin
                #=
                Single RC model:
                1 state/control node
                2 inputs: Ta and Qheat
                A = [1/(RC)], B = [1/(RC) 1/C], u = [Ta; Q]
                NOTE exogenous_inputs (u) allows for parasitic heat, but it is input as zeros here
        
                We start with no technologies except ExistingBoiler and ExistingChiller. 
                FlexibleHVAC is only worth purchasing if its cost is neglible (i.e. below the lcc_bau * MIPTOL) 
                or if there is a time-varying fuel and/or electricity cost 
                (and the FlexibleHVAC installed_cost is less than the achievable savings).
                =#
        
                # Austin, TX -> existing_chiller and existing_boiler added with FlexibleHVAC
                pf, tamb = REopt.call_pvwatts_api(30.2672, -97.7431);
                R = 0.00025  # K/kW
                C = 1e5   # kJ/K
                # the starting scenario has flat fuel and electricty costs
                d = JSON.parsefile("./scenarios/thermal_load.json");
                A = reshape([-1/(R*C)], 1,1)
                B = [1/(R*C) 1/C]
                u = [tamb zeros(8760)]';
                d["FlexibleHVAC"] = Dict(
                    "control_node" => 1,
                    "initial_temperatures" => [21],
                    "temperature_upper_bound_degC" => 22.0,
                    "temperature_lower_bound_degC" => 19.8,
                    "installed_cost" => 300.0, # NOTE cost must be more then the MIPTOL * LCC 5e-5 * 5.79661e6 ≈ 290 to make FlexibleHVAC not worth it
                    "system_matrix" => A,
                    "input_matrix" => B,
                    "exogenous_inputs" => u
                )
        
                m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                r = run_reopt([m1,m2], d)
                @test (occursin("not supported by the solver", string(r["Messages"]["errors"])) || occursin("REopt scenarios solved either with errors or non-optimal solutions", string(r["Messages"]["errors"])))
                # @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === false
                # @test r["Financial"]["npv"] == 0
                finalize(backend(m1))
                empty!(m1)
                finalize(backend(m2))
                empty!(m2)
                GC.gc()
                
                # put in a time varying fuel cost, which should make purchasing the FlexibleHVAC system economical
                # with flat ElectricTariff the ExistingChiller does not benefit from FlexibleHVAC
                d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = rand(Float64, (8760))*(50-5).+5;
                m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
                m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
                r = run_reopt([m1,m2], d)
                @test (occursin("not supported by the solver", string(r["Messages"]["errors"])) || occursin("REopt scenarios solved either with errors or non-optimal solutions", string(r["Messages"]["errors"])))                
                # all of the savings are from the ExistingBoiler fuel costs
                # @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === true
                # fuel_cost_savings = r["ExistingBoiler"]["lifecycle_fuel_cost_after_tax_bau"] - r["ExistingBoiler"]["lifecycle_fuel_cost_after_tax"]
                # @test fuel_cost_savings - d["FlexibleHVAC"]["installed_cost"] ≈ r["Financial"]["npv"] atol=0.1
                finalize(backend(m1))
                empty!(m1)
                finalize(backend(m2))
                empty!(m2)
                GC.gc()        

                # now increase the FlexibleHVAC installed_cost to the fuel costs savings + 100 and expect that the FlexibleHVAC is not purchased
                # d["FlexibleHVAC"]["installed_cost"] = fuel_cost_savings + 100
                m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
                m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
                r = run_reopt([m1,m2], d)
                @test (occursin("not supported by the solver", string(r["Messages"]["errors"])) || occursin("REopt scenarios solved either with errors or non-optimal solutions", string(r["Messages"]["errors"])))
                finalize(backend(m1))
                empty!(m1)
                finalize(backend(m2))
                empty!(m2)
                GC.gc()                
                # @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === false
                # @test r["Financial"]["npv"] == 0
        
                # add TOU ElectricTariff and expect to benefit from using ExistingChiller intelligently
                d["ElectricTariff"] = Dict("urdb_label" => "5ed6c1a15457a3367add15ae")
        
                m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                r = run_reopt([m1,m2], d)
                @test (occursin("not supported by the solver", string(r["Messages"]["errors"])) || occursin("REopt scenarios solved either with errors or non-optimal solutions", string(r["Messages"]["errors"])))
                finalize(backend(m1))
                empty!(m1)
                finalize(backend(m2))
                empty!(m2)
                GC.gc()                

                # elec_cost_savings = r["ElectricTariff"]["lifecycle_demand_cost_after_tax_bau"] + 
                #                     r["ElectricTariff"]["lifecycle_energy_cost_after_tax_bau"] - 
                #                     r["ElectricTariff"]["lifecycle_demand_cost_after_tax"] - 
                #                     r["ElectricTariff"]["lifecycle_energy_cost_after_tax"]
        
                # fuel_cost_savings = r["ExistingBoiler"]["lifecycle_fuel_cost_after_tax_bau"] - r["ExistingBoiler"]["lifecycle_fuel_cost_after_tax"]
                # @test fuel_cost_savings + elec_cost_savings - d["FlexibleHVAC"]["installed_cost"] ≈ r["Financial"]["npv"] atol=0.1
        
                # now increase the FlexibleHVAC installed_cost to the fuel costs savings + elec_cost_savings 
                # + 100 and expect that the FlexibleHVAC is not purchased
                # d["FlexibleHVAC"]["installed_cost"] = fuel_cost_savings + elec_cost_savings + 100
                m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                r = run_reopt([m1,m2], d)
                @test (occursin("not supported by the solver", string(r["Messages"]["errors"])) || occursin("REopt scenarios solved either with errors or non-optimal solutions", string(r["Messages"]["errors"])))
                # @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === false
                # @test r["Financial"]["npv"] == 0
                finalize(backend(m1))
                empty!(m1)
                finalize(backend(m2))
                empty!(m2)
                GC.gc()
            end
        end

        #=
        add a time-of-export rate that is greater than retail rate for the month of January,
        check to make sure that PV does NOT export unless the site load is met first for the month of January.
        =#
        @testset "Do not allow_simultaneous_export_import" begin
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            data = JSON.parsefile("./scenarios/monthly_rate.json")

            # create wholesale_rate with compensation in January > retail rate
            jan_rate = data["ElectricTariff"]["monthly_energy_rates"][1]
            data["ElectricTariff"]["wholesale_rate"] =
                append!(repeat([jan_rate + 0.1], 31 * 24), repeat([0.0], 8760 - 31*24))
            data["ElectricTariff"]["monthly_demand_rates"] = repeat([0], 12)
            data["ElectricUtility"] = Dict("allow_simultaneous_export_import" => false)

            s = Scenario(data)
            inputs = REoptInputs(s)
            results = run_reopt(model, inputs)
            
            @test all(x == 0.0 for (i,x) in enumerate(results["ElectricUtility"]["electric_to_load_series_kw"][1:744]) 
                    if results["PV"]["electric_to_grid_series_kw"][i] > 0)
            finalize(backend(model))
            empty!(model)
            GC.gc()
        end

        #=
        Battery degradation replacement strategy test can be validated against solvers like Xpress.
        Commented out of this testset due to solve time constraints using open-source solvers.
        This test has been validated via local testing.
        =#
        # @testset "Battery degradation replacement strategy" begin
        #     # Replacement
        #     d = JSON.parsefile("scenarios/batt_degradation.json");

        #     d["ElectricStorage"]["macrs_option_years"] = 0
        #     d["ElectricStorage"]["macrs_bonus_fraction"] = 0.0
        #     d["ElectricStorage"]["macrs_itc_reduction"] = 0.0
        #     d["ElectricStorage"]["total_itc_fraction"] = 0.0
        #     d["ElectricStorage"]["replace_cost_per_kwh"] = 0.0
        #     d["ElectricStorage"]["replace_cost_per_kw"] = 0.0
        #     d["Financial"] = Dict(
        #         "offtaker_tax_rate_fraction" => 0.0,
        #         "owner_tax_rate_fraction" => 0.0
        #     )
        #     d["ElectricStorage"]["degradation"]["installed_cost_per_kwh_declination_rate"] = 0.2
        #     d["Settings"] = Dict{Any,Any}("add_soc_incentive" => false)

        #     s = Scenario(d)
        #     p = REoptInputs(s)
        #     for t in 1:4380
        #         p.s.electric_tariff.energy_rates[2*t-1] = 0
        #         p.s.electric_tariff.energy_rates[2*t] = 10.0
        #     end
        #     m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false))
        #     build_reopt!(m,p)
        #     fix(m[:binSOHIndicatorChange][29], 1.0) # Fix to simplify solving with HiGHS
        #     optimize!(m)
        #     results = reopt_results(m, p)

        #     @test results["ElectricStorage"]["size_kw"] ≈ 11.13 atol=0.05
        #     @test results["ElectricStorage"]["size_kwh"] ≈ 13.35 atol=0.05
        #     @test results["ElectricStorage"]["replacement_month"] == 29
        #     @test results["ElectricStorage"]["maintenance_cost"] ≈ 3481.2 atol=1
        #     @test results["ElectricStorage"]["state_of_health"][8760] ≈ -0.972 atol=0.1
        #     @test results["ElectricStorage"]["residual_value"] ≈ 2.53 atol=0.1
        #     @test sum(results["ElectricStorage"]["storage_to_load_series_kw"]) ≈ 43800 atol=1.0 #battery should serve all load, every other period


        #     # Validate model decision variables make sense.
        #     replace_month = Int(value.(m[:months_to_first_replacement]))+1
        #     @test replace_month ≈ results["ElectricStorage"]["replacement_month"]
        #     @test sum(value.(m[:binSOHIndicator])[replace_month:end]) ≈ 0.0
        #     @test sum(value.(m[:binSOHIndicatorChange])) ≈ value.(m[:binSOHIndicatorChange])[replace_month] ≈ 1.0
        #     @test value.(m[:binSOHIndicator])[end] ≈ 0.0
        # end

        @testset "Solar and ElectricStorage w/BAU and degradation" begin
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            d = JSON.parsefile("scenarios/pv_storage.json");
            d["Settings"] = Dict{Any,Any}("add_soc_incentive" => false)
            results = run_reopt([m1,m2], d)

            @test results["PV"]["size_kw"] ≈ 216.6667 atol=0.01
            @test results["PV"]["lcoe_per_kwh"] ≈ 0.0468 atol = 0.001
            @test results["Financial"]["lcc"] ≈ 1.239179e7 rtol=1e-5
            @test results["Financial"]["lcc_bau"] ≈ 12766397 rtol=1e-5
            @test results["ElectricStorage"]["size_kw"] ≈ 49.02 atol=0.1
            @test results["ElectricStorage"]["size_kwh"] ≈ 83.3 atol=0.1
            proforma_npv = REopt.npv(results["Financial"]["offtaker_annual_free_cashflows"] - 
                results["Financial"]["offtaker_annual_free_cashflows_bau"], 0.081)
            @test results["Financial"]["npv"] ≈ proforma_npv rtol=0.0001
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()

            # compare avg soc with and without degradation, 
            # using default augmentation battery maintenance strategy
            avg_soc_no_degr = sum(results["ElectricStorage"]["soc_series_fraction"]) / 8760

            d = JSON.parsefile("scenarios/pv_storage.json");
            d["ElectricStorage"]["model_degradation"] = true
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            r_degr = run_reopt(m, d)
            avg_soc_degr = sum(r_degr["ElectricStorage"]["soc_series_fraction"]) / 8760
            @test avg_soc_no_degr > avg_soc_degr
            finalize(backend(m))
            empty!(m)
            GC.gc()

            # test the replacement strategy ## Cannot test with open source solvers.
            # d["ElectricStorage"]["degradation"] = Dict("maintenance_strategy" => "replacement")
            # m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            # set_optimizer_attribute(m, "mip_rel_gap", 0.01)
            # r = run_reopt(m, d)
            # @test occursin("not supported by the solver", string(r["Messages"]["errors"]))
            # #optimal SOH at end of horizon is 80\% to prevent any replacement
            # @test sum(value.(m[:dvSOHChangeTimesEnergy])) ≈ 68.48 atol=0.01
            # # @test r["ElectricStorage"]["maintenance_cost"] ≈ 2972.66 atol=0.01 
            # # the maintenance_cost comes out to 3004.39 on Actions, so we test the LCC since it should match
            # @test r["Financial"]["lcc"] ≈ 1.240096e7  rtol=0.01
            # @test last(value.(m[:SOH])) ≈ 42.95 rtol=0.01
            # @test r["ElectricStorage"]["size_kwh"] ≈ 68.48 rtol=0.01

            # test minimum_avg_soc_fraction
            d["ElectricStorage"]["minimum_avg_soc_fraction"] = 0.72
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            set_optimizer_attribute(m, "mip_rel_gap", 0.01)
            r = run_reopt(m, d)
            @test round(sum(r["ElectricStorage"]["soc_series_fraction"])/8760, digits=2) >= 0.72
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

        @testset "Outage with Generator, outage simulator, BAU critical load outputs" begin
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            p = REoptInputs("./scenarios/generator.json")
            results = run_reopt([m1,m2], p)
            @test results["Generator"]["size_kw"] ≈ 9.55 atol=0.01
            @test (sum(results["Generator"]["electric_to_load_series_kw"][i] for i in 1:9) + 
                sum(results["Generator"]["electric_to_load_series_kw"][i] for i in 13:8760)) == 0
            @test results["ElectricLoad"]["bau_critical_load_met"] == false
            @test results["ElectricLoad"]["bau_critical_load_met_time_steps"] == 0
            
            simresults = simulate_outages(results, p)
            @test simresults["resilience_hours_max"] == 11
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()
        end

        @testset "Minimize Unserved Load" begin
            d = JSON.parsefile("./scenarios/outage.json")
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01, "presolve" => "on"))
            results = run_reopt(m, d)
        
            @test results["Outages"]["expected_outage_cost"] ≈ 0 atol=0.1
            @test sum(results["Outages"]["unserved_load_per_outage_kwh"]) ≈ 0 atol=0.1
            @test value(m[:binMGTechUsed]["Generator"]) ≈ 1
            @test value(m[:binMGTechUsed]["CHP"]) ≈ 1
            @test value(m[:binMGTechUsed]["PV"]) ≈ 1
            @test value(m[:binMGStorageUsed]) ≈ 1
            finalize(backend(m))
            empty!(m)
            GC.gc()
        
            # Increase cost of microgrid upgrade and PV Size, PV not used and some load not met
            d["Financial"]["microgrid_upgrade_cost_fraction"] = 0.3
            d["PV"]["min_kw"] = 200.0
            d["PV"]["max_kw"] = 200.0
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01, "presolve" => "on"))
            results = run_reopt(m, d)
            @test value(m[:binMGTechUsed]["PV"]) ≈ 0
            @test sum(results["Outages"]["unserved_load_per_outage_kwh"]) ≈ 24.16 atol=0.1
            finalize(backend(m))
            empty!(m)
            GC.gc()
            
            #=
            Scenario with $0.001/kWh value_of_lost_load_per_kwh, 12x169 hour outages, 1kW load/hour, and min_resil_time_steps = 168
            - should meet 168 kWh in each outage such that the total unserved load is 12 kWh
            =#
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
            results = run_reopt(m, "./scenarios/nogridcost_minresilhours.json")
            @test sum(results["Outages"]["unserved_load_per_outage_kwh"]) ≈ 12
            finalize(backend(m))
            empty!(m)
            GC.gc()
            
            # testing dvUnserved load, which would output 100 kWh for this scenario before output fix
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
            results = run_reopt(m, "./scenarios/nogridcost_multiscenario.json")
            @test sum(results["Outages"]["unserved_load_per_outage_kwh"]) ≈ 60
            @test results["Outages"]["expected_outage_cost"] ≈ 485.43270 atol=1.0e-5  #avg duration (3h) * load per time step (10) * present worth factor (16.18109)
            @test results["Outages"]["max_outage_cost_per_outage_duration"][1] ≈ 161.8109 atol=1.0e-5
            finalize(backend(m))
            empty!(m)
            GC.gc()

            # Scenario with generator, PV, electric storage
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
            results = run_reopt(m, "./scenarios/outages_gen_pv_stor.json")
            @test results["Outages"]["expected_outage_cost"] ≈ 3.54476923e6 atol=10
            @test results["Financial"]["lcc"] ≈ 8.63559824639e7 rtol=0.001
            finalize(backend(m))
            empty!(m)
            GC.gc()

            # Scenario with generator, PV, wind, electric storage
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
            results = run_reopt(m, "./scenarios/outages_gen_pv_wind_stor.json")
            @test value(m[:binMGTechUsed]["Generator"]) ≈ 1
            @test value(m[:binMGTechUsed]["PV"]) ≈ 1
            @test value(m[:binMGTechUsed]["Wind"]) ≈ 1
            @test results["Outages"]["expected_outage_cost"] ≈ 1.296319791276051e6 atol=1.0
            @test results["Financial"]["lcc"] ≈ 4.833635288e6 rtol=0.001
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

        @testset "Outages with Wind and supply-to-load no greater than critical load" begin
            input_data = JSON.parsefile("./scenarios/wind_outages.json")
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01, "presolve" => "on"))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01, "presolve" => "on"))
            results = run_reopt([m1,m2], inputs)
                
            # Check that supply-to-load is equal to critical load during outages, including wind
            supply_to_load = results["Outages"]["storage_discharge_series_kw"] .+ results["Outages"]["wind_to_load_series_kw"]
            supply_to_load = [supply_to_load[:,:,i][1] for i in eachindex(supply_to_load)]
            critical_load = results["Outages"]["critical_loads_per_outage_series_kw"][1,1,:]
            check = .≈(supply_to_load, critical_load, atol=0.001)
            @test !(0 in check)

            # Check that the soc_series_fraction is the same length as the storage_discharge_series_kw
            @test size(results["Outages"]["soc_series_fraction"]) == size(results["Outages"]["storage_discharge_series_kw"])
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()
        end

        @testset "Multiple Sites" begin
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            ps = [
                REoptInputs("./scenarios/pv_storage.json"),
                REoptInputs("./scenarios/monthly_rate.json"),
            ];
            results = run_reopt(m, ps)
            @test results[3]["Financial"]["lcc"] + results[10]["Financial"]["lcc"] ≈ 1.2830872235e7 rtol=1e-5
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

        @testset verbose=true "Rate Structures" begin

            @testset "Tiered Energy" begin
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, "./scenarios/tiered_energy_rate.json")
                @test results["ElectricTariff"]["year_one_energy_cost_before_tax"] ≈ 2342.88
                @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ 24000.0 atol=0.1
                @test results["ElectricLoad"]["annual_calculated_kwh"] ≈ 24000.0 atol=0.1
                finalize(backend(m))
                empty!(m)
                GC.gc()
            end

            @testset "Lookback Demand Charges" begin
                # 1. Testing rate from URDB
                data = JSON.parsefile("./scenarios/lookback_rate.json")
                # urdb_label used https://apps.openei.org/IURDB/rate/view/539f6a23ec4f024411ec8bf9#2__Demand
                # has a demand charge lookback of 35% for all months with 2 different demand charges based on which month
                data["ElectricLoad"]["loads_kw"] = ones(8760)
                data["ElectricLoad"]["loads_kw"][8] = 100.0
                data["ElectricLoad"]["year"] = 2022
                inputs = REoptInputs(Scenario(data))        
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, inputs)
                # Expected result is 100 kW demand for January, 35% of that for all other months and 
                # with 5x other $10.5/kW cold months and 6x $11.5/kW warm months
                @test results["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ 100 * (10.5 + 0.35*10.5*5 + 0.35*11.5*6)
                finalize(backend(m))
                empty!(m)
                GC.gc()

                # 2. Testing custom rate from user with demand_lookback_months
                d = JSON.parsefile("./scenarios/lookback_rate.json")
                d["ElectricTariff"] = Dict()
                d["ElectricTariff"]["demand_lookback_percent"] = 0.75
                d["ElectricLoad"]["loads_kw"] = [100 for i in range(1,8760)]
                d["ElectricLoad"]["loads_kw"][22] = 200 # Jan peak
                d["ElectricLoad"]["loads_kw"][2403] = 400 # April peak (Should set dvPeakDemandLookback)
                d["ElectricLoad"]["loads_kw"][4088] = 500 # June peak (not in peak month lookback)
                d["ElectricLoad"]["loads_kw"][8333] = 300 # Dec peak 
                d["ElectricLoad"]["year"] = 2022
                d["ElectricTariff"]["monthly_demand_rates"] = [10,10,20,50,20,10,20,20,20,20,20,5]
                d["ElectricTariff"]["demand_lookback_months"] = [1,0,0,1,0,0,0,0,0,0,0,1] # Jan, April, Dec
                d["ElectricTariff"]["blended_annual_energy_rate"] = 0.01

                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                r = run_reopt(m, REoptInputs(Scenario(d)))

                monthly_peaks = [300,300,300,400,300,500,300,300,300,300,300,300] # 300 = 400*0.75. Sets peak in all months excpet April and June
                expected_demand_cost = sum(monthly_peaks.*d["ElectricTariff"]["monthly_demand_rates"]) 
                @test r["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ expected_demand_cost
                finalize(backend(m))
                empty!(m)
                GC.gc()

                # 3. Testing custom rate from user with demand_lookback_range
                d = JSON.parsefile("./scenarios/lookback_rate.json")
                d["ElectricTariff"] = Dict()
                d["ElectricTariff"]["demand_lookback_percent"] = 0.75
                d["ElectricLoad"]["loads_kw"] = [100 for i in range(1,8760)]
                d["ElectricLoad"]["loads_kw"][22] = 200 # Jan peak
                d["ElectricLoad"]["loads_kw"][2403] = 400 # April peak (Should set dvPeakDemandLookback)
                d["ElectricLoad"]["loads_kw"][4088] = 500 # June peak (not in peak month lookback)
                d["ElectricLoad"]["loads_kw"][8333] = 300 # Dec peak
                d["ElectricLoad"]["year"] = 2022 
                d["ElectricTariff"]["monthly_demand_rates"] = [10,10,20,50,20,10,20,20,20,20,20,5]
                d["ElectricTariff"]["blended_annual_energy_rate"] = 0.01
                d["ElectricTariff"]["demand_lookback_range"] = 6

                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                r = run_reopt(m, REoptInputs(Scenario(d)))

                monthly_peaks = [225, 225, 225, 400, 300, 500, 375, 375, 375, 375, 375, 375]
                expected_demand_cost = sum(monthly_peaks.*d["ElectricTariff"]["monthly_demand_rates"]) 
                @test r["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ expected_demand_cost
                finalize(backend(m))
                empty!(m)
                GC.gc()

            end

            @testset "Blended tariff" begin
                model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(model, "./scenarios/no_techs.json")
                @test results["ElectricTariff"]["year_one_energy_cost_before_tax"] ≈ 1000.0
                @test results["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ 136.99
                finalize(backend(model))
                empty!(model)
                GC.gc()
            end

            @testset "Coincident Peak Charges" begin
                model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(model, "./scenarios/coincident_peak.json")
                @test results["ElectricTariff"]["year_one_coincident_peak_cost_before_tax"] ≈ 15.0
                finalize(backend(model))
                empty!(model)
                GC.gc()
            end

            @testset "URDB sell rate" begin
                #= The URDB contains at least one "Customer generation" tariff that only has a "sell" key in the energyratestructure (the tariff tested here)
                =#
                model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                p = REoptInputs("./scenarios/URDB_customer_generation.json")
                results = run_reopt(model, p)
                @test results["PV"]["size_kw"] ≈ p.max_sizes["PV"]
                finalize(backend(model))
                empty!(model)
                GC.gc()
            end

            @testset "Custom URDB with Sub-Hourly" begin
                # Avoid excessive JuMP warning messages about += with Expressions
                logger = SimpleLogger()
                with_logger(logger) do
                    # Testing a 15-min post with a urdb_response with multiple n_energy_tiers
                    model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
                    p = REoptInputs("./scenarios/subhourly_with_urdb.json")
                    results = run_reopt(model, p)
                    @test length(p.s.electric_tariff.export_rates[:WHL]) ≈ 8760*4
                    @test results["PV"]["size_kw"] ≈ p.s.pvs[1].existing_kw
                    finalize(backend(model))
                    empty!(model)
                    GC.gc()
                end
            end

            @testset "Multi-tier demand and energy rates" begin
                #This test ensures that when multiple energy or demand regimes are included, that the tier limits load appropriately
                d = JSON.parsefile("./scenarios/no_techs.json")
                d["ElectricTariff"] = Dict()
                d["ElectricTariff"]["urdb_response"] = JSON.parsefile("./scenarios/multi_tier_urdb_response.json")
                s = Scenario(d)
                p = REoptInputs(s)
                @test p.s.electric_tariff.tou_demand_tier_limits[1, 1] ≈ 1.0e8 atol=1.0
                @test p.s.electric_tariff.tou_demand_tier_limits[1, 2] ≈ 1.0e8 atol=1.0
                @test p.s.electric_tariff.tou_demand_tier_limits[2, 1] ≈ 100.0 atol=1.0
                @test p.s.electric_tariff.tou_demand_tier_limits[2, 2] ≈ 1.0e8 atol=1.0
                @test p.s.electric_tariff.energy_tier_limits[1, 1] ≈ 1.0e10 atol=1.0
                @test p.s.electric_tariff.energy_tier_limits[1, 2] ≈ 1.0e10 atol=1.0
                @test p.s.electric_tariff.energy_tier_limits[6, 1] ≈ 20000.0 atol=1.0
                @test p.s.electric_tariff.energy_tier_limits[6, 2] ≈ 1.0e10 atol=1.0
            end

            @testset "Tiered TOU Demand" begin
                data = JSON.parsefile("./scenarios/tiered_tou_demand.json")
                model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(model, data)
                max_demand = data["ElectricLoad"]["annual_kwh"] / 8760
                tier1_max = data["ElectricTariff"]["urdb_response"]["demandratestructure"][1][1]["max"]
                tier1_rate = data["ElectricTariff"]["urdb_response"]["demandratestructure"][1][1]["rate"]
                tier2_rate = data["ElectricTariff"]["urdb_response"]["demandratestructure"][1][2]["rate"]
                expected_demand_charges = 12 * (tier1_max * tier1_rate + (max_demand - tier1_max) * tier2_rate)
                @test results["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ expected_demand_charges atol=1
                finalize(backend(model))
                empty!(model)
                GC.gc()                
            end

            # # tiered monthly demand rate  TODO: expected results?
            # m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            # data = JSON.parsefile("./scenarios/tiered_energy_rate.json")
            # data["ElectricTariff"]["urdb_label"] = "59bc22705457a3372642da67"
            # s = Scenario(data)
            # inputs = REoptInputs(s)
            # results = run_reopt(m, inputs)

            @testset "Non-Standard Units for Energy Rates" begin
                d = JSON.parsefile("./scenarios/no_techs.json")
                d["ElectricTariff"] = Dict(
                    "urdb_label" => "6272e4ae7eb76766c247d469"
                )
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, d)
                @test occursin("URDB energy tiers have non-standard units of", string(results["Messages"]))
                finalize(backend(m))
                empty!(m)
                GC.gc()
            end

            @testset "Demand and Energy Tier Limits Big-M Setup" begin
                d = JSON.parsefile("./scenarios/tiered_energy_demand.json")
                s = Scenario(d)
                p = REoptInputs(s)
                m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => true, "log_to_console" => true, "mip_rel_gap" => 1e-5))
                results = run_reopt(m1, p)
                # demand tier 1 limit = flat load = 100, so no demand charge should be present in Tier 2
                @test sum(value.(m1[Symbol(:dvPeakDemandTOU)][:,2])) ≈ 0.0 atol=1e-6
                @test sum(value.(m1[Symbol(:dvGridPurchase)][:,2])) ≈ 0.0 atol=1e-6
                @test (results["Financial"]["lcc"]) ≈ 1.092312443e6 rtol=1e-6
            end

        end

        @testset "EASIUR" begin
            d = JSON.parsefile("./scenarios/pv.json")
            d["Site"]["latitude"] = 30.2672
            d["Site"]["longitude"] = -97.7431
            scen = Scenario(d)
            @test scen.financial.NOx_grid_cost_per_tonne ≈ 5510.61 atol=0.1
        end

        @testset "Wind" begin
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
            d = JSON.parsefile("./scenarios/wind.json")
            results = run_reopt(m, d)
            @test results["Wind"]["size_kw"] ≈ 3752 atol=0.1
            @test results["Financial"]["lcc"] ≈ 8.591017e6 rtol=1e-5
            finalize(backend(m))
            empty!(m)
            GC.gc()            
            #= 
            0.5% higher LCC in this package as compared to API ? 8,591,017 vs 8,551,172
            - both have zero curtailment
            - same energy to grid: 5,839,317 vs 5,839,322
            - same energy to load: 4,160,683 vs 4,160,677
            - same city: Boulder
            - same total wind prod factor
            
            REopt.jl has:
            - bigger turbine: 3752 vs 3735
            - net_capital_costs_plus_om: 8,576,590 vs. 8,537,480

            TODO: will these discrepancies be addressed once NMIL binaries are added?
            =#

            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
            d["Site"]["land_acres"] = 60 # = 2 MW (with 0.03 acres/kW)
            results = run_reopt(m, d)
            @test results["Wind"]["size_kw"] == 2000.0 # Wind should be constrained by land_acres
            finalize(backend(m))
            empty!(m)
            GC.gc()            

            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
            d["Wind"]["min_kw"] = 2001 # min_kw greater than land-constrained max should error
            results = run_reopt(m, d)
            @test "errors" ∈ keys(results["Messages"])
            @test length(results["Messages"]["errors"]) > 0
            finalize(backend(m))
            empty!(m)
            GC.gc()            
        end

        @testset "Multiple PVs" begin
            logger = SimpleLogger()
            with_logger(logger) do
                m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt([m1,m2], "./scenarios/multiple_pvs.json")

                ground_pv = results["PV"][findfirst(pv -> pv["name"] == "ground", results["PV"])]
                roof_west = results["PV"][findfirst(pv -> pv["name"] == "roof_west", results["PV"])]
                roof_east = results["PV"][findfirst(pv -> pv["name"] == "roof_east", results["PV"])]

                @test ground_pv["size_kw"] ≈ 15 atol=0.1
                @test roof_west["size_kw"] ≈ 7 atol=0.1
                @test roof_east["size_kw"] ≈ 4 atol=0.1
                @test ground_pv["lifecycle_om_cost_after_tax_bau"] ≈ 782.0 atol=0.1
                @test roof_west["lifecycle_om_cost_after_tax_bau"] ≈ 782.0 atol=0.1
                @test ground_pv["annual_energy_produced_kwh_bau"] ≈ 8933.09 atol=0.1
                @test roof_west["annual_energy_produced_kwh_bau"] ≈ 7656.11 atol=0.1
                @test ground_pv["annual_energy_produced_kwh"] ≈ 26799.26 atol=0.1
                @test roof_west["annual_energy_produced_kwh"] ≈ 10719.51 atol=0.1
                @test roof_east["annual_energy_produced_kwh"] ≈ 6685.95 atol=0.1
                finalize(backend(m1))
                empty!(m1)
                finalize(backend(m2))
                empty!(m2)
                GC.gc()
            end
        end

        @testset "Thermal Energy Storage + Absorption Chiller" begin
            model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            data = JSON.parsefile("./scenarios/thermal_storage.json")
            s = Scenario(data)
            p = REoptInputs(s)
                
            #test for get_absorption_chiller_defaults consistency with inputs data and Scenario s.
            htf_defaults_response = get_absorption_chiller_defaults(;
                thermal_consumption_hot_water_or_steam=get(data["AbsorptionChiller"], "thermal_consumption_hot_water_or_steam", nothing),  
                boiler_type=get(data["ExistingBoiler"], "production_type", nothing),
                load_max_tons=maximum(s.cooling_load.loads_kw_thermal / REopt.KWH_THERMAL_PER_TONHOUR)
            )
            
            expected_installed_cost_per_ton = htf_defaults_response["default_inputs"]["installed_cost_per_ton"]
            expected_om_cost_per_ton = htf_defaults_response["default_inputs"]["om_cost_per_ton"]
            
            @test p.s.absorption_chiller.installed_cost_per_kw ≈ expected_installed_cost_per_ton / REopt.KWH_THERMAL_PER_TONHOUR atol=0.001
            @test p.s.absorption_chiller.om_cost_per_kw ≈ expected_om_cost_per_ton / REopt.KWH_THERMAL_PER_TONHOUR atol=0.001
            @test p.s.absorption_chiller.cop_thermal ≈ htf_defaults_response["default_inputs"]["cop_thermal"] atol=0.001
            
            #load test values
            p.s.absorption_chiller.installed_cost_per_kw = 500.0 / REopt.KWH_THERMAL_PER_TONHOUR
            p.s.absorption_chiller.om_cost_per_kw = 0.5 / REopt.KWH_THERMAL_PER_TONHOUR
            p.s.absorption_chiller.cop_thermal = 0.7
            
            #Make every other hour zero fuel and electric cost; storage should charge and discharge in each period
            for ts in p.time_steps
                #heating and cooling loads only
                if ts % 2 == 0  #in even periods, there is a nonzero load and energy is higher cost, and storage should discharge
                    p.s.electric_load.loads_kw[ts] = 10
                    p.s.dhw_load.loads_kw[ts] = 5
                    p.s.space_heating_load.loads_kw[ts] = 5
                    p.s.cooling_load.loads_kw_thermal[ts] = 10
                    p.fuel_cost_per_kwh["ExistingBoiler"][ts] = 100
                    for tier in 1:p.s.electric_tariff.n_energy_tiers
                        p.s.electric_tariff.energy_rates[ts, tier] = 100
                    end
                else #in odd periods, there is no load and energy is cheaper - storage should charge 
                    p.s.electric_load.loads_kw[ts] = 0
                    p.s.dhw_load.loads_kw[ts] = 0
                    p.s.space_heating_load.loads_kw[ts] = 0
                    p.s.cooling_load.loads_kw_thermal[ts] = 0
                    p.fuel_cost_per_kwh["ExistingBoiler"][ts] = 1
                    for tier in 1:p.s.electric_tariff.n_energy_tiers
                        p.s.electric_tariff.energy_rates[ts, tier] = 50
                    end
                end
            end
            
            r = run_reopt(model, p)
            
            #dispatch to load should be 10kW every other period = 4,380 * 10
            @test sum(r["HotThermalStorage"]["storage_to_load_series_mmbtu_per_hour"]) ≈ 149.45 atol=0.1
            @test sum(r["ColdThermalStorage"]["storage_to_load_series_ton"]) ≈ 12454.33 atol=0.1
            #size should be just over 10kW in gallons, accounting for efficiency losses and min SOC
            @test r["HotThermalStorage"]["size_gal"] ≈ 233.0 atol=0.1
            @test r["ColdThermalStorage"]["size_gal"] ≈ 378.0 atol=0.1
            #No production from existing chiller, only absorption chiller, which is sized at ~5kW to manage electric demand charge & capital cost.
            @test r["ExistingChiller"]["annual_thermal_production_tonhour"] ≈ 0.0 atol=0.1
            @test r["AbsorptionChiller"]["annual_thermal_production_tonhour"] ≈ 12464.15 atol=0.1
            @test r["AbsorptionChiller"]["size_ton"] ≈ 2.846 atol=0.01
            finalize(backend(model))
            empty!(model)
            GC.gc()
        end

        @testset "Heat and cool energy balance" begin
            """

            This is an "energy balance" type of test which tests the model formulation/math as opposed
            to a specific scenario. This test is robust to changes in the model "MIPRELSTOP" or "MAXTIME" setting

            Validation to ensure that:
                1) The electric and absorption chillers are supplying 100% of the cooling thermal load plus losses from ColdThermalStorage
                2) The boiler and CHP are supplying the heating load plus additional absorption chiller thermal load
                3) The Cold and Hot TES efficiency (charge loss and thermal decay) are being tracked properly

            """
            input_data = JSON.parsefile("./scenarios/heat_cool_energy_balance_inputs.json")
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results = run_reopt(m, inputs)

            # Annual cooling **thermal** energy load of CRB is based on annual cooling electric energy (from CRB models) and a conditional COP depending on the peak cooling thermal load
            # When the user specifies inputs["ExistingChiller"]["cop"], this changes the **electric** consumption of the chiller to meet that cooling thermal load
            crb_cop = REopt.get_existing_chiller_default_cop(;
                                                            existing_chiller_max_thermal_factor_on_peak_load=s.existing_chiller.max_thermal_factor_on_peak_load,
                                                            max_load_kw_thermal=maximum(s.cooling_load.loads_kw_thermal))
            cooling_thermal_load_tonhour_total = 1427329.0 * crb_cop / REopt.KWH_THERMAL_PER_TONHOUR  # From CRB models, in heating_cooling_loads.jl, BuiltInCoolingLoad data for location (SanFrancisco Hospital)
            cooling_electric_load_total_mod_cop_kwh = cooling_thermal_load_tonhour_total / inputs.s.existing_chiller.cop * REopt.KWH_THERMAL_PER_TONHOUR

            #Test cooling load results
            @test round(cooling_thermal_load_tonhour_total, digits=1) ≈ results["CoolingLoad"]["annual_calculated_tonhour"] atol=1.0
            
            # Convert fuel input to thermal using user input boiler efficiency
            boiler_thermal_load_mmbtu_total = (671.40531 + 11570.9155) * input_data["ExistingBoiler"]["efficiency"] # From CRB models, in heating_cooling_loads.jl, BuiltInDomesticHotWaterLoad + BuiltInSpaceHeatingLoad data for location (SanFrancisco Hospital)
            boiler_fuel_consumption_total_mod_efficiency = boiler_thermal_load_mmbtu_total / inputs.s.existing_boiler.efficiency

            # Cooling outputs
            cooling_elecchl_tons_to_load_series = results["ExistingChiller"]["thermal_to_load_series_ton"]
            cooling_elecchl_tons_to_tes_series = results["ExistingChiller"]["thermal_to_storage_series_ton"]
            cooling_absorpchl_tons_to_load_series = results["AbsorptionChiller"]["thermal_to_load_series_ton"]
            cooling_absorpchl_tons_to_tes_series = results["AbsorptionChiller"]["thermal_to_storage_series_ton"]
            cooling_tonhour_to_load_tech_total = sum(cooling_elecchl_tons_to_load_series) + sum(cooling_absorpchl_tons_to_load_series)
            cooling_tonhour_to_tes_total = sum(cooling_elecchl_tons_to_tes_series) + sum(cooling_absorpchl_tons_to_tes_series)
            cooling_tes_tons_to_load_series = results["ColdThermalStorage"]["storage_to_load_series_ton"]
            cooling_extra_from_tes_losses = cooling_tonhour_to_tes_total - sum(cooling_tes_tons_to_load_series)
            tes_effic_with_decay = sum(cooling_tes_tons_to_load_series) / cooling_tonhour_to_tes_total
            cooling_total_prod_from_techs = cooling_tonhour_to_load_tech_total + cooling_tonhour_to_tes_total
            cooling_load_plus_tes_losses = cooling_thermal_load_tonhour_total + cooling_extra_from_tes_losses

            # Absorption Chiller electric consumption addition
            absorpchl_total_cooling_produced_series_ton = cooling_absorpchl_tons_to_load_series .+ cooling_absorpchl_tons_to_tes_series 
            absorpchl_total_cooling_produced_ton_hour = sum(absorpchl_total_cooling_produced_series_ton)
            absorpchl_electric_consumption_total_kwh = results["AbsorptionChiller"]["annual_electric_consumption_kwh"]
            absorpchl_cop_elec = s.absorption_chiller.cop_electric

            # Check if sum of electric and absorption chillers equals cooling thermal total
            @test tes_effic_with_decay < 0.97
            @test round(cooling_total_prod_from_techs, digits=0) ≈ cooling_load_plus_tes_losses atol=5.0
            @test round(absorpchl_electric_consumption_total_kwh, digits=0) ≈ absorpchl_total_cooling_produced_ton_hour * REopt.KWH_THERMAL_PER_TONHOUR / absorpchl_cop_elec atol=1.0

            # Heating outputs
            boiler_fuel_consumption_calculated = results["ExistingBoiler"]["annual_fuel_consumption_mmbtu"]
            boiler_thermal_series = results["ExistingBoiler"]["thermal_production_series_mmbtu_per_hour"]
            boiler_to_load_series = results["ExistingBoiler"]["thermal_to_load_series_mmbtu_per_hour"]
            boiler_thermal_to_tes_series = results["ExistingBoiler"]["thermal_to_storage_series_mmbtu_per_hour"]
            chp_thermal_to_load_series = results["CHP"]["thermal_to_load_series_mmbtu_per_hour"]
            chp_thermal_to_tes_series = results["CHP"]["thermal_to_storage_series_mmbtu_per_hour"]
            chp_thermal_to_waste_series = results["CHP"]["thermal_curtailed_series_mmbtu_per_hour"]
            absorpchl_thermal_series = results["AbsorptionChiller"]["thermal_consumption_series_mmbtu_per_hour"]
            hot_tes_mmbtu_per_hour_to_load_series = results["HotThermalStorage"]["storage_to_load_series_mmbtu_per_hour"]
            tes_inflows = sum(chp_thermal_to_tes_series) + sum(boiler_thermal_to_tes_series)
            total_chp_production = sum(chp_thermal_to_load_series) + sum(chp_thermal_to_waste_series) + sum(chp_thermal_to_tes_series)
            tes_outflows = sum(hot_tes_mmbtu_per_hour_to_load_series)
            total_thermal_expected = boiler_thermal_load_mmbtu_total + sum(chp_thermal_to_waste_series) + tes_inflows + sum(absorpchl_thermal_series)
            boiler_fuel_expected = (total_thermal_expected - total_chp_production - tes_outflows) / inputs.s.existing_boiler.efficiency
            total_thermal_mmbtu_calculated = sum(boiler_thermal_series) + total_chp_production + tes_outflows

            @test round(boiler_fuel_consumption_calculated, digits=0) ≈ boiler_fuel_expected atol=8.0
            @test round(total_thermal_mmbtu_calculated, digits=0) ≈ total_thermal_expected atol=8.0  

            # Test CHP["cooling_thermal_factor"] = 0.8, AbsorptionChiller["cop_thermal"] = 0.7 (from inputs .json)
            absorpchl_heat_in_kwh = results["AbsorptionChiller"]["annual_thermal_consumption_mmbtu"] * REopt.KWH_PER_MMBTU
            absorpchl_cool_out_kwh = results["AbsorptionChiller"]["annual_thermal_production_tonhour"] * REopt.KWH_THERMAL_PER_TONHOUR
            absorpchl_cop = absorpchl_cool_out_kwh / absorpchl_heat_in_kwh

            @test round(absorpchl_cop, digits=5) ≈ 0.8*0.7 rtol=1e-4
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

        @testset "Heating and cooling inputs + CHP defaults" begin
            """

            This tests the various ways to input heating and cooling loads to make sure they are processed correctly.
            There are no "new" technologies in this test, so heating is served by ExistingBoiler, and 
                cooling is served by ExistingCooler. Since this is just inputs processing tests, no optimization is needed.

            """
            input_data = JSON.parsefile("./scenarios/heating_cooling_load_inputs.json")
            s = Scenario(input_data)
            inputs = REoptInputs(s)

            # Heating load is input as **fuel**, not thermal 
            # If boiler efficiency is not input, we use REopt.EXISTING_BOILER_EFFICIENCY to convert fuel to thermal
            expected_fuel = input_data["SpaceHeatingLoad"]["annual_mmbtu"] + input_data["DomesticHotWaterLoad"]["annual_mmbtu"]
            total_boiler_heating_thermal_load_mmbtu = (sum(inputs.s.space_heating_load.loads_kw) + sum(inputs.s.dhw_load.loads_kw)) / REopt.KWH_PER_MMBTU
            @test round(total_boiler_heating_thermal_load_mmbtu, digits=0) ≈ expected_fuel * REopt.EXISTING_BOILER_EFFICIENCY atol=1.0
            total_boiler_heating_fuel_load_mmbtu = total_boiler_heating_thermal_load_mmbtu / inputs.s.existing_boiler.efficiency
            @test round(total_boiler_heating_fuel_load_mmbtu, digits=0) ≈ expected_fuel * REopt.EXISTING_BOILER_EFFICIENCY / inputs.s.existing_boiler.efficiency atol=1.0
            # If boiler efficiency is input, use that with annual or monthly mmbtu input to convert fuel to thermal
            input_data["ExistingBoiler"]["efficiency"] = 0.72
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            total_boiler_heating_thermal_load_mmbtu = (sum(inputs.s.space_heating_load.loads_kw) + sum(inputs.s.dhw_load.loads_kw)) / REopt.KWH_PER_MMBTU
            @test round(total_boiler_heating_thermal_load_mmbtu, digits=0) ≈ expected_fuel * input_data["ExistingBoiler"]["efficiency"] atol=1.0
            total_boiler_heating_fuel_load_mmbtu = total_boiler_heating_thermal_load_mmbtu / inputs.s.existing_boiler.efficiency
            @test round(total_boiler_heating_fuel_load_mmbtu, digits=0) ≈ expected_fuel * input_data["ExistingBoiler"]["efficiency"] / inputs.s.existing_boiler.efficiency atol=1.0

            # The expected cooling load is based on the default **fraction of total electric** profile for the doe_reference_name when annual_tonhour is NOT input
            #    the 320540.0 kWh number is from the default LargeOffice fraction of total electric profile applied to the Hospital default total electric profile
            total_chiller_electric_consumption = sum(inputs.s.cooling_load.loads_kw_thermal) / inputs.s.existing_chiller.cop
            @test round(total_chiller_electric_consumption, digits=0) ≈ 320544.0 atol=1.0  # loads_kw is **electric**, loads_kw_thermal is **thermal**

            #Test CHP defaults use average fuel load, size class 2 for recip_engine 
            @test inputs.s.chp.min_allowable_kw ≈ 50.0 atol=0.01
            @test inputs.s.chp.om_cost_per_kwh ≈ 0.0235 atol=0.0001

            delete!(input_data, "SpaceHeatingLoad")
            delete!(input_data, "DomesticHotWaterLoad")
            annual_fraction_of_electric_load_input = 0.5
            input_data["CoolingLoad"] = Dict{Any, Any}("annual_fraction_of_electric_load" => annual_fraction_of_electric_load_input)

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            expected_cooling_electricity = sum(inputs.s.electric_load.loads_kw) * annual_fraction_of_electric_load_input
            total_chiller_electric_consumption = sum(inputs.s.cooling_load.loads_kw_thermal) / inputs.s.cooling_load.existing_chiller_cop
            @test round(total_chiller_electric_consumption, digits=0) ≈ round(expected_cooling_electricity) atol=1.0
            @test round(total_chiller_electric_consumption, digits=0) ≈ 3876410 atol=1.0

            # Check that without heating load or max_kw input, CHP.max_kw gets set based on peak electric load
            @test inputs.s.chp.max_kw ≈ maximum(inputs.s.electric_load.loads_kw) atol=0.01

            input_data["SpaceHeatingLoad"] = Dict{Any, Any}("monthly_mmbtu" => repeat([1000.0], 12))
            input_data["DomesticHotWaterLoad"] = Dict{Any, Any}("monthly_mmbtu" => repeat([1000.0], 12))
            input_data["CoolingLoad"] = Dict{Any, Any}("monthly_fractions_of_electric_load" => repeat([0.1], 12))

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            #Test CHP defaults use average fuel load, size class changes to 3
            @test inputs.s.chp.min_allowable_kw ≈ 125.0 atol=0.1
            @test inputs.s.chp.om_cost_per_kwh ≈ 0.021 atol=0.0001
            #Update CHP prime_mover and test new defaults
            input_data["CHP"]["prime_mover"] = "combustion_turbine"
            input_data["CHP"]["size_class"] = 1
            # Set max_kw higher than peak electric load so min_allowable_kw doesn't get assigned to max_kw
            input_data["CHP"]["max_kw"] = 2500.0

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            @test inputs.s.chp.min_allowable_kw ≈ 2000.0 atol=0.1
            @test inputs.s.chp.om_cost_per_kwh ≈ 0.014499999999999999 atol=0.0001

            total_heating_fuel_load_mmbtu = (sum(inputs.s.space_heating_load.loads_kw) + 
                                            sum(inputs.s.dhw_load.loads_kw)) / input_data["ExistingBoiler"]["efficiency"] / REopt.KWH_PER_MMBTU
            @test round(total_heating_fuel_load_mmbtu, digits=0) ≈ 24000 atol=1.0
            total_chiller_electric_consumption = sum(inputs.s.cooling_load.loads_kw_thermal) / inputs.s.cooling_load.existing_chiller_cop
            @test round(total_chiller_electric_consumption, digits=0) ≈ 775282 atol=1.0

            input_data["SpaceHeatingLoad"] = Dict{Any, Any}("fuel_loads_mmbtu_per_hour" => repeat([0.5], 8760))
            input_data["DomesticHotWaterLoad"] = Dict{Any, Any}("fuel_loads_mmbtu_per_hour" => repeat([0.5], 8760))
            input_data["CoolingLoad"] = Dict{Any, Any}("per_time_step_fractions_of_electric_load" => repeat([0.01], 8760))

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            total_heating_fuel_load_mmbtu = (sum(inputs.s.space_heating_load.loads_kw) + 
                                            sum(inputs.s.dhw_load.loads_kw)) / input_data["ExistingBoiler"]["efficiency"] / REopt.KWH_PER_MMBTU
            @test round(total_heating_fuel_load_mmbtu, digits=0) ≈ 8760 atol=0.1
            @test round(sum(inputs.s.cooling_load.loads_kw_thermal) / inputs.s.cooling_load.existing_chiller_cop, digits=0) ≈ 77528.0 atol=1.0

            # Make sure annual_tonhour is preserved with conditional existing_chiller_default logic, where guess-and-correct method is applied
            input_data["SpaceHeatingLoad"] = Dict{Any, Any}()
            input_data["DomesticHotWaterLoad"] = Dict{Any, Any}()
            annual_tonhour = 25000.0
            input_data["CoolingLoad"] = Dict{Any, Any}("doe_reference_name" => "Hospital",
                                                        "annual_tonhour" => annual_tonhour)
            input_data["ExistingChiller"] = Dict{Any, Any}()

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            @test round(sum(inputs.s.cooling_load.loads_kw_thermal) / REopt.KWH_THERMAL_PER_TONHOUR, digits=0) ≈ annual_tonhour atol=1.0 
            
            # Test for prime generator CHP inputs (electric only)
            # First get CHP cost to compare later with prime generator
            input_data["ElectricLoad"] = Dict("doe_reference_name" => "FlatLoad",
                                                "annual_kwh" => 876000)
            input_data["ElectricTariff"] = Dict("blended_annual_energy_rate" => 0.06,
                                                "blended_annual_demand_rate" => 0.0  )
            s_chp = Scenario(input_data)
            inputs_chp = REoptInputs(s)
            installed_cost_chp = s_chp.chp.installed_cost_per_kw

            # Now get prime generator (electric only)
            input_data["CHP"]["is_electric_only"] = true
            delete!(input_data["CHP"], "max_kw")
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            # Costs are 75% of CHP
            @test inputs.s.chp.installed_cost_per_kw ≈ (0.75*installed_cost_chp) atol=1.0
            @test inputs.s.chp.om_cost_per_kwh ≈ (0.75*0.0145) atol=0.0001
            @test inputs.s.chp.federal_itc_fraction ≈ 0.0 atol=0.0001
            # Thermal efficiency set to zero
            @test inputs.s.chp.thermal_efficiency_full_load == 0
            @test inputs.s.chp.thermal_efficiency_half_load == 0
            # Max size based on electric load, not heating load
            @test inputs.s.chp.max_kw ≈ maximum(inputs.s.electric_load.loads_kw) atol=0.001    
        end

        @testset "Hybrid/blended heating and cooling loads" begin
            """

            This tests the hybrid/campus loads for heating and cooling, where a blended_doe_reference_names
                and blended_doe_reference_percents are given and blended to create an aggregate load profile

            """
            input_data = JSON.parsefile("./scenarios/hybrid_loads_heating_cooling_inputs.json")

            hospital_fraction = 0.75
            hotel_fraction = 1.0 - hospital_fraction

            # Hospital only
            input_data["ElectricLoad"]["annual_kwh"] = hospital_fraction * 100
            input_data["ElectricLoad"]["doe_reference_name"] = "Hospital"
            input_data["SpaceHeatingLoad"]["annual_mmbtu"] = hospital_fraction * 100
            input_data["SpaceHeatingLoad"]["doe_reference_name"] = "Hospital"
            input_data["DomesticHotWaterLoad"]["annual_mmbtu"] = hospital_fraction * 100
            input_data["DomesticHotWaterLoad"]["doe_reference_name"] = "Hospital"    
            input_data["CoolingLoad"]["doe_reference_name"] = "Hospital"

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            elec_hospital = inputs.s.electric_load.loads_kw
            space_hospital = inputs.s.space_heating_load.loads_kw  # thermal
            dhw_hospital = inputs.s.dhw_load.loads_kw  # thermal
            cooling_hospital = inputs.s.cooling_load.loads_kw_thermal  # thermal
            cooling_elec_frac_of_total_hospital = cooling_hospital / inputs.s.cooling_load.existing_chiller_cop ./ elec_hospital

            # Hotel only
            input_data["ElectricLoad"]["annual_kwh"] = hotel_fraction * 100
            input_data["ElectricLoad"]["doe_reference_name"] = "LargeHotel"
            input_data["SpaceHeatingLoad"]["annual_mmbtu"] = hotel_fraction * 100
            input_data["SpaceHeatingLoad"]["doe_reference_name"] = "LargeHotel"
            input_data["DomesticHotWaterLoad"]["annual_mmbtu"] = hotel_fraction * 100
            input_data["DomesticHotWaterLoad"]["doe_reference_name"] = "LargeHotel"    
            input_data["CoolingLoad"]["doe_reference_name"] = "LargeHotel"

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            elec_hotel = inputs.s.electric_load.loads_kw
            space_hotel = inputs.s.space_heating_load.loads_kw  # thermal
            dhw_hotel = inputs.s.dhw_load.loads_kw  # thermal
            cooling_hotel = inputs.s.cooling_load.loads_kw_thermal  # thermal
            cooling_elec_frac_of_total_hotel = cooling_hotel / inputs.s.cooling_load.existing_chiller_cop ./ elec_hotel

            # Hybrid mix of hospital and hotel
            # Remove previous assignment of doe_reference_name
            for load in ["ElectricLoad", "SpaceHeatingLoad", "DomesticHotWaterLoad", "CoolingLoad"]
                delete!(input_data[load], "doe_reference_name")
            end
            annual_energy = (hospital_fraction + hotel_fraction) * 100
            building_list = ["Hospital", "LargeHotel"]
            percent_share_list = [hospital_fraction, hotel_fraction]
            input_data["ElectricLoad"]["annual_kwh"] = annual_energy
            input_data["ElectricLoad"]["blended_doe_reference_names"] = building_list
            input_data["ElectricLoad"]["blended_doe_reference_percents"] = percent_share_list

            input_data["SpaceHeatingLoad"]["annual_mmbtu"] = annual_energy
            input_data["SpaceHeatingLoad"]["blended_doe_reference_names"] = building_list
            input_data["SpaceHeatingLoad"]["blended_doe_reference_percents"] = percent_share_list
            input_data["DomesticHotWaterLoad"]["annual_mmbtu"] = annual_energy
            input_data["DomesticHotWaterLoad"]["blended_doe_reference_names"] = building_list
            input_data["DomesticHotWaterLoad"]["blended_doe_reference_percents"] = percent_share_list    

            # CoolingLoad now use a weighted fraction of total electric profile if no annual_tonhour is provided
            input_data["CoolingLoad"]["blended_doe_reference_names"] = building_list
            input_data["CoolingLoad"]["blended_doe_reference_percents"] = percent_share_list    

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            elec_hybrid = inputs.s.electric_load.loads_kw
            space_hybrid = inputs.s.space_heating_load.loads_kw  # thermal
            dhw_hybrid = inputs.s.dhw_load.loads_kw  # thermal
            cooling_hybrid = inputs.s.cooling_load.loads_kw_thermal   # thermal
            cooling_elec_hybrid = cooling_hybrid / inputs.s.cooling_load.existing_chiller_cop  # electric
            cooling_elec_frac_of_total_hybrid = cooling_hybrid / inputs.s.cooling_load.existing_chiller_cop ./ elec_hybrid

            # Check that the combined/hybrid load is the same as the sum of the individual loads in each time_step

            @test round(sum(elec_hybrid .- (elec_hospital .+ elec_hotel)), digits=1) ≈ 0.0 atol=0.1
            @test round(sum(space_hybrid .- (space_hospital .+ space_hotel)), digits=1) ≈ 0.0 atol=0.1
            @test round(sum(dhw_hybrid .- (dhw_hospital .+ dhw_hotel)), digits=1) ≈ 0.0 atol=0.1
            # Check that the cooling load is the weighted average of the default CRB fraction of total electric profiles
            cooling_electric_hybrid_expected = elec_hybrid .* (cooling_elec_frac_of_total_hospital * hospital_fraction  .+ 
                                                    cooling_elec_frac_of_total_hotel * hotel_fraction)
            @test round(sum(cooling_electric_hybrid_expected .- cooling_elec_hybrid), digits=1) ≈ 0.0 atol=0.1
        end

        @testset "Boiler (new) test" begin
            input_data = JSON.parsefile("scenarios/boiler_new_inputs.json")
            input_data["SpaceHeatingLoad"]["annual_mmbtu"] = 0.5 * 8760
            input_data["DomesticHotWaterLoad"]["annual_mmbtu"] = 0.5 * 8760
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            @test inputs.tech_emissions_factors_CO2["ExistingBoiler"] ≈ inputs.tech_emissions_factors_CO2["Boiler"] atol=1.0e-6 
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt([m1,m2], inputs)
            
            # BAU boiler loads
            load_thermal_mmbtu_bau = sum(s.space_heating_load.loads_kw + s.dhw_load.loads_kw) / REopt.KWH_PER_MMBTU
            existing_boiler_mmbtu = sum(results["ExistingBoiler"]["thermal_production_series_mmbtu_per_hour"])
            boiler_thermal_mmbtu = sum(results["Boiler"]["thermal_production_series_mmbtu_per_hour"])
            
            # Used monthly fuel cost for ExistingBoiler and Boiler, where ExistingBoiler has lower fuel cost only
            # in February (28 days), so expect ExistingBoiler to serve the flat/constant load 28 days of the year
            @test existing_boiler_mmbtu ≈ load_thermal_mmbtu_bau * 28 / 365 atol=0.00001
            @test boiler_thermal_mmbtu ≈ load_thermal_mmbtu_bau - existing_boiler_mmbtu atol=0.00001
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()
        end

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
            @test r["PV"]["size_kw"] ≈ 5050.0
            f = r["Financial"]
            @test f["lifecycle_generation_tech_capital_costs"] + f["lifecycle_storage_capital_costs"] + f["lifecycle_om_costs_after_tax"] +
                    f["lifecycle_fuel_costs_after_tax"] + f["lifecycle_chp_standby_cost_after_tax"] + f["lifecycle_elecbill_after_tax"] + 
                    f["lifecycle_offgrid_other_annual_costs_after_tax"] + f["lifecycle_offgrid_other_capital_costs"] + 
                    f["lifecycle_outage_cost"] + f["lifecycle_MG_upgrade_and_fuel_cost"] - 
                    f["lifecycle_production_incentive_after_tax"] ≈ f["lcc"] atol=1.0
            
            ## Scenario 2: Fixed Generator only
            post["ElectricLoad"]["annual_kwh"] = 100.0
            post["PV"]["max_kw"] = 0.0
            post["ElectricStorage"]["max_kw"] = 0.0
            post["Generator"]["min_turn_down_fraction"] = 0.0
            finalize(backend(m))
            empty!(m)
            GC.gc()            

            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            r = run_reopt(m, post)

            # Test generator outputs
            @test r["Generator"]["annual_fuel_consumption_gal"] ≈ 7.52 # 99 kWh * 0.076 gal/kWh
            @test r["Generator"]["annual_energy_produced_kwh"] ≈ 99.0
            @test r["Generator"]["year_one_fuel_cost_before_tax"] ≈ 22.57
            @test r["Generator"]["lifecycle_fuel_cost_after_tax"] ≈ 205.35 
            other_offgrid_capex_before_tax = post["Financial"]["offgrid_other_capital_costs"]
            other_offgrid_capex_after_tax = value(m[Symbol("OffgridOtherCapexAfterDepr")])
            @test r["Financial"]["initial_capital_costs"] ≈ 100*(700) + other_offgrid_capex_before_tax 
            @test r["Financial"]["lifecycle_capital_costs"] ≈ 100*(700+324.235442*(1-0.26)) + other_offgrid_capex_after_tax atol=0.1 # replacement in yr 10 is considered tax deductible
            @test r["Financial"]["initial_capital_costs_after_incentives"] ≈ 700*100 + other_offgrid_capex_after_tax atol=0.1
            @test r["Financial"]["replacements_future_cost_after_tax"] ≈ 700*100
            @test r["Financial"]["replacements_present_cost_after_tax"] ≈ 100*(324.235442*(1-0.26)) atol=0.1 

            ## Scenario 3: Fixed Generator that can meet load, but cannot meet load operating reserve requirement
            ## This test ensures the load operating reserve requirement is being enforced
            post["ElectricLoad"]["doe_reference_name"] = "FlatLoad"
            post["ElectricLoad"]["annual_kwh"] = 876000.0 # requires 100 kW gen
            post["ElectricLoad"]["min_load_met_annual_fraction"] = 1.0 # requires additional generator capacity
            post["PV"]["max_kw"] = 0.0
            post["ElectricStorage"]["max_kw"] = 0.0
            post["Generator"]["min_turn_down_fraction"] = 0.0
            finalize(backend(m))
            empty!(m)
            GC.gc()            

            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            r = run_reopt(m, post)

            # Test generator outputs
            @test typeof(r) == Model # this is true when the model is infeasible
            finalize(backend(m))
            empty!(m)
            GC.gc()            

            ### Scenario 3: Indonesia. Wind (custom prod) and Generator only
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01, "presolve" => "on"))
            post_name = "wind_intl_offgrid.json" 
            post = JSON.parsefile("./scenarios/$post_name")
            post["ElectricLoad"]["loads_kw"] = [10.0 for i in range(1,8760)]
            post["ElectricLoad"]["year"] = 2022
            scen = Scenario(post)
            post["Wind"]["production_factor_series"] =  reduce(vcat, readdlm("./data/example_wind_prod_factor_kw.csv", '\n', header=true)[1])

            results = run_reopt(m, post)
            
            @test results["ElectricLoad"]["offgrid_load_met_fraction"] >= scen.electric_load.min_load_met_annual_fraction
            f = results["Financial"]
            @test f["lifecycle_generation_tech_capital_costs"] + f["lifecycle_storage_capital_costs"] + f["lifecycle_om_costs_after_tax"] +
                    f["lifecycle_fuel_costs_after_tax"] + f["lifecycle_chp_standby_cost_after_tax"] + f["lifecycle_elecbill_after_tax"] + 
                    f["lifecycle_offgrid_other_annual_costs_after_tax"] + f["lifecycle_offgrid_other_capital_costs"] + 
                    f["lifecycle_outage_cost"] + f["lifecycle_MG_upgrade_and_fuel_cost"] - 
                    f["lifecycle_production_incentive_after_tax"] ≈ f["lcc"] atol=1.0

            windOR = sum(results["Wind"]["electric_to_load_series_kw"]  * post["Wind"]["operating_reserve_required_fraction"])
            loadOR = sum(post["ElectricLoad"]["loads_kw"] * scen.electric_load.operating_reserve_required_fraction)
            @test sum(results["ElectricLoad"]["offgrid_annual_oper_res_required_series_kwh"]) ≈ loadOR  + windOR atol=1.0
            finalize(backend(m))
            empty!(m)
            GC.gc()            

        end

        @testset "GHP" begin
            """

            This tests multiple unique aspects of GHP:
            1. REopt takes the output data of GhpGhx, creates multiple GHP options, and chooses the expected one
            2. GHP with heating and cooling "..efficiency_thermal_factors" reduces the net thermal load
            3. GHP serves only the SpaceHeatingLoad by default unless it is allowed to serve DHW
            4. GHP serves all the Cooling load
            5. Input of a custom COP map for GHP and check the GHP performance to make sure it's using it correctly
            6. Hybrid GHP capability functions as expected
            7. Check GHP LCC calculation for URBANopt
            8. Check GHX LCC calculation for URBANopt
            9. Allow User-defined max GHP size
            10. Allow User-defined max GHP size and max number of boreholes

            """
            # Load base inputs
            input_data = JSON.parsefile("scenarios/ghp_inputs.json")
            
            # Modify ["GHP"]["ghpghx_inputs"] for running GhpGhx.jl
            # Heat pump performance maps
            cop_map_mat_header = readdlm("scenarios/ghp_cop_map_custom.csv", ',', header=true)
            data = cop_map_mat_header[1]
            headers = cop_map_mat_header[2]
            # Generate a "records" style dictionary from the 
            cop_map_list = []
            for i in axes(data,1)
                dict_record = Dict(name=>data[i, col] for (col, name) in enumerate(headers))
                push!(cop_map_list, dict_record)
            end
            input_data["GHP"]["ghpghx_inputs"][1]["cop_map_eft_heating_cooling"] = cop_map_list
            
            # Due to GhpGhx not being a registered package (no OSI-approved license), 
            # the registered REopt package cannot have GhpGhx as a "normal" dependency;
            # Therefore, we only use a "ghpghx_response" (the output of GhpGhx) as an 
            # input to REopt to avoid GhpGhx module calls
            response_1 = JSON.parsefile("scenarios/ghpghx_response.json")
            response_2 = deepcopy(response_1)
            # Reduce the electric consumption of response 2 which should then be the chosen system
            response_2["outputs"]["yearly_total_electric_consumption_series_kw"] *= 0.5 
            input_data["GHP"]["ghpghx_responses"] = [response_1, response_2]
            
            # Heating load
            input_data["SpaceHeatingLoad"]["doe_reference_name"] = "Hospital"
            input_data["SpaceHeatingLoad"]["monthly_mmbtu"] = fill(1000.0, 12)
            input_data["SpaceHeatingLoad"]["monthly_mmbtu"][1] = 500.0
            input_data["SpaceHeatingLoad"]["monthly_mmbtu"][end] = 1500.0
            
            # Call REopt
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results = run_reopt([m1,m2], inputs)
            
            ghp_option_chosen = results["GHP"]["ghp_option_chosen"]
            @test ghp_option_chosen == 2

            # Test GHP heating and cooling load reduced
            hot_load_reduced_mmbtu = sum(results["GHP"]["space_heating_thermal_load_reduction_with_ghp_mmbtu_per_hour"])
            cold_load_reduced_tonhour = sum(results["GHP"]["cooling_thermal_load_reduction_with_ghp_ton"])
            @test hot_load_reduced_mmbtu ≈ 1440.00 atol=0.1
            @test cold_load_reduced_tonhour ≈ 761382.78 atol=0.1

            # Test GHP serving space heating with VAV thermal efficiency improvements
            heating_served_mmbtu = sum(s.ghp_option_list[ghp_option_chosen].heating_thermal_kw / REopt.KWH_PER_MMBTU)
            expected_heating_served_mmbtu = 12000 * 0.8 * 0.85  # (fuel_mmbtu * boiler_effic * space_heating_efficiency_thermal_factor)
            @test round(heating_served_mmbtu, digits=1) ≈ expected_heating_served_mmbtu atol=1.0
            
            # Boiler serves all of the DHW load, no DHW thermal reduction due to GHP retrofit
            boiler_served_mmbtu = sum(results["ExistingBoiler"]["thermal_production_series_mmbtu_per_hour"])
            expected_boiler_served_mmbtu = 3000 * 0.8 # (fuel_mmbtu * boiler_effic)
            @test round(boiler_served_mmbtu, digits=1) ≈ expected_boiler_served_mmbtu atol=1.5
            
            # LoadProfileChillerThermal cooling thermal is 1/cooling_efficiency_thermal_factor of GHP cooling thermal production
            bau_chiller_thermal_tonhour = sum(s.cooling_load.loads_kw_thermal / REopt.KWH_THERMAL_PER_TONHOUR)
            ghp_cooling_thermal_tonhour = sum(inputs.ghp_cooling_thermal_load_served_kw[1,:] / REopt.KWH_THERMAL_PER_TONHOUR)
            @test round(bau_chiller_thermal_tonhour) ≈ ghp_cooling_thermal_tonhour/0.6 atol=1.0
            
            # Custom heat pump COP map is used properly
            ghp_option_chosen = results["GHP"]["ghp_option_chosen"]
            heating_cop_avg = s.ghp_option_list[ghp_option_chosen].ghpghx_response["outputs"]["heating_cop_avg"]
            cooling_cop_avg = s.ghp_option_list[ghp_option_chosen].ghpghx_response["outputs"]["cooling_cop_avg"]
            # Average COP which includes pump power should be lower than Heat Pump only COP specified by the map
            @test heating_cop_avg <= 4.0
            @test cooling_cop_avg <= 8.0
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()

            # Test hybrid GHP functionality
            input_data_hybrid = JSON.parsefile("scenarios/ghp_inputs_hybrid.json")

            hybrid_inputs = REoptInputs(input_data_hybrid)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            hybrid_results = run_reopt(m1, hybrid_inputs)

            pop!(input_data_hybrid["GHP"], "ghpghx_inputs", nothing)
            non_hybrid_inputs = REoptInputs(input_data_hybrid)
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            non_hybrid_results = run_reopt(m2, non_hybrid_inputs)

            hybrid_GHP_size = hybrid_results["GHP"]["size_heat_pump_ton"]
            hybrid_GHX_size = hybrid_results["GHP"]["ghpghx_chosen_outputs"]["number_of_boreholes"] 
            hybrid_solution_nonhybrid_GHX_size = hybrid_results["GHP"]["number_of_boreholes_nonhybrid"]
            non_hybrid_GHP_size = non_hybrid_results["GHP"]["size_heat_pump_ton"]
            non_hybrid_GHX_size = non_hybrid_results["GHP"]["ghpghx_chosen_outputs"]["number_of_boreholes"] 

            @test hybrid_GHX_size < non_hybrid_GHX_size
            @test hybrid_GHX_size ≈ 5.0 atol=1.0
            @test hybrid_GHP_size ≈ non_hybrid_GHP_size atol=0.5
            @test hybrid_solution_nonhybrid_GHX_size ≈ non_hybrid_GHX_size atol=2.0

            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()     

            # Check GHP LCC calculation for URBANopt
            ghp_data = JSON.parsefile("scenarios/ghp_urbanopt.json")
            s = Scenario(ghp_data)
            ghp_inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results = run_reopt(m, ghp_inputs)
            ghp_lcc = results["Financial"]["lcc"]
            ghp_lccc = results["Financial"]["lifecycle_capital_costs"]
            ghp_lccc_initial = results["Financial"]["initial_capital_costs"]
            ghp_ebill = results["Financial"]["lifecycle_elecbill_after_tax"]
            boreholes = results["GHP"]["ghpghx_chosen_outputs"]["number_of_boreholes"]
            boreholes_len = results["GHP"]["ghpghx_chosen_outputs"]["length_boreholes_ft"]

            # Initial capital cost = initial cap cost of GHP + initial cap cost of hydronic loop
            @test ghp_lccc_initial - results["GHP"]["size_heat_pump_ton"]*1075 - ghp_data["GHP"]["building_sqft"]*1.7 ≈ 0.0 atol = 0.1
            # LCC = LCCC + Electricity Bill
            @test ghp_lcc - ghp_lccc - ghp_ebill ≈ 0.0 atol = 0.1
            # LCCC should be around be around 52% of initial capital cost due to incentive and bonus
            @test ghp_lccc/ghp_lccc_initial ≈ 0.518 atol = 0.01
            # GHX size must be 0
            @test boreholes ≈ 0.0 atol = 0.01
            @test boreholes_len ≈ 0.0 atol = 0.01
            finalize(backend(m))
            empty!(m)
            GC.gc()

            # Check GHX LCC calculation for URBANopt
            ghx_data = JSON.parsefile("scenarios/ghx_urbanopt.json")
            s = Scenario(ghx_data)
            ghx_inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results = run_reopt(m, ghx_inputs)
            ghx_lcc = results["Financial"]["lcc"]
            ghx_lccc = results["Financial"]["lifecycle_capital_costs"]
            ghx_lccc_initial = results["Financial"]["initial_capital_costs"]
            ghp_size = results["GHP"]["size_heat_pump_ton"]
            boreholes = results["GHP"]["ghpghx_chosen_outputs"]["number_of_boreholes"]
            boreholes_len = results["GHP"]["ghpghx_chosen_outputs"]["length_boreholes_ft"]
            
            # Initial capital cost = initial cap cost of GHX
            @test ghx_lccc_initial - boreholes*boreholes_len*14 ≈ 0.0 atol = 0.01
            # GHP size must be 0
            @test ghp_size ≈ 0.0 atol = 0.01
            # LCCC should be around 52% of initial capital cost due to incentive and bonus
            @test ghx_lccc/ghx_lccc_initial ≈ 0.518 atol = 0.01
            
            # User specified GHP size
            input_presizedGHP = deepcopy(input_data)
            input_presizedGHP["GHP"]["max_ton"] = 300
            input_presizedGHP["GHP"]["heatpump_capacity_sizing_factor_on_peak_load"] = 1.0
            delete!(input_presizedGHP["GHP"], "ghpghx_responses")
            # Rerun REopts
            s_presizedGHP = Scenario(input_presizedGHP)
            inputs_presizedGHP = REoptInputs(s_presizedGHP)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results = run_reopt([m1,m2], inputs_presizedGHP)
            # GHP output size should equal user-defined GHP size
            output_GHP_size = sum(results["GHP"]["size_heat_pump_ton"])
            @test output_GHP_size ≈ 300.00 atol=0.1
            
            # User specified max GHP and GHX sizes
            input_presizedGHPGHX = deepcopy(input_presizedGHP)
            input_presizedGHPGHX["GHP"]["max_number_of_boreholes"] = 400
            # Rerun REopts
            s_presizedGHPGHX = Scenario(input_presizedGHPGHX)
            inputs_presizedGHPGHX = REoptInputs(s_presizedGHPGHX)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results = run_reopt([m1,m2], inputs_presizedGHPGHX)
            # GHP output size should equal user-defined GHP size
            output_GHP_size = results["GHP"]["size_heat_pump_ton"]
            output_GHX_size = results["GHP"]["ghpghx_chosen_outputs"]["number_of_boreholes"]
            @test output_GHX_size ≈ 400.00 atol=0.5
            @test output_GHP_size < 300.00
            
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

        @testset "Hybrid GHX and GHP calculated costs validation" begin
            ## Hybrid GHP validation.
            # Load base inputs
            input_data = JSON.parsefile("scenarios/ghp_financial_hybrid.json")

            inputs = REoptInputs(input_data)

            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results = run_reopt([m1,m2], inputs)

            calculated_ghp_capital_costs = ((input_data["GHP"]["ghpghx_responses"][1]["outputs"]["number_of_boreholes"]*
            input_data["GHP"]["ghpghx_responses"][1]["outputs"]["length_boreholes_ft"]* 
            inputs.s.ghp_option_list[1].installed_cost_ghx_per_ft) + 
            (inputs.s.ghp_option_list[1].installed_cost_heatpump_per_ton*
            input_data["GHP"]["ghpghx_responses"][1]["outputs"]["peak_combined_heatpump_thermal_ton"]*
            inputs.s.ghp_option_list[1].heatpump_capacity_sizing_factor_on_peak_load) + 
            (inputs.s.ghp_option_list[1].building_sqft*
            inputs.s.ghp_option_list[1].installed_cost_building_hydronic_loop_per_sqft))

            @test results["Financial"]["initial_capital_costs"] ≈ calculated_ghp_capital_costs atol=0.1
            
            calculated_om_costs = inputs.s.ghp_option_list[1].building_sqft*
            inputs.s.ghp_option_list[1].om_cost_per_sqft_year * inputs.third_party_factor * inputs.pwf_om

            @test results["Financial"]["lifecycle_om_costs_before_tax"] ≈ calculated_om_costs atol=0.1

            calc_om_cost_after_tax = calculated_om_costs*(1-inputs.s.financial.owner_tax_rate_fraction)
            @test results["Financial"]["lifecycle_om_costs_after_tax"] - calc_om_cost_after_tax < 0.0001

            ghx_residual_value = value(m2[Symbol("ResidualGHXCapCost")])
            @test abs(results["Financial"]["lifecycle_capital_costs_plus_om_after_tax"] - (calc_om_cost_after_tax + 0.7*results["Financial"]["initial_capital_costs"] - ghx_residual_value)) < 150.0
            
            @test abs(results["Financial"]["lifecycle_capital_costs"] - (0.7*results["Financial"]["initial_capital_costs"] - ghx_residual_value)) < 150.0

            @test abs(results["Financial"]["npv"] - 840621) < 1.0
            @test abs(results["Financial"]["simple_payback_years"] - 3.59) < 0.1
            @test abs(results["Financial"]["internal_rate_of_return"] - 0.258) < 0.01

            @test haskey(results["ExistingBoiler"], "year_one_fuel_cost_before_tax_bau")
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()

            ## Hybrid
            input_data["GHP"]["ghpghx_responses"] = [JSON.parsefile("scenarios/ghpghx_hybrid_results.json")]
            input_data["GHP"]["avoided_capex_by_ghp_present_value"] = 1.0e6
            input_data["GHP"]["ghx_useful_life_years"] = 35

            inputs = REoptInputs(input_data)

            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results = run_reopt([m1,m2], inputs)

            pop!(input_data["GHP"], "ghpghx_inputs", nothing)
            pop!(input_data["GHP"], "ghpghx_responses", nothing)
            ghp_obj = REopt.GHP(JSON.parsefile("scenarios/ghpghx_hybrid_results.json"), input_data["GHP"]; sector="commercial/industrial", federal_procurement_type="")

            calculated_ghx_residual_value = ghp_obj.ghx_only_capital_cost*
            (
                (ghp_obj.ghx_useful_life_years - inputs.s.financial.analysis_years)/ghp_obj.ghx_useful_life_years
            )/(
                (1 + inputs.s.financial.offtaker_discount_rate_fraction)^inputs.s.financial.analysis_years
            )
            
            @test results["GHP"]["ghx_residual_value_present_value"] ≈ calculated_ghx_residual_value atol=0.1
            @test inputs.s.ghp_option_list[1].is_ghx_hybrid = true
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()            

            # Test centralized GHP cost calculations
            input_data_wwhp = JSON.parsefile("scenarios/ghp_inputs_wwhp.json")
            response_wwhp = JSON.parsefile("scenarios/ghpghx_response_wwhp.json")
            input_data_wwhp["GHP"]["ghpghx_responses"] = [response_wwhp]

            s_wwhp = Scenario(input_data_wwhp)
            inputs_wwhp = REoptInputs(s_wwhp)
            m3 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results_wwhp = run_reopt(m3, inputs_wwhp)


            heating_hp_cost = input_data_wwhp["GHP"]["installed_cost_wwhp_heating_pump_per_ton"] * 
                                input_data_wwhp["GHP"]["heatpump_capacity_sizing_factor_on_peak_load"] *
                                results_wwhp["GHP"]["ghpghx_chosen_outputs"]["peak_heating_heatpump_thermal_ton"]

            cooling_hp_cost = input_data_wwhp["GHP"]["installed_cost_wwhp_cooling_pump_per_ton"] * 
                                input_data_wwhp["GHP"]["heatpump_capacity_sizing_factor_on_peak_load"] *
                                results_wwhp["GHP"]["ghpghx_chosen_outputs"]["peak_cooling_heatpump_thermal_ton"]

            ghx_cost = input_data_wwhp["GHP"]["installed_cost_ghx_per_ft"] * 
                        results_wwhp["GHP"]["ghpghx_chosen_outputs"]["number_of_boreholes"] * 
                        results_wwhp["GHP"]["ghpghx_chosen_outputs"]["length_boreholes_ft"]

            # CAPEX reduction factor for 30% ITC, 5-year MACRS, assuming 26% tax rate and 8.3% discount
            capex_reduction_factor = 0.455005797

            calculated_ghp_capex = (heating_hp_cost + cooling_hp_cost + ghx_cost) * (1 - capex_reduction_factor)

            ghx_residual_value = value(m3[Symbol("ResidualGHXCapCost")])
            reopt_ghp_capex = results_wwhp["Financial"]["lifecycle_capital_costs"] + ghx_residual_value
            @test calculated_ghp_capex ≈ reopt_ghp_capex atol=300
            finalize(backend(m3))
            empty!(m3)
            GC.gc()
        end

        @testset "Cambium Emissions" begin
            """
            1) Location in contiguous US
                - Correct data from Cambium (returned location and values)
                - Adjusted for load year vs. Cambium year (which starts on Sunday) vs. AVERT year (2022 currently)
                - co2 pct increase should be zero
            2) HI and AK locations
                - Should use AVERT data and give an "info" message
                - Adjust for load year vs. AVERT year
                - co2 pct increase should be the default value unless user provided value 
            3) International 
                - all emissions should be zero unless provided
            """
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
        
            post_name = "cambium.json" 
            post = JSON.parsefile("./scenarios/$post_name")
        
            cities = Dict(
                "Denver" => (39.7413753050447, -104.99965032911328),
                "Fairbanks" => (64.84053664406181, -147.71913656313163),
                "Santiago" => (-33.44485437650408, -70.69031905547853)
            )
        
            # 1) Location in contiguous US
            city = "Denver"
            post["Site"]["latitude"] = cities[city][1]
            post["Site"]["longitude"] = cities[city][2]
            post["ElectricLoad"]["loads_kw"] = [20 for i in range(1,8760)]
            post["ElectricLoad"]["year"] = 2021 # 2021 First day is Fri
            scen = Scenario(post)
            
            @test scen.electric_utility.avert_emissions_region == "Rocky Mountains"
            @test scen.electric_utility.distance_to_avert_emissions_region_meters ≈ 0 atol=1e-5
            @test scen.electric_utility.cambium_region == "West Connect North"
            # Test that correct data is used, and adjusted to start on a Fri to align with load year of 2021
            avert_year = 2023 # Update when AVERT/eGRID data are updated
            ef_start_day = 7 # Sun. Update when AVERT/eGRID data are updated
            load_start_day = 5 # Fri
            cut_days = 7+(load_start_day-ef_start_day) # Ex: = 7+(5-7) = 5 --> cut Sun, Mon, Tues, Wed, Thurs
            so2_data = CSV.read("../data/emissions/AVERT_Data/AVERT_$(avert_year)_SO2_lb_per_kwh.csv", DataFrame)[!,"RM"]
            @test scen.electric_utility.emissions_factor_series_lb_SO2_per_kwh[1] ≈ so2_data[24*cut_days+1] # EF data should start on Fri

            @test scen.electric_utility.emissions_factor_CO2_decrease_fraction ≈ 0 atol=1e-5 # should be 0 with Cambium data
            @test scen.electric_utility.emissions_factor_SO2_decrease_fraction ≈ REopt.EMISSIONS_DECREASE_DEFAULTS["SO2"] 
            @test scen.electric_utility.emissions_factor_NOx_decrease_fraction ≈ REopt.EMISSIONS_DECREASE_DEFAULTS["NOx"]
            @test scen.electric_utility.emissions_factor_PM25_decrease_fraction ≈ REopt.EMISSIONS_DECREASE_DEFAULTS["PM25"]

            # 2) AK location
            city = "Fairbanks"
            post["Site"]["latitude"] = cities[city][1]
            post["Site"]["longitude"] = cities[city][2]
            scen = Scenario(post)
        
            @test scen.electric_utility.avert_emissions_region == "Alaska"
            @test scen.electric_utility.distance_to_avert_emissions_region_meters ≈ 0 atol=1e-5
            @test scen.electric_utility.cambium_region == "NA - Cambium data not used"
            @test sum(scen.electric_utility.emissions_factor_series_lb_CO2_per_kwh) / 8760 ≈ CSV.read("../data/emissions/AVERT_Data/AVERT_$(avert_year)_CO2_lb_per_kwh.csv", DataFrame)[!,"AKGD"][1] rtol=1e-3 # check that data from eGRID (AVERT data file) is used
            @test scen.electric_utility.emissions_factor_CO2_decrease_fraction ≈ REopt.EMISSIONS_DECREASE_DEFAULTS["CO2e"] # should get updated to this value
            @test scen.electric_utility.emissions_factor_SO2_decrease_fraction ≈ REopt.EMISSIONS_DECREASE_DEFAULTS["SO2"] # should be 2.163% for AVERT data
            @test scen.electric_utility.emissions_factor_NOx_decrease_fraction ≈ REopt.EMISSIONS_DECREASE_DEFAULTS["NOx"]
            @test scen.electric_utility.emissions_factor_PM25_decrease_fraction ≈ REopt.EMISSIONS_DECREASE_DEFAULTS["PM25"]        

            # 3) International location
            city = "Santiago"
            post["Site"]["latitude"] = cities[city][1]
            post["Site"]["longitude"] = cities[city][2]
            scen = Scenario(post)
            
            @test scen.electric_utility.avert_emissions_region == ""
            @test scen.electric_utility.distance_to_avert_emissions_region_meters ≈ 5.521032136418236e6 atol=1.0
            @test scen.electric_utility.cambium_region == "NA - Cambium data not used"
            @test sum(scen.electric_utility.emissions_factor_series_lb_CO2_per_kwh) ≈ 0 
            @test sum(scen.electric_utility.emissions_factor_series_lb_NOx_per_kwh) ≈ 0 
            @test sum(scen.electric_utility.emissions_factor_series_lb_SO2_per_kwh) ≈ 0 
            @test sum(scen.electric_utility.emissions_factor_series_lb_PM25_per_kwh) ≈ 0 
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()
            
        end

        @testset "Emissions and Renewable Energy Percent" begin
            #renewable energy and emissions reduction targets
            include_exported_RE_in_total = [true,false,true]
            include_exported_ER_in_total = [true,false,true]
            RE_target = [0.8,nothing,nothing]
            ER_target = [nothing,0.8,nothing]
            with_outage = [true,false,false]

            for i in range(1, stop=3)
                if i == 3
                    inputs = JSON.parsefile("./scenarios/re_emissions_with_thermal.json")
                else
                    inputs = JSON.parsefile("./scenarios/re_emissions_elec_only.json")
                end
                if i == 1
                    inputs["Site"]["latitude"] = 37.746
                    inputs["Site"]["longitude"] = -122.448
                    # inputs["ElectricUtility"]["emissions_region"] = "California"
                end
                inputs["Site"]["include_exported_renewable_electricity_in_total"] = include_exported_RE_in_total[i]
                inputs["Site"]["include_exported_elec_emissions_in_total"] = include_exported_ER_in_total[i]
                inputs["Site"]["renewable_electricity_min_fraction"] = if isnothing(RE_target[i]) 0.0 else RE_target[i] end
                inputs["Site"]["renewable_electricity_max_fraction"] = RE_target[i]
                inputs["Site"]["CO2_emissions_reduction_min_fraction"] = ER_target[i]
                inputs["Site"]["CO2_emissions_reduction_max_fraction"] = ER_target[i]
                if with_outage[i]
                    outage_start_hour = 4032
                    outage_duration = 2000 #hrs
                    inputs["ElectricUtility"]["outage_start_time_step"] = outage_start_hour + 1
                    inputs["ElectricUtility"]["outage_end_time_step"] = outage_start_hour + 1 + outage_duration
                    inputs["Generator"]["max_kw"] = 20
                    inputs["Generator"]["existing_kw"] = 2
                    inputs["Generator"]["fuel_avail_gal"] = 1000 
                end

                m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
                m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
                results = run_reopt([m1, m2], inputs)

                if !isnothing(ER_target[i])  
                    ER_fraction_out = results["Site"]["lifecycle_emissions_reduction_CO2_fraction"]
                    @test ER_target[i] ≈ ER_fraction_out atol=1e-3
                    lifecycle_emissions_tonnes_CO2_out = results["Site"]["lifecycle_emissions_tonnes_CO2"]
                    lifecycle_emissions_bau_tonnes_CO2_out = results["Site"]["lifecycle_emissions_tonnes_CO2_bau"]
                    ER_fraction_calced_out = (lifecycle_emissions_bau_tonnes_CO2_out-lifecycle_emissions_tonnes_CO2_out)/lifecycle_emissions_bau_tonnes_CO2_out
                    ER_fraction_diff = abs(ER_fraction_calced_out-ER_fraction_out)
                    @test ER_fraction_diff ≈ 0.0 atol=1e-2
                end

                annual_emissions_tonnes_CO2_out = results["Site"]["annual_emissions_tonnes_CO2"]
                yr1_fuel_emissions_tonnes_CO2_out = results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"]
                yr1_grid_emissions_tonnes_CO2_out = results["ElectricUtility"]["annual_emissions_tonnes_CO2"]
                yr1_total_emissions_calced_tonnes_CO2 = yr1_fuel_emissions_tonnes_CO2_out + yr1_grid_emissions_tonnes_CO2_out 
                @test annual_emissions_tonnes_CO2_out ≈ yr1_total_emissions_calced_tonnes_CO2 atol=1e-1
                if haskey(results["Financial"],"breakeven_cost_of_emissions_reduction_per_tonne_CO2")
                    @test results["Financial"]["breakeven_cost_of_emissions_reduction_per_tonne_CO2"] >= 0.0
                end
                
                if i == 1
                    @test results["PV"]["size_kw"] ≈ 59.7222 atol=1e-1
                    @test results["ElectricStorage"]["size_kw"] ≈ 0.0 atol=1e-1
                    @test results["ElectricStorage"]["size_kwh"] ≈ 0.0 atol=1e-1
                    @test results["Generator"]["size_kw"] ≈ 9.13 atol=1e-1
                    @test results["Site"]["onsite_renewable_energy_fraction_of_total_load"] ≈ 0.8
                    @test results["Site"]["onsite_renewable_energy_fraction_of_total_load_bau"] ≈ 0.148375 atol=1e-4
                    @test results["Site"]["lifecycle_emissions_reduction_CO2_fraction"] ≈ 0.587 rtol=0.01
                    @test results["Financial"]["breakeven_cost_of_emissions_reduction_per_tonne_CO2"] ≈ 336.4 rtol=0.01
                    @test results["Site"]["annual_emissions_tonnes_CO2"] ≈ 11.1 rtol=0.01
                    @test results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"] ≈ 7.427 rtol=0.01
                    @test results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2_bau"] ≈ 0.0
                    @test results["Site"]["lifecycle_emissions_tonnes_CO2"] ≈ 222.26 rtol=0.01
                    @test results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_CO2"] ≈ 148.54
                    @test results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_CO2_bau"] ≈ 0.0
                    @test results["ElectricUtility"]["annual_emissions_tonnes_CO2_bau"] ≈ 26.9 rtol=0.01
                    @test results["ElectricUtility"]["lifecycle_emissions_tonnes_CO2_bau"] ≈ 537.99 rtol=0.01
                elseif i == 2
                    #commented out values are results using same levelization factor as API
                    @test results["PV"]["size_kw"] ≈ 99.35 rtol=0.01
                    @test results["ElectricStorage"]["size_kw"] ≈ 20.09 atol=1 # 20.29
                    @test results["ElectricStorage"]["size_kwh"] ≈ 156.4 rtol=0.01
                    @test !haskey(results, "Generator")
                    # Renewable energy
                    @test results["Site"]["onsite_renewable_electricity_fraction_of_elec_load"] ≈ 0.745 rtol=0.01
                    @test results["Site"]["onsite_renewable_electricity_fraction_of_elec_load_bau"] ≈ 0.132118 atol=1e-3 #0.1354 atol=1e-3
                    @test results["Site"]["annual_onsite_renewable_electricity_kwh_bau"] ≈ 13308.5 atol=10 # 13542.62 atol=10
                    @test results["Site"]["onsite_renewable_energy_fraction_of_total_load_bau"] ≈ 0.132118 atol=1e-3 # 0.1354 atol=1e-3
                    # CO2 emissions - totals ≈  from grid, from fuelburn, ER, $/tCO2 breakeven
                    @test results["Site"]["lifecycle_emissions_reduction_CO2_fraction"] ≈ 0.8 atol=1e-3 # 0.8
                    @test results["Site"]["annual_emissions_tonnes_CO2"] ≈ 11.79 rtol=0.01
                    @test results["Site"]["annual_emissions_tonnes_CO2_bau"] ≈ 58.97 rtol=0.01
                    @test results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"] ≈ 0.0 atol=1 # 0.0
                    @test results["Financial"]["lifecycle_emissions_cost_climate"] ≈ 8496.6 rtol=0.01
                    @test results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_CO2"] ≈ 0.0 atol=1 # 0.0
                    @test results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_CO2_bau"] ≈ 0.0 atol=1 # 0.0
                    @test results["ElectricUtility"]["lifecycle_emissions_tonnes_CO2"] ≈ 235.9 rtol=0.01
        
        
                    #also test CO2 breakeven cost
                    inputs["PV"]["min_kw"] = results["PV"]["size_kw"] - inputs["PV"]["existing_kw"]
                    inputs["PV"]["max_kw"] = results["PV"]["size_kw"] - inputs["PV"]["existing_kw"]
                    inputs["ElectricStorage"]["min_kw"] = results["ElectricStorage"]["size_kw"]
                    inputs["ElectricStorage"]["max_kw"] = results["ElectricStorage"]["size_kw"]
                    inputs["ElectricStorage"]["min_kwh"] = results["ElectricStorage"]["size_kwh"]
                    inputs["ElectricStorage"]["max_kwh"] = results["ElectricStorage"]["size_kwh"]
                    inputs["Financial"]["CO2_cost_per_tonne"] = results["Financial"]["breakeven_cost_of_emissions_reduction_per_tonne_CO2"]
                    inputs["Settings"]["include_climate_in_objective"] = true
                    m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
                    m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "presolve" => "on"))
                    results = run_reopt([m1, m2], inputs)
                    @test results["Financial"]["breakeven_cost_of_emissions_reduction_per_tonne_CO2"] ≈ inputs["Financial"]["CO2_cost_per_tonne"] rtol=0.001
                elseif i == 3
                    @test results["PV"]["size_kw"] ≈ 20.0 atol=1e-1
                    @test !haskey(results, "Wind")
                    @test !haskey(results, "ElectricStorage")
                    @test !haskey(results, "Generator")
                    @test results["CHP"]["size_kw"] ≈ 200.0 atol=1e-1
                    @test results["AbsorptionChiller"]["size_ton"] ≈ 400.0 atol=1e-1
                    @test results["HotThermalStorage"]["size_gal"] ≈ 50000 atol=1e1
                    @test results["ColdThermalStorage"]["size_gal"] ≈ 30000 atol=1e1
                    yr1_nat_gas_mmbtu = results["ExistingBoiler"]["annual_fuel_consumption_mmbtu"] + results["CHP"]["annual_fuel_consumption_mmbtu"]
                    nat_gas_emissions_lb_per_mmbtu = Dict("CO2"=>117.03, "NOx"=>0.09139, "SO2"=>0.000578592, "PM25"=>0.007328833)
                    TONNE_PER_LB = 1/2204.62
                    @test results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"] ≈ nat_gas_emissions_lb_per_mmbtu["CO2"] * yr1_nat_gas_mmbtu * TONNE_PER_LB atol=1
                    @test results["Site"]["annual_emissions_from_fuelburn_tonnes_NOx"] ≈ nat_gas_emissions_lb_per_mmbtu["NOx"] * yr1_nat_gas_mmbtu * TONNE_PER_LB atol=1e-2
                    @test results["Site"]["annual_emissions_from_fuelburn_tonnes_SO2"] ≈ nat_gas_emissions_lb_per_mmbtu["SO2"] * yr1_nat_gas_mmbtu * TONNE_PER_LB atol=1e-2
                    @test results["Site"]["annual_emissions_from_fuelburn_tonnes_PM25"] ≈ nat_gas_emissions_lb_per_mmbtu["PM25"] * yr1_nat_gas_mmbtu * TONNE_PER_LB atol=1e-2
                    @test results["Site"]["lifecycle_emissions_tonnes_CO2"] ≈ results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_CO2"] + results["ElectricUtility"]["lifecycle_emissions_tonnes_CO2"] rtol=0.001
                    @test results["Site"]["lifecycle_emissions_tonnes_NOx"] ≈ results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_NOx"] + results["ElectricUtility"]["lifecycle_emissions_tonnes_NOx"] rtol=0.001
                    @test results["Site"]["lifecycle_emissions_tonnes_SO2"] ≈ results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_SO2"] + results["ElectricUtility"]["lifecycle_emissions_tonnes_SO2"] rtol=0.01 # rounding causes difference
                    @test results["Site"]["lifecycle_emissions_tonnes_PM25"] ≈ results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_PM25"] + results["ElectricUtility"]["lifecycle_emissions_tonnes_PM25"] rtol=0.001
                    @test results["Site"]["annual_onsite_renewable_electricity_kwh"] ≈ results["PV"]["annual_energy_produced_kwh"] + inputs["CHP"]["fuel_renewable_energy_fraction"] * results["CHP"]["annual_electric_production_kwh"] atol=1
                    @test results["Site"]["onsite_renewable_electricity_fraction_of_elec_load"] ≈ results["Site"]["annual_onsite_renewable_electricity_kwh"] / results["ElectricLoad"]["annual_electric_load_with_thermal_conversions_kwh"] rtol=0.001
                    annual_RE_kwh = inputs["CHP"]["fuel_renewable_energy_fraction"] * results["CHP"]["annual_thermal_production_mmbtu"] * REopt.KWH_PER_MMBTU + results["Site"]["annual_onsite_renewable_electricity_kwh"]
                    annual_heat_kwh = (results["CHP"]["annual_thermal_production_mmbtu"] + results["ExistingBoiler"]["annual_thermal_production_mmbtu"]) * REopt.KWH_PER_MMBTU
                    @test results["Site"]["onsite_renewable_energy_fraction_of_total_load"] ≈ annual_RE_kwh / (annual_heat_kwh + results["ElectricLoad"]["annual_electric_load_with_thermal_conversions_kwh"]) rtol=0.001
                end
                finalize(backend(m1))
                empty!(m1)
                finalize(backend(m2))
                empty!(m2)
                GC.gc()                
            end
        end

        @testset "Renewable Energy from Grid" begin
            # Test RE calc
            inputs = JSON.parsefile("./scenarios/re_emissions_elec_only.json") # PV, Generator, ElectricStorage
            
            s = Scenario(inputs)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, inputs)

            bess_effic = 0.96*0.975^0.5*0.96*0.975^0.5
            grid2load = results["ElectricUtility"]["electric_to_load_series_kw"]
            grid2bess = results["ElectricUtility"]["electric_to_storage_series_kw"]
            gridRE = sum((grid2load + grid2bess * bess_effic) .* s.electric_utility.renewable_energy_fraction_series)
            pv2load = sum(results["PV"]["electric_to_load_series_kw"])
            pv2grid = sum(results["PV"]["electric_to_grid_series_kw"])
            pv2bess = sum(results["PV"]["electric_to_storage_series_kw"])
            onsiteRE = pv2load + pv2grid + pv2bess * bess_effic
            
            @test results["ElectricUtility"]["annual_renewable_electricity_supplied_kwh"] ≈ gridRE rtol=1e-4
            @test results["Site"]["onsite_and_grid_renewable_electricity_fraction_of_elec_load"] ≈ ((onsiteRE+gridRE) / results["ElectricLoad"]["annual_calculated_kwh"]) rtol=1e-3
            
            finalize(backend(m))
            empty!(m)
            GC.gc()

            # TODO: Add tests with heating techs (ASHP or GHP) once AnnualEleckWh is updated
        end

        @testset "Back pressure steam turbine" begin
            """
            Validation to ensure that:
                1) ExistingBoiler provides the thermal energy (steam) to a backpressure SteamTurbine for CHP application
                2) SteamTurbine serves the heating load with the condensing steam

            """
            # Setup inputs, make heating load large to entice SteamTurbine
            input_data = JSON.parsefile("scenarios/backpressure_steamturbine_inputs.json")
            latitude = input_data["Site"]["latitude"]
            longitude = input_data["Site"]["longitude"]
            building = "Hospital"
            elec_load_multiplier = 5.0
            heat_load_multiplier = 100.0
            input_data["ElectricLoad"]["doe_reference_name"] = building
            input_data["SpaceHeatingLoad"]["doe_reference_name"] = building
            input_data["DomesticHotWaterLoad"]["doe_reference_name"] = building
            elec_load = REopt.ElectricLoad(latitude=latitude, longitude=longitude, doe_reference_name=building)
            input_data["ElectricLoad"]["annual_kwh"] = elec_load_multiplier * sum(elec_load.loads_kw)
            space_load = REopt.HeatingLoad(load_type="space_heating", latitude=latitude, longitude=longitude, doe_reference_name=building, existing_boiler_efficiency=input_data["ExistingBoiler"]["efficiency"])
            input_data["SpaceHeatingLoad"]["annual_mmbtu"] = heat_load_multiplier * space_load.annual_mmbtu / input_data["ExistingBoiler"]["efficiency"]
            dhw_load = REopt.HeatingLoad(load_type="domestic_hot_water", latitude=latitude, longitude=longitude, doe_reference_name=building, existing_boiler_efficiency=input_data["ExistingBoiler"]["efficiency"])
            input_data["DomesticHotWaterLoad"]["annual_mmbtu"] = heat_load_multiplier * dhw_load.annual_mmbtu / input_data["ExistingBoiler"]["efficiency"]
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt([m1,m2], inputs)

            # The expected values below were directly copied from the REopt_API V2 expected values
            @test results["Financial"]["lcc"] ≈ 189359280.0 rtol=0.001
            @test results["Financial"]["npv"] ≈ 8085233.0 rtol=0.01
            @test results["SteamTurbine"]["size_kw"] ≈ 2616.418 atol=1.0
            @test results["SteamTurbine"]["annual_thermal_consumption_mmbtu"] ≈ 1000557.6 rtol=0.001
            @test results["SteamTurbine"]["annual_electric_production_kwh"] ≈ 18970374.6 rtol=0.001
            @test results["SteamTurbine"]["annual_thermal_production_mmbtu"] ≈ 924045.1 rtol=0.001

            # BAU boiler loads
            load_boiler_fuel = (s.space_heating_load.loads_kw + s.dhw_load.loads_kw) ./ REopt.KWH_PER_MMBTU ./ s.existing_boiler.efficiency
            load_boiler_thermal = load_boiler_fuel * s.existing_boiler.efficiency

            # ExistingBoiler and SteamTurbine production
            boiler_to_load = results["ExistingBoiler"]["thermal_to_load_series_mmbtu_per_hour"]
            boiler_to_st = results["ExistingBoiler"]["thermal_to_steamturbine_series_mmbtu_per_hour"]
            boiler_total = boiler_to_load + boiler_to_st
            st_to_load = results["SteamTurbine"]["thermal_to_load_series_mmbtu_per_hour"]

            # Fuel/thermal **consumption**
            boiler_fuel = results["ExistingBoiler"]["fuel_consumption_series_mmbtu_per_hour"]
            steamturbine_thermal_in = results["SteamTurbine"]["thermal_consumption_series_mmbtu_per_hour"]

            # Check that all thermal supply to load meets the BAU load
            thermal_to_load = sum(boiler_to_load) + sum(st_to_load)
            @test thermal_to_load ≈ sum(load_boiler_thermal) atol=1.0

            # Check the net electric efficiency of Boiler->SteamTurbine (electric out/fuel in) with the expected value from the Fact Sheet 
            steamturbine_electric = results["SteamTurbine"]["electric_production_series_kw"] 
            net_electric_efficiency = sum(steamturbine_electric) / (sum(boiler_fuel) * REopt.KWH_PER_MMBTU)
            @test net_electric_efficiency ≈ 0.052 atol=0.005

            # Check that the max production of the boiler is still less than peak heating load times thermal factor
            factor = input_data["ExistingBoiler"]["max_thermal_factor_on_peak_load"]
            boiler_capacity = maximum(load_boiler_thermal) * factor
            @test maximum(boiler_total) <= boiler_capacity

            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()
        end

        @testset "All heating supply/demand/storage energy balance" begin
            """
            Validation to ensure that:
                1) Heat balance is correct with SteamTurbine (backpressure), CHP, HotTES, and AbsorptionChiller included
                2) The sum of a all thermal from techs supplying SteamTurbine is equal to SteamTurbine thermal consumption
                3) Techs are not supplying SteamTurbine with thermal if can_supply_steam_turbine = False
            
            :return:
            """
            
            # Start with steam turbine inputs, but adding a bunch below
            input_data = JSON.parsefile("scenarios/backpressure_steamturbine_inputs.json")
            input_data["ElectricLoad"]["doe_reference_name"] = "Hospital"
            # Add SpaceHeatingLoad building for heating loads, ignore DomesticHotWaterLoad for simplicity of energy balance checks
            input_data["SpaceHeatingLoad"]["doe_reference_name"] = "Hospital"
            delete!(input_data, "DomesticHotWaterLoad")
            
            # Fix size of SteamTurbine, even if smaller than practical, because we're just looking at energy balances
            input_data["SteamTurbine"]["min_kw"] = 30.0
            input_data["SteamTurbine"]["max_kw"] = 30.0
            
            # Add CHP 
            input_data["CHP"] = Dict{Any, Any}([
                                ("prime_mover", "recip_engine"),
                                ("size_class", 4),
                                ("min_kw", 250.0),
                                ("min_allowable_kw", 0.0),
                                ("max_kw", 250.0),
                                ("can_supply_steam_turbine", false),
                                ("fuel_cost_per_mmbtu", 8.0),
                                ("cooling_thermal_factor", 1.0)
                                ])
            
            input_data["Financial"]["chp_fuel_cost_escalation_rate_fraction"] = 0.034
            
            # Add CoolingLoad and AbsorptionChiller so we can test the energy balance on AbsorptionChiller too (thermal consumption)
            input_data["CoolingLoad"] = Dict{Any, Any}("doe_reference_name" => "Hospital")
            input_data["AbsorptionChiller"] = Dict{Any, Any}([
                                                ("min_ton", 600.0),
                                                ("max_ton", 600.0),
                                                ("cop_thermal", 0.7),
                                                ("installed_cost_per_ton", 500.0),
                                                ("om_cost_per_ton", 0.5),
                                                ("heating_load_input", "SpaceHeating")
                                                ])
            
            # Add Hot TES
            input_data["HotThermalStorage"] = Dict{Any, Any}([
                                    ("min_gal", 50000.0),
                                    ("max_gal", 50000.0)
                                    ])
            
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results = run_reopt(m, inputs)
            
            thermal_techs = ["ExistingBoiler", "CHP", "SteamTurbine"]
            thermal_loads = ["load", "storage", "steamturbine", "waste"]  # We don't track AbsorptionChiller thermal consumption by tech
            tech_to_thermal_load = Dict{Any, Any}()
            for tech in thermal_techs
                tech_to_thermal_load[tech] = Dict{Any, Any}()
                for load in thermal_loads
                    if (tech == "SteamTurbine" && load == "steamturbine") || (load == "waste" && tech != "CHP")
                        tech_to_thermal_load[tech][load] = [0.0] * 8760
                    else
                        if load == "waste"
                            tech_to_thermal_load[tech][load] = results[tech]["thermal_curtailed_series_mmbtu_per_hour"]
                        else
                            tech_to_thermal_load[tech][load] = results[tech]["thermal_to_"*load*"_series_mmbtu_per_hour"]
                        end
                    end
                end
            end
            # Hot TES is the other thermal supply
            hottes_to_load = results["HotThermalStorage"]["storage_to_load_series_mmbtu_per_hour"]
            
            # BAU boiler loads
            load_boiler_fuel = s.space_heating_load.loads_kw / input_data["ExistingBoiler"]["efficiency"] ./ REopt.KWH_PER_MMBTU
            load_boiler_thermal = load_boiler_fuel .* input_data["ExistingBoiler"]["efficiency"]
            
            # Fuel/thermal **consumption**
            boiler_fuel = results["ExistingBoiler"]["fuel_consumption_series_mmbtu_per_hour"]
            chp_fuel_total = results["CHP"]["annual_fuel_consumption_mmbtu"]
            steamturbine_thermal_in = results["SteamTurbine"]["thermal_consumption_series_mmbtu_per_hour"]
            absorptionchiller_thermal_in = results["AbsorptionChiller"]["thermal_consumption_series_mmbtu_per_hour"]
            
            # Check that all thermal supply to load meets the BAU load plus AbsorptionChiller load which is not explicitly tracked
            alltechs_thermal_to_load_total = sum([sum(tech_to_thermal_load[tech]["load"]) for tech in thermal_techs]) + sum(hottes_to_load)
            thermal_load_total = sum(load_boiler_thermal) + sum(absorptionchiller_thermal_in)
            @test alltechs_thermal_to_load_total ≈ thermal_load_total rtol=1e-5
            
            # Check that all thermal to steam turbine is equal to steam turbine thermal consumption
            alltechs_thermal_to_steamturbine_total = sum([sum(tech_to_thermal_load[tech]["steamturbine"]) for tech in ["ExistingBoiler", "CHP"]])
            @test alltechs_thermal_to_steamturbine_total ≈ sum(steamturbine_thermal_in) atol=3
            
            # Check that "thermal_to_steamturbine" is zero for each tech which has input of can_supply_steam_turbine as False
            for tech in ["ExistingBoiler", "CHP"]
                if !(tech in inputs.techs.can_supply_steam_turbine)
                    @test sum(tech_to_thermal_load[tech]["steamturbine"]) == 0.0
                end
            end
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

        @testset "Electric Heater" begin
            d = JSON.parsefile("./scenarios/electric_heater.json")
            d["SpaceHeatingLoad"]["annual_mmbtu"] = 0.4 * 8760
            d["DomesticHotWaterLoad"]["annual_mmbtu"] = 0.4 * 8760
            d["ProcessHeatLoad"]["annual_mmbtu"] = 0.2 * 8760
            s = Scenario(d)
            p = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, p)

            #first run: Boiler produces the required heat instead of the electric heater - electric heater should not be purchased
            @test results["ElectricHeater"]["size_mmbtu_per_hour"] ≈ 0.0 atol=0.1
            @test results["ElectricHeater"]["annual_thermal_production_mmbtu"] ≈ 0.0 atol=0.1
            @test results["ElectricHeater"]["annual_electric_consumption_kwh"] ≈ 0.0 atol=0.1
            @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ 87600.0 atol=0.1
            finalize(backend(m))
            empty!(m)
            GC.gc()             
            
            d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = 100
            d["ElectricHeater"]["installed_cost_per_mmbtu_per_hour"] = 1.0
            d["ElectricTariff"]["monthly_energy_rates"] = [0,0,0,0,0,0,0,0,0,0,0,0]
            s = Scenario(d)
            p = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, p)
            annual_thermal_prod = 0.64 * 8760  #80% efficient boiler --> 0.64 MMBTU of heat load per hour for electric heater
            annual_electric_heater_consumption = annual_thermal_prod * REopt.KWH_PER_MMBTU  #1.0 COP
            annual_energy_supplied = 87600 + annual_electric_heater_consumption

            #Second run: ElectricHeater produces the required heat with free electricity for two of three heat sources
            @test results["ElectricHeater"]["size_mmbtu_per_hour"] ≈ 0.64 atol=0.1
            @test results["ElectricHeater"]["annual_thermal_production_mmbtu"] ≈ annual_thermal_prod rtol=1e-4
            @test results["ElectricHeater"]["annual_electric_consumption_kwh"] ≈ annual_electric_heater_consumption rtol=1e-4
            @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ annual_energy_supplied rtol=1e-4
            #no bypass of Electric Heater through Hot TES to process heat
            @test sum(results["HotThermalStorage"]["storage_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

        @testset "ASHP" begin
            @testset "ASHP Space Heater" begin
                #Case 1: Boiler and existing chiller produce the required heat and cooling - ASHP is not purchased
                d = JSON.parsefile("./scenarios/ashp.json")
                d["SpaceHeatingLoad"]["annual_mmbtu"] = 1.0 * 8760
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)
                @test results["ASHPSpaceHeater"]["size_ton"] ≈ 0.0 atol=0.1
                @test results["ASHPSpaceHeater"]["annual_thermal_production_mmbtu"] ≈ 0.0 atol=0.1
                @test results["ASHPSpaceHeater"]["annual_electric_consumption_kwh"] ≈ 0.0 atol=0.1
                @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ 87600.0 atol=0.1

                #Case 2: ASHP has temperature-dependent output and serves all heating load
                d["ExistingChiller"] = Dict("retire_in_optimal" => false)
                d["ExistingBoiler"]["retire_in_optimal"] = false
                d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = 100
                d["ASHPSpaceHeater"]["installed_cost_per_ton"] = 300
                d["ASHPSpaceHeater"]["min_allowable_ton"] = 80.0
                finalize(backend(m))
                empty!(m)
                GC.gc()

                s = Scenario(d)
                p = REoptInputs(s)            
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)
                annual_thermal_prod = 0.8 * 8760  #80% efficient boiler --> 0.8 MMBTU of heat load per hour
                annual_ashp_consumption = sum(0.8 * REopt.KWH_PER_MMBTU / p.heating_cop["ASHPSpaceHeater"][ts] for ts in p.time_steps)
                annual_energy_supplied = 87600 + annual_ashp_consumption
                @test results["ASHPSpaceHeater"]["size_ton"] ≈ 80.0 atol=0.01
                @test results["ASHPSpaceHeater"]["annual_thermal_production_mmbtu"] ≈ annual_thermal_prod rtol=1e-4
                @test results["ASHPSpaceHeater"]["annual_electric_consumption_kwh"] ≈ annual_ashp_consumption rtol=1e-4
                @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ annual_energy_supplied rtol=1e-4
                @test results["ASHPSpaceHeater"]["annual_thermal_production_tonhour"] ≈ 0.0 atol=1e-4

                #Case 3: ASHP can serve cooling, add cooling load
                d["CoolingLoad"] = Dict("thermal_loads_ton" => ones(8760)*0.1)
                d["ExistingChiller"] = Dict("cop" => 0.5)
                d["ASHPSpaceHeater"]["can_serve_cooling"] = true
                finalize(backend(m))
                empty!(m)
                GC.gc()

                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)

                annual_ashp_consumption += 0.1 * sum(REopt.KWH_THERMAL_PER_TONHOUR / p.cooling_cop["ASHPSpaceHeater"][ts] for ts in p.time_steps)
                annual_energy_supplied = annual_ashp_consumption + 87600 - 2*876.0*REopt.KWH_THERMAL_PER_TONHOUR
                @test results["ASHPSpaceHeater"]["size_ton"] ≈ 80.0 atol=0.01 #size increases when cooling load also served
                @test results["ASHPSpaceHeater"]["annual_electric_consumption_kwh"] ≈ annual_ashp_consumption rtol=1e-4
                @test results["ASHPSpaceHeater"]["annual_thermal_production_tonhour"] ≈ 876.0 rtol=1e-4
                finalize(backend(m))
                empty!(m)
                GC.gc()
            
                #Case 4: ASHP used for everything because the existing boiler and chiller are retired even if efficient or free to operate
                d["ExistingChiller"] = Dict("retire_in_optimal" => true, "cop" => 100)
                d["ExistingBoiler"]["retire_in_optimal"] = true
                d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = 0
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)
                @test results["ASHPSpaceHeater"]["annual_electric_consumption_kwh"] ≈ annual_ashp_consumption rtol=1e-4
                @test results["ASHPSpaceHeater"]["annual_thermal_production_tonhour"] ≈ 876.0 atol=1e-4
                finalize(backend(m))
                empty!(m)
                GC.gc()

            end

            @testset "ASHP Water Heater" begin
                #Case 1: Boiler and existing chiller produce the required heat and cooling - ASHP_WH is not purchased
                d = JSON.parsefile("./scenarios/ashp_wh.json")
                d["SpaceHeatingLoad"]["annual_mmbtu"] = 0.5 * 8760
                d["DomesticHotWaterLoad"]["annual_mmbtu"] = 0.5 * 8760
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)
                @test results["ASHPWaterHeater"]["size_ton"] ≈ 0.0 atol=0.1
                @test results["ASHPWaterHeater"]["annual_thermal_production_mmbtu"] ≈ 0.0 atol=0.1
                @test results["ASHPWaterHeater"]["annual_electric_consumption_kwh"] ≈ 0.0 atol=0.1
                @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ 87600.0 atol=0.1
            
                #Case 2: ASHP_WH has temperature-dependent output and serves all DHW load
                d["ExistingChiller"] = Dict("retire_in_optimal" => false)
                d["ExistingBoiler"]["retire_in_optimal"] = false
                d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = 100
                d["ASHPWaterHeater"]["installed_cost_per_ton"] = 300
                finalize(backend(m))
                empty!(m)
                GC.gc()
                          
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)
                annual_thermal_prod = 0.4 * 8760  #80% efficient boiler --> 0.8 MMBTU of heat load per hour
                annual_ashp_consumption = sum(0.4 * REopt.KWH_PER_MMBTU / p.heating_cop["ASHPWaterHeater"][ts] for ts in p.time_steps)
                annual_energy_supplied = 87600 + annual_ashp_consumption
                @test results["ASHPWaterHeater"]["size_ton"] ≈ 37.673 atol=0.1
                @test results["ASHPWaterHeater"]["annual_thermal_production_mmbtu"] ≈ annual_thermal_prod rtol=1e-4
                @test results["ASHPWaterHeater"]["annual_electric_consumption_kwh"] ≈ annual_ashp_consumption rtol=1e-4
                @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ annual_energy_supplied rtol=1e-4
                finalize(backend(m))
                empty!(m)
                GC.gc()
            end

            @testset "Force in ASHP systems" begin
                d = JSON.parsefile("./scenarios/ashp.json")
                d["SpaceHeatingLoad"]["annual_mmbtu"] = 0.5 * 8760
                d["DomesticHotWaterLoad"] = Dict{String,Any}("annual_mmbtu" => 0.5 * 8760, "doe_reference_name" => "FlatLoad")
                d["CoolingLoad"] = Dict{String,Any}("thermal_loads_ton" => ones(8760)*0.1)
                d["ExistingChiller"] = Dict{String,Any}("retire_in_optimal" => false, "cop" => 100)
                d["ExistingBoiler"]["retire_in_optimal"] = false
                d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = 0.001
                d["ASHPSpaceHeater"]["can_serve_cooling"] = true
                d["ASHPSpaceHeater"]["force_into_system"] = true
                d["ASHPWaterHeater"] = Dict{String,Any}("force_into_system" => true, "force_dispatch" => false, "max_ton" => 100000)
                
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)
            
                @test results["ASHPWaterHeater"]["annual_electric_consumption_kwh"] ≈ sum(0.4 * REopt.KWH_PER_MMBTU / p.heating_cop["ASHPWaterHeater"][ts] for ts in p.time_steps) rtol=1e-4
                @test results["ASHPSpaceHeater"]["annual_thermal_production_mmbtu"] ≈ 0.4 * 8760 rtol=1e-4
                @test results["ASHPSpaceHeater"]["annual_thermal_production_tonhour"] ≈ 876.0 rtol=1e-4
                finalize(backend(m))
                empty!(m)
                GC.gc()

                d["ASHPSpaceHeater"]["force_into_system"] = false
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)

                @test results["ASHPWaterHeater"]["annual_electric_consumption_kwh"] ≈ sum(0.4 * REopt.KWH_PER_MMBTU / p.heating_cop["ASHPWaterHeater"][ts] for ts in p.time_steps) rtol=1e-4
                @test results["ExistingBoiler"]["annual_thermal_production_mmbtu"] ≈ 0.4 * 8760 rtol=1e-4
                @test results["ExistingChiller"]["annual_thermal_production_tonhour"] ≈ 876.0 rtol=1e-4
                finalize(backend(m))
                empty!(m)
                GC.gc()

                d["ASHPSpaceHeater"]["force_into_system"] = true
                d["ASHPWaterHeater"]["force_into_system"] = false
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)

                @test results["ASHPSpaceHeater"]["annual_thermal_production_mmbtu"] ≈ 0.4 * 8760 rtol=1e-4
                @test results["ASHPSpaceHeater"]["annual_thermal_production_tonhour"] ≈ 876.0 rtol=1e-4
                @test results["ExistingBoiler"]["annual_thermal_production_mmbtu"] ≈ 0.4 * 8760 rtol=1e-4
                finalize(backend(m))
                empty!(m)
                GC.gc()
            end

            @testset "ASHP Forced Dispatch to Load or Max Capacity" begin
                d = JSON.parsefile("./scenarios/ashp.json")
                d["SpaceHeatingLoad"]["annual_mmbtu"] = 0.5 * 8760
                d["DomesticHotWaterLoad"] = Dict{String,Any}("annual_mmbtu" => 0.5 * 8760, "doe_reference_name" => "FlatLoad")
                d["CoolingLoad"] = Dict{String,Any}("thermal_loads_ton" => ones(8760)*0.1)
                d["ExistingChiller"] = Dict{String,Any}("retire_in_optimal" => false, "cop" => 100)
                d["ExistingBoiler"]["retire_in_optimal"] = false
                d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = 0.001
                d["ASHPSpaceHeater"]["can_serve_cooling"] = true
                d["ASHPSpaceHeater"]["force_dispatch"] = true
                d["ASHPSpaceHeater"]["min_ton"] = 1000
                d["ASHPSpaceHeater"]["max_ton"] = 1000      
                
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)
            
                #Case 1: ASHP systems run to meet full site load as they are oversized and dispatch is forced
                @test results["ASHPSpaceHeater"]["annual_electric_consumption_kwh"] ≈ sum(0.4 * REopt.KWH_PER_MMBTU / p.heating_cop["ASHPSpaceHeater"][ts] + 0.1 * REopt.KWH_THERMAL_PER_TONHOUR / p.cooling_cop["ASHPSpaceHeater"][ts] for ts in p.time_steps) rtol=1e-4
                # This confirms that ASHPSpaceHeater is forced to dispatch to cooling load because the default ExistingChiller.cop is greater than the defaul ASHP cooling COP
                @test results["ASHPSpaceHeater"]["annual_thermal_production_tonhour"] ≈ 0.1 * 8760 rtol=1e-4
                @test results["ASHPSpaceHeater"]["annual_thermal_production_mmbtu"] ≈ 0.4 * 8760 rtol=1e-4            
                finalize(backend(m))
                empty!(m)
                GC.gc()
                
                d["ASHPSpaceHeater"]["can_serve_cooling"] = false
                d["ASHPSpaceHeater"]["min_ton"] = 10
                d["ASHPSpaceHeater"]["max_ton"] = 10
                d["ASHPSpaceHeater"]["min_allowable_ton"] = 0
                d["ASHPWaterHeater"] = Dict{String,Any}("force_dispatch" => true, "min_allowable_ton" => 0.0, "min_ton" => 10, "max_ton" => 10)
            
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)
            
                #Case 2: ASHP systems run to meet at capacity as they are undersized and dispatch is forced, Space Heater is heat only
                @test results["ASHPSpaceHeater"]["annual_electric_consumption_kwh"] ≈ sum(10 * REopt.KWH_THERMAL_PER_TONHOUR * p.heating_cf["ASHPSpaceHeater"][ts] / p.heating_cop["ASHPSpaceHeater"][ts] for ts in p.time_steps) rtol=1e-4
                @test results["ASHPSpaceHeater"]["annual_thermal_production_mmbtu"] ≈ sum(10 * (REopt.KWH_THERMAL_PER_TONHOUR/REopt.KWH_PER_MMBTU) * p.heating_cf["ASHPSpaceHeater"][ts] for ts in p.time_steps) rtol=1e-4
                @test results["ASHPWaterHeater"]["annual_electric_consumption_kwh"] ≈ sum(10 * REopt.KWH_THERMAL_PER_TONHOUR * p.heating_cf["ASHPWaterHeater"][ts] / p.heating_cop["ASHPWaterHeater"][ts] for ts in p.time_steps) rtol=1e-4
                @test results["ASHPWaterHeater"]["annual_thermal_production_mmbtu"] ≈ sum(10 * (REopt.KWH_THERMAL_PER_TONHOUR/REopt.KWH_PER_MMBTU) * p.heating_cf["ASHPWaterHeater"][ts] for ts in p.time_steps) rtol=1e-4
                finalize(backend(m))
                empty!(m)
                GC.gc()
            
                d["ASHPSpaceHeater"]["force_dispatch"] = false
                d["ASHPWaterHeater"]["force_dispatch"] = false
            
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.05))
                results = run_reopt(m, p)
            
                #Case 3: ASHP present but does not run because dispatch is not forced and boiler fuel is cheap
                @test results["ASHPSpaceHeater"]["annual_electric_consumption_kwh"] ≈ 0.0 atol=1e-4
                @test results["ASHPSpaceHeater"]["annual_thermal_production_mmbtu"] ≈ 0.0 atol=1e-4
                @test results["ASHPWaterHeater"]["annual_electric_consumption_kwh"] ≈ 0.0 atol=1e-4
                @test results["ASHPWaterHeater"]["annual_thermal_production_mmbtu"] ≈ 0.0 atol=1e-4
                finalize(backend(m))
                empty!(m)
                GC.gc()
            
                #Case 4: confirm that when force_dispatch == true, there is no ASHP system purchased when system is expensive compared to cost of fuel
                d["ASHPSpaceHeater"]["force_dispatch"] = true
                d["ASHPWaterHeater"]["force_dispatch"] = true
                d["ASHPSpaceHeater"]["min_ton"] = 0.0
                d["ASHPWaterHeater"]["min_ton"] = 0.0
                s = Scenario(d)
                p = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, p)
                @test results["ASHPSpaceHeater"]["size_ton"] ≈ 0.0 atol=1e-4
                @test results["ASHPWaterHeater"]["size_ton"] ≈ 0.0 atol=1e-4
                finalize(backend(m))
                empty!(m)
                GC.gc()
            end
        end

        @testset "Process Heat Load" begin
            d = JSON.parsefile("./scenarios/process_heat.json")
        
            # Test set 1: Boiler has free fuel, no emissions, and serves all heating load.
            d["Boiler"]["fuel_cost_per_mmbtu"] = 0.0
            s = Scenario(d)
            p = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, p)

            @test results["Boiler"]["size_mmbtu_per_hour"] ≈ 24.0 atol=0.1
            @test results["Boiler"]["annual_thermal_production_mmbtu"] ≈ 210240.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test results["ExistingBoiler"]["annual_thermal_production_mmbtu"] ≈ 0.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ 0.0 atol=0.1
            finalize(backend(m))
            empty!(m)
            GC.gc()
        
            #Test set 2: Boiler only serves process heat
            d["Boiler"]["can_serve_dhw"] = false
            d["Boiler"]["can_serve_space_heating"] = false
            d["Boiler"]["can_serve_process_heat"] = true
            s = Scenario(d)
            p = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, p)
            @test results["Boiler"]["size_mmbtu_per_hour"] ≈ 8.0 atol=0.1
            @test results["Boiler"]["annual_thermal_production_mmbtu"] ≈ 70080.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test results["ExistingBoiler"]["annual_thermal_production_mmbtu"] ≈ 140160.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            finalize(backend(m))
            empty!(m)
            GC.gc()
        
            #Test set 3: Boiler cannot serve process heat but serves DHW, space heating
            d["Boiler"]["can_serve_dhw"] = true
            d["Boiler"]["can_serve_space_heating"] = true
            d["Boiler"]["can_serve_process_heat"] = false
            s = Scenario(d)
            p = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, p)
            @test results["Boiler"]["size_mmbtu_per_hour"] ≈ 16.0 atol=0.1
            @test results["Boiler"]["annual_thermal_production_mmbtu"] ≈ 140160.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test results["ExistingBoiler"]["annual_thermal_production_mmbtu"] ≈ 70080.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            finalize(backend(m))
            empty!(m)
            GC.gc()
        
            #Test set 4: Fuel expensive, but ExistingBoiler is retired
            d["Boiler"]["can_serve_dhw"] = true
            d["Boiler"]["can_serve_space_heating"] = true
            d["Boiler"]["can_serve_process_heat"] = true
            d["Boiler"]["fuel_cost_per_mmbtu"] = 30.0
            d["ExistingBoiler"]["retire_in_optimal"] = true
            s = Scenario(d)
            p = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, p)
            @test results["Boiler"]["size_mmbtu_per_hour"] ≈ 24.0 atol=0.1
            @test results["Boiler"]["annual_thermal_production_mmbtu"] ≈ 210240.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test results["ExistingBoiler"]["annual_thermal_production_mmbtu"] ≈ 0.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            finalize(backend(m))
            empty!(m)
            GC.gc()
        
            #Test set 5: Fuel expensive, ExistingBoiler not retired
            d["ExistingBoiler"]["retire_in_optimal"] = false
            s = Scenario(d)
            p = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, p)
            @test results["Boiler"]["size_mmbtu_per_hour"] ≈ 0.0 atol=0.1
            @test results["Boiler"]["annual_thermal_production_mmbtu"] ≈ 0.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test sum(results["Boiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 0.0 atol=0.1
            @test results["ExistingBoiler"]["annual_thermal_production_mmbtu"] ≈ 210240.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_dhw_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_space_heating_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            @test sum(results["ExistingBoiler"]["thermal_to_process_heat_load_series_mmbtu_per_hour"]) ≈ 70080.0 atol=0.1
            finalize(backend(m))
            empty!(m)
            GC.gc()
    
            # Test 6: reduce emissions by half, get half the new boiler size
            d["Site"]["CO2_emissions_reduction_min_fraction"] = 0.50
            s = Scenario(d)
            p = REoptInputs(s)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt([m1,m2], p)
            @test results["Boiler"]["size_mmbtu_per_hour"] ≈ 12.0 atol=0.1
            @test results["Boiler"]["annual_thermal_production_mmbtu"] ≈ 105120.0 atol=0.1
            @test results["ExistingBoiler"]["annual_thermal_production_mmbtu"] ≈ 105120.0 atol=0.1
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()             
        end

        @testset "CST + High-temperature TES" begin
            # TODO add a test that pairs with a steam turbine for a CSP system
            d = JSON.parsefile("./scenarios/cst.json")
            s = Scenario(d)
            p = REoptInputs(s)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
            results = run_reopt(m1, p)
            @test results["CST"]["annual_thermal_production_mmbtu"] ≈ 26175.2 rtol=1.0e-4
            @test sum(results["CST"]["thermal_curtailed_series_mmbtu_per_hour"]) ≈ 19548.3 rtol=1.0e-4
            @test results["CST"]["size_kw"] ≈ 10000.0 atol=0.001
            @test results["CST"]["size_mmbtu_per_hour"] ≈ 10000.0 / REopt.KWH_PER_MMBTU atol=1.0e-3
            @test results["ExistingBoiler"]["annual_thermal_production_mmbtu"] ≈ 386.9 rtol=1.0e-4
            @test results["HighTempThermalStorage"]["size_kwh"] ≈ 10000.0 atol=0.1
            @test results["HotThermalStorage"]["size_gal"] ≈ 1000.0 atol=0.1

            # Test that CST and HighTempThermalStorage capital costs are included in initial_capital_costs
            expected_cst_cost = results["CST"]["size_kw"] * 2200.0  # CST installed_cost_per_kw from defaults
            expected_httes_cost = results["HighTempThermalStorage"]["size_kwh"] * 86.0  # HighTempThermalStorage installed_cost_per_kwh from scenario
            @test results["Financial"]["initial_capital_costs"] ≈ expected_cst_cost + expected_httes_cost rtol=1.0e-3
            
            finalize(backend(m1))
            empty!(m1)
            GC.gc()
        end

        @testset "Custom REopt logger" begin
            
            # Throw a handled error
            d = JSON.parsefile("./scenarios/logger.json")

            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            r = run_reopt([m1,m2], d)
            @test r["status"] == "error"
            @test "Messages" ∈ keys(r)
            @test "errors" ∈ keys(r["Messages"])
            @test "warnings" ∈ keys(r["Messages"])
            @test length(r["Messages"]["errors"]) > 0
            @test length(r["Messages"]["warnings"]) > 0
            @test r["Messages"]["has_stacktrace"] == false
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()

            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            r = run_reopt(m, d)
            @test r["status"] == "error"
            @test "Messages" ∈ keys(r)
            @test "errors" ∈ keys(r["Messages"])
            @test "warnings" ∈ keys(r["Messages"])
            @test length(r["Messages"]["errors"]) > 0
            @test length(r["Messages"]["warnings"]) > 0

            # Type is dict when errors, otherwise type REoptInputs
            @test isa(REoptInputs(d), Dict)
            finalize(backend(m))
            empty!(m)
            GC.gc()            

            # Using filepath
            n1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            n2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            r = run_reopt([n1,n2], "./scenarios/logger.json")
            @test r["status"] == "error"
            @test "Messages" ∈ keys(r)
            @test "errors" ∈ keys(r["Messages"])
            @test "warnings" ∈ keys(r["Messages"])
            @test length(r["Messages"]["errors"]) > 0
            @test length(r["Messages"]["warnings"]) > 0
            finalize(backend(n1))
            empty!(n1)
            finalize(backend(n2))
            empty!(n2)
            GC.gc()

            n = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            r = run_reopt(n, "./scenarios/logger.json")
            @test r["status"] == "error"
            @test "Messages" ∈ keys(r)
            @test "errors" ∈ keys(r["Messages"])
            @test "warnings" ∈ keys(r["Messages"])
            @test length(r["Messages"]["errors"]) > 0
            @test length(r["Messages"]["warnings"]) > 0
            finalize(backend(n))
            empty!(n)
            GC.gc()

            # Throw an unhandled error: Bad URDB rate -> stack gets returned for debugging
            d["ElectricLoad"]["doe_reference_name"] = "MidriseApartment"
            d["ElectricTariff"]["urdb_label"] = "62c70a6c40a0c425535d387x"

            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            r = run_reopt([m1,m2], d)
            @test r["status"] == "error"
            @test "Messages" ∈ keys(r)
            @test "errors" ∈ keys(r["Messages"])
            @test "warnings" ∈ keys(r["Messages"])
            @test length(r["Messages"]["errors"]) > 0
            @test length(r["Messages"]["warnings"]) > 0
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()

            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            r = run_reopt(m, d)
            @test r["status"] == "error"
            @test "Messages" ∈ keys(r)
            @test "errors" ∈ keys(r["Messages"])
            @test "warnings" ∈ keys(r["Messages"])
            @test length(r["Messages"]["errors"]) > 0
            @test length(r["Messages"]["warnings"]) > 0

            # Type is dict when errors, otherwise type REoptInputs
            @test isa(REoptInputs(d), Dict)
            finalize(backend(m))
            empty!(m)
            GC.gc()

            # Using filepath
            n1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            n2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            r = run_reopt([n1,n2], "./scenarios/logger.json")
            @test r["status"] == "error"
            @test "Messages" ∈ keys(r)
            @test "errors" ∈ keys(r["Messages"])
            @test "warnings" ∈ keys(r["Messages"])
            @test length(r["Messages"]["errors"]) > 0
            @test length(r["Messages"]["warnings"]) > 0
            finalize(backend(n1))
            empty!(n1)
            finalize(backend(n2))
            empty!(n2)
            GC.gc()

            n = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.1))
            r = run_reopt(n, "./scenarios/logger.json")
            @test r["status"] == "error"
            @test "Messages" ∈ keys(r)
            @test "errors" ∈ keys(r["Messages"])
            @test "warnings" ∈ keys(r["Messages"])
            @test length(r["Messages"]["errors"]) > 0
            @test length(r["Messages"]["warnings"]) > 0
            finalize(backend(n))
            empty!(n)
            GC.gc()
        end

        @testset "Normalize and scale load profile input to annual and monthly energy" begin
            # Normalize and scale input load profile based on annual or monthly energy uses
            # The purpose of this is to be able to build a load profile shape, and then scale to the typical monthly energy data that users have

            input_data = JSON.parsefile("./scenarios/norm_scale_load.json")

            # Start with normalizing and scaling electric load only
            input_data["ElectricLoad"]["loads_kw"] = fill(10.0, 8760)
            input_data["ElectricLoad"]["loads_kw"][5:28] .= 20.0
            input_data["ElectricLoad"]["year"] = 2020
            input_data["ElectricLoad"]["monthly_totals_kwh"] = fill(87600.0/12, 12)
            input_data["ElectricLoad"]["monthly_totals_kwh"][2] *= 2
            input_data["ElectricLoad"]["normalize_and_scale_load_profile_input"] = true

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            # Check that monthly energy input is preserved when normalizing and scaling the hourly profile
            @test abs(sum(s.electric_load.loads_kw) - sum(input_data["ElectricLoad"]["monthly_totals_kwh"])) < 1.0

            # Check consistency of get_monthly_energy() function which is used in simulated_load()
            monthly_totals_kwh = REopt.get_monthly_energy(s.electric_load.loads_kw; year=input_data["ElectricLoad"]["year"])

            # Check that each month matches
            @test sum(monthly_totals_kwh .- input_data["ElectricLoad"]["monthly_totals_kwh"]) < 1.0

            # Check that the load ratio within a month is proportional to the loads_kw ratio
            @test abs(s.electric_load.loads_kw[6] / s.electric_load.loads_kw[4] - input_data["ElectricLoad"]["loads_kw"][6] / input_data["ElectricLoad"]["loads_kw"][4]) < 0.001

            # Check consistency with simulated_load function
            d_sim_load = Dict([
                ("load_type", "electric"),
                ("normalize_and_scale_load_profile_input", true),
                ("load_profile", input_data["ElectricLoad"]["loads_kw"]),
                ("monthly_totals_kwh", input_data["ElectricLoad"]["monthly_totals_kwh"])
                ])

            sim_load_response = simulated_load(d_sim_load)

            @test abs(sim_load_response["annual_kwh"] - sum(input_data["ElectricLoad"]["monthly_totals_kwh"])) < 1.0
            @test sum(s.electric_load.loads_kw .- sim_load_response["loads_kw"]) < 10.0

            # Check space heating load normalization and scaling
            input_data = JSON.parsefile("./scenarios/norm_scale_load.json")
            input_data["ElectricLoad"]["doe_reference_name"] = "LargeOffice"
            # Focus on SpaceHeating for heating norm and scale
            input_data["SpaceHeatingLoad"] = Dict()
            input_data["SpaceHeatingLoad"]["fuel_loads_mmbtu_per_hour"] = fill(10.0, 8760)
            input_data["SpaceHeatingLoad"]["fuel_loads_mmbtu_per_hour"][5:28] .= 20.0
            input_data["SpaceHeatingLoad"]["year"] = 2017

            input_data["SpaceHeatingLoad"]["monthly_mmbtu"] = fill(87600.0/12, 12)
            input_data["SpaceHeatingLoad"]["monthly_mmbtu"][2] *= 2
            input_data["SpaceHeatingLoad"]["normalize_and_scale_load_profile_input"] = true
            input_data["SpaceHeatingLoad"]["addressable_load_fraction"] = 0.9
            address_frac = input_data["SpaceHeatingLoad"]["addressable_load_fraction"]

            input_data["ProcessHeatLoad"] = Dict()
            input_data["ProcessHeatLoad"]["fuel_loads_mmbtu_per_hour"] = fill(1.0, 8760)
            input_data["ProcessHeatLoad"]["fuel_loads_mmbtu_per_hour"][6] = 21.0
            input_data["ProcessHeatLoad"]["year"] = 2017
            input_data["ProcessHeatLoad"]["annual_mmbtu"] = 87800
            input_data["ProcessHeatLoad"]["normalize_and_scale_load_profile_input"] = true

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            # Check that monthly energy input is preserved when normalizing and scaling the hourly profile
            @test abs(sum(s.space_heating_load.loads_kw / s.existing_boiler.efficiency / REopt.KWH_PER_MMBTU) - sum(input_data["SpaceHeatingLoad"]["monthly_mmbtu"]) * address_frac) < 1.0
            # Check consistency of get_monthly_energy() function which is used in simulated_load()
            monthly_kwht = REopt.get_monthly_energy(s.space_heating_load.loads_kw; year=input_data["SpaceHeatingLoad"]["year"]) 
            monthly_mmbtu = monthly_kwht/ s.existing_boiler.efficiency / REopt.KWH_PER_MMBTU
            @test sum(monthly_mmbtu .- input_data["SpaceHeatingLoad"]["monthly_mmbtu"] * address_frac) < 1.0

            # Check that annual energy input is preserved when normalizing and scaling the hourly profile
            @test abs(sum(s.process_heat_load.loads_kw / s.existing_boiler.efficiency / REopt.KWH_PER_MMBTU) - input_data["ProcessHeatLoad"]["annual_mmbtu"]) < 1.0

            # Check that the load ratio within a month is proportional to the loads_kw ratio
            @test abs(s.space_heating_load.loads_kw[6] / s.space_heating_load.loads_kw[4] - input_data["SpaceHeatingLoad"]["fuel_loads_mmbtu_per_hour"][6] / input_data["SpaceHeatingLoad"]["fuel_loads_mmbtu_per_hour"][4]) < 0.001
            @test abs(s.process_heat_load.loads_kw[6] / s.process_heat_load.loads_kw[4] - input_data["ProcessHeatLoad"]["fuel_loads_mmbtu_per_hour"][6] / input_data["ProcessHeatLoad"]["fuel_loads_mmbtu_per_hour"][4]) < 0.001

            # Check space heating consistency with simulated_load function
            d_sim_load = Dict([
                ("load_type", "space_heating"),
                ("normalize_and_scale_load_profile_input", true),
                ("load_profile", input_data["SpaceHeatingLoad"]["fuel_loads_mmbtu_per_hour"]),
                ("monthly_mmbtu", input_data["SpaceHeatingLoad"]["monthly_mmbtu"]),
                ("addressable_load_fraction", address_frac)
                ])

            sim_load_response = simulated_load(d_sim_load)

            @test abs(sim_load_response["annual_mmbtu"] - sum(input_data["SpaceHeatingLoad"]["monthly_mmbtu"]) * address_frac) < 1.0
            @test sum(s.space_heating_load.loads_kw / s.existing_boiler.efficiency / REopt.KWH_PER_MMBTU .- sim_load_response["loads_mmbtu_per_hour"]) < 10.0              

            # Check process heat consistency with simulated_load function
            d_sim_load = Dict([
                ("load_type", "process_heat"),
                ("normalize_and_scale_load_profile_input", true),
                ("load_profile", input_data["ProcessHeatLoad"]["fuel_loads_mmbtu_per_hour"]),
                ("annual_mmbtu", input_data["ProcessHeatLoad"]["annual_mmbtu"])
                ])

            sim_load_response = simulated_load(d_sim_load)

            @test abs(sim_load_response["annual_mmbtu"] - input_data["ProcessHeatLoad"]["annual_mmbtu"]) < 1.0
            @test sum(s.process_heat_load.loads_kw / s.existing_boiler.efficiency / REopt.KWH_PER_MMBTU .- sim_load_response["loads_mmbtu_per_hour"]) < 10.0 
        
        end      
        
        @testset "Storage Duration" begin
            ## Battery storage
            d = JSON.parsefile("scenarios/pv_storage.json")
            d["ElectricStorage"]["min_duration_hours"] = 8
            d["ElectricStorage"]["max_duration_hours"] = 8
            s = Scenario(d)
            inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            r = run_reopt(m, inputs)
            # Test battery size_kwh = size_hw * duration
            @test r["ElectricStorage"]["size_kw"]*8 - r["ElectricStorage"]["size_kwh"] ≈ 0.0 atol = 0.1
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

        @testset "Test leap year for URDB demand and energy charges" begin
            """
            We tell users to truncate/cut-off the last day of the year of their load profile for leap years, to 
                preserve the weekday/weekend and month alignment of the load with the rate structure

            The input .json file has a custom rate tariff to test leap year behavior for timesteps beyond end of February
                Higher energy price weekdays between 7AM (ts 8, 32, etc) through 7pm (ts 20, 44, etc)
                Flat/Facility (non-TOU) demand charges of 18.05/kW all month
                TOU demand charges of 10/kW between 2pm-7pm on weekdays
            """
            input_data = JSON.parsefile("scenarios/leap_year.json")
            # Set the load profile to zeros except for certain timesteps to test alignment of load with rate structure
            peak_load = 10.0
            for year in [2023, 2024]
                input_data["ElectricLoad"]["year"] = year
                
                # Test for TOU energy and demand charges alignment with load profile for leap years
                input_data["ElectricLoad"]["loads_kw"] = zeros(8760)
                # Sunday (off-peak) March 3, 2023, so expect off-peak energy and demand charges for 2023
                # Monday (on-peak) March 4, 2024, but Sunday (weekend, off-peak) if February handled as 28 days for leap year (as it was in REopt prior to 2025)
                input_data["ElectricLoad"]["loads_kw"][31*24+29*24+3*24+16] = peak_load
                s = Scenario(input_data)
                inputs = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.05, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, inputs)

                # TOU Energy charges
                weekend_rate = input_data["ElectricTariff"]["urdb_response"]["energyratestructure"][2][1]["rate"]  # Not used in this test
                weekday_rate = input_data["ElectricTariff"]["urdb_response"]["energyratestructure"][3][1]["rate"]

                # TOU Demand charges
                flat_rate = input_data["ElectricTariff"]["urdb_response"]["flatdemandstructure"][3][1]["rate"]
                tou_rate = input_data["ElectricTariff"]["urdb_response"]["demandratestructure"][3][1]["rate"]

                energy_charge_expected = 0.0
                demand_charge_expected = 0.0
                if year == 2023
                    energy_charge_expected = weekend_rate * peak_load
                    demand_charge_expected = flat_rate * peak_load
                elseif year == 2024  # Leap year
                    energy_charge_expected = weekday_rate * peak_load
                    demand_charge_expected = (flat_rate + tou_rate) * peak_load        
                end
                @test results["ElectricTariff"]["year_one_energy_cost_before_tax"] ≈ energy_charge_expected atol=1E-6
                @test results["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ demand_charge_expected atol=1E-6
                finalize(backend(m))
                empty!(m)
                GC.gc()

                # Flat/facility (non-TOU) demand charge
                input_data["ElectricLoad"]["loads_kw"] = zeros(8760)
                # Weekday off-peak February 28th, to set February Facility demand charge
                input_data["ElectricLoad"]["loads_kw"][31*24+27*24+8] = peak_load
                # Weekday off-peak Feb 29th for leap year, March 1st for non-leap year (also if Feb is wrongly handled as 28 days for leap year)
                input_data["ElectricLoad"]["loads_kw"][31*24+28*24+8] = peak_load
                s = Scenario(input_data)
                inputs = REoptInputs(s)
                m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
                results = run_reopt(m, inputs)
                flat_rate = input_data["ElectricTariff"]["urdb_response"]["flatdemandstructure"][3][1]["rate"]
                if year == 2024  # Leap year
                    demand_charge_expected = flat_rate * peak_load
                elseif year == 2023
                    demand_charge_expected = 2 * flat_rate * peak_load
                end
                @test results["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ demand_charge_expected atol=1E-6
                finalize(backend(m))
                empty!(m)
                GC.gc()
            end
        end

        @testset "Align load profiles based on load year" begin
            """
            Common use case: ElectricLoad.loads_kw is input with specific year, but heating and/or cooling is 
                simulated with either a schedule-based FlatLoad, or b) CRB type with annual or monthly energy
            This test confirms that the simulated FlatLoad type and CRB are shifted to start on Monday for 2024
            """
        
            input_data = JSON.parsefile("./scenarios/load_year_align.json")
            year = 2024
            # ElectricLoad.loads_kw is 2024, and heating and cooling loads are shifted to align
            # Use a FlatLoad_16_5 shifted to 2024 (Monday start) with the web tool's custom load builder
            loads_kw = readdlm("./data/10 kW FlatLoad_16_5 2024.csv", ',', Float64, header=true)[1][:, 2]
            input_data["ElectricLoad"] = Dict("loads_kw" => loads_kw, "year" => year)
        
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.1, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, inputs)
        
            electric_load = results["ElectricLoad"]["load_series_kw"]
            heating_load = results["HeatingLoad"]["space_heating_boiler_fuel_load_series_mmbtu_per_hour"]
            cooling_load = results["CoolingLoad"]["load_series_ton"]
        
            count_misaligned_heating = sum((electric_load .> 0) .& (heating_load .== 0))
            count_misaligned_cooling = sum((electric_load .> 0) .& (cooling_load .== 0))
        
            @test count_misaligned_heating == 0
            @test count_misaligned_cooling == 0
        
            # Simulated load with year input (e.g. when user inputs custom electric load profile but wants to see aligned simulated heating load)
            d_sim_load = Dict([("latitude", input_data["Site"]["latitude"]),
                                ("longitude", input_data["Site"]["longitude"]),
                                ("load_type", "space_heating"),  # since annual_tonhour is not given
                                ("doe_reference_name", "FlatLoad_16_5"),
                                ("annual_mmbtu", input_data["SpaceHeatingLoad"]["annual_mmbtu"]),
                                ("year", year)
                                ])
        
            sim_load_response = simulated_load(d_sim_load)
        
            @test sim_load_response["loads_mmbtu_per_hour"] ≈ round.(heating_load, digits=3)
            finalize(backend(m))
            empty!(m)
            GC.gc()            
        
            # If a non-2017 year is input with a CRB for electric, heating, or cooling load, make sure that 
            #  the energy input is preserved while the CRB profile is shifted and adjusted to align with 
            #  the load year and re-normalized to preserve the annual energy (sum of normalized profile == 1.0)
            buildingtype = "Hospital"
            input_data["ElectricLoad"] = Dict("doe_reference_name" => buildingtype, "annual_kwh" => 10000, "year" => year)
            input_data["SpaceHeatingLoad"] = Dict("doe_reference_name" => buildingtype, "annual_mmbtu" => 10000)
            input_data["CoolingLoad"] = Dict("doe_reference_name" => buildingtype, "annual_tonhour" => 100.0)

            s = Scenario(input_data)
            inputs = REoptInputs(s)

            # Test that the energy input is preserved with the CRB profile shift
            @test sum(s.electric_load.loads_kw) ≈ input_data["ElectricLoad"]["annual_kwh"]
            @test sum(s.space_heating_load.loads_kw) / REopt.KWH_PER_MMBTU ≈ input_data["SpaceHeatingLoad"]["annual_mmbtu"]
            @test sum(s.cooling_load.loads_kw_thermal) / REopt.KWH_THERMAL_PER_TONHOUR ≈ input_data["CoolingLoad"]["annual_tonhour"]

            # The first CRB profile day, Sunday, is replaced by the first day of the load year, and that day is replicated at the end of the year too
            @test s.electric_load.loads_kw[end-24+1:end] == s.electric_load.loads_kw[1:24]
            @test s.space_heating_load.loads_kw[end-24+1:end] == s.space_heating_load.loads_kw[1:24]
            @test s.cooling_load.loads_kw_thermal[end-24+1:end] == s.cooling_load.loads_kw_thermal[1:24]
        end
        
        @testset "After-tax savings and capital cost metric for alternative payback calculation" begin
            """
            Check alignment between REopt simple_payback_years and a simple X/Y payback metric with
            after-tax savings and a capital cost metric with non-discounted incentives to get simple X/Y payback 
            The REopt simple_payback_years output metric is after-tax, with no discounting, but it uses escalated and 
            inflated cashflows and it includes out-year, non-discounted battery replacement cost which is only included 
            in the payback calulcation if the replacement happens before the payback period.
            This scenario includes export benefits and CHP standby charges which are additive to the electricity bill for total electricity costs.
            """

            input_data = JSON.parsefile("./scenarios/after_tax_payback.json")
            # First test with battery replacement within the payback period, but zero discount rate, so simple_payback_years should be equal to the X/Y payback metric
            #  which discounts the future-year battery replacement back to present value so that it can be included in the payback calculation
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            results = run_reopt([m1,m2], inputs)
            # Total operating (energy, fuel, O&M) cost savings output (available only with BAU scenario included)
            savings = results["Financial"]["year_one_total_operating_cost_savings_after_tax"]
            # Net cost with non-discounted future capital-based incentives, including present value of battery replacement costs
            capital_costs_after_non_discounted_incentives = results["Financial"]["capital_costs_after_non_discounted_incentives"]
            # Calculated payback from above-two metrics
            payback = capital_costs_after_non_discounted_incentives / savings
            @test round(results["Financial"]["simple_payback_years"], digits=2) ≈ round(payback, digits=2)
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()

            # Test that with a non-zero discount rate, as long as the battery replacement cost is zero, these payback periods should also align
            input_data["Financial"]["offtaker_discount_rate_fraction"] = 0.1
            input_data["ElectricStorage"]["replace_cost_per_kw"] = 0.0
            input_data["ElectricStorage"]["replace_cost_per_kwh"] = 0.0
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            results = run_reopt([m1,m2], inputs)
            payback = results["Financial"]["capital_costs_after_non_discounted_incentives"] / results["Financial"]["year_one_total_operating_cost_savings_after_tax"]
            @test round(results["Financial"]["simple_payback_years"], digits=2) ≈ round(payback, digits=2)
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()
        end

        @testset "Existing HVAC (Boiler and Chiller) Costs for BAU" begin
            """
            Test that the existing HVAC (ExistingBoiler and ExistingChiller) costs are calculated correctly in BAU and optimal scenarios
            """
            # GHP is not allowed to serve DHW in this scenario, so there is still expected to be "ExistingBoiler" cost in optimal case
            input_data = JSON.parsefile("./scenarios/hvac_costs.json")
            # Choose one or the other to be non-zero
            # This test will check that with GHP, we just have the ExistingBoiler cost based on the size to serve the DHW load
            input_data["ExistingBoiler"]["installed_cost_dollars"] = 0.0 #100000.0
            input_data["ExistingBoiler"]["installed_cost_per_mmbtu_per_hour"] = 100000.0
            # Choose one or the other to be non-zero
            # This test will make sure GHP is serving ALL the cooling load so that it does not incur this binary cost
            input_data["ExistingChiller"]["installed_cost_dollars"] = 50000.0
            input_data["ExistingChiller"]["installed_cost_per_ton"] = 0.0

            # Avoid calling GhpGhx.jl for speed testing, once we have a consistent ghpghx_response relative to the heating and cooling loads
            response_1 = JSON.parsefile("./scenarios/ghpghx_response_existing.json")
            input_data["GHP"]["ghpghx_responses"] = [response_1]

            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            results = run_reopt([m1,m2], inputs)

            # Heating CapEx with "per_mmbtu_per_hour" cost input
            max_thermal_mmbtu_per_hour = maximum(s.space_heating_load.loads_kw .+ s.dhw_load.loads_kw) / REopt.KWH_PER_MMBTU
            # Expected capex below assumes that both of these inputs may be included but one has to be zero (will error if not)
            expected_capex_bau = 1.25 * max_thermal_mmbtu_per_hour * input_data["ExistingBoiler"]["installed_cost_per_mmbtu_per_hour"] + input_data["ExistingBoiler"]["installed_cost_dollars"]

            # Cooling CapEx with "_dollars" cost input
            max_cooling_ton = maximum(s.cooling_load.loads_kw_thermal) / REopt.KWH_THERMAL_PER_TONHOUR
            expected_capex_bau += 1.25 * max_cooling_ton * input_data["ExistingChiller"]["installed_cost_per_ton"] + input_data["ExistingChiller"]["installed_cost_dollars"]

            # Expected optimal case ExistingBoiler + ExistingChiller cost - just the ExistingBoiler to serve DHW
            max_dhw_thermal_mmbtu_per_hour = maximum(s.dhw_load.loads_kw) / REopt.KWH_PER_MMBTU
            # Expected capex below assumes that both of these inputs may be included but one has to be zero (will error if not)
            expected_capex_opt = 1.25 * max_dhw_thermal_mmbtu_per_hour * input_data["ExistingBoiler"]["installed_cost_per_mmbtu_per_hour"] + input_data["ExistingBoiler"]["installed_cost_dollars"]
        
            @test round(results["Financial"]["lifecycle_capital_costs_bau"], digits=0) ≈ round(expected_capex_bau, digits=0)
            @test round(results["Financial"]["lifecycle_capital_costs"], digits=0) ≈ round(expected_capex_opt, digits=0)
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()            
        end

        @testset "PV size classes and cost-scaling" begin
            """
            PV size class determination, assigning defaults based on size-class and PV type, and cost-scaling within the model
            TODO roof/land space-based limit on size_class
            TODO installed_cost is input but O&M is not, that it still uses the size_class O&M cost
            """
        
            # Get active PV defaults for checking
            pv_defaults_path = joinpath(@__DIR__, "..", "data", "pv", "pv_defaults.json")
            pv_defaults_all = JSON.parsefile(pv_defaults_path)
        
            # Path to the scenario file
            pv_scenario_file_path = joinpath(@__DIR__, "scenarios", "pv_cost.json")
        
            # Test 1: the size_class is one based on max_kw input
            input_data = JSON.parsefile(pv_scenario_file_path)
            input_data["ElectricLoad"]["annual_kwh"] = 500*8760
            input_data["PV"]["max_kw"] = 7.0
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            @test s.pvs[1].size_class == 1

            # Test 2: size_class and costs are determined by the load and roof (Reopt.jl default) data is used
            input_data = JSON.parsefile(pv_scenario_file_path)
            input_data["ElectricLoad"]["annual_kwh"] = 10*8760
            # input_data["PV"]["array_type"] = 1  # This is the default - STRANGE that webtool default is ground, but REopt.jl is roof
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            # Avg load = 10 kW -> PV size == 10 / 0.2 * 0.5 = 25 kW which is in size_class 2 (11-100 kW)
            @test s.pvs[1].size_class == 2
            @test s.pvs[1].installed_cost_per_kw == pv_defaults_all["size_classes"][s.pvs[1].size_class]["roof"]["avg_installed_cost_per_kw"] 

            # Test 3: Ground-mount premium is correctly applied to the default roof cost.
            input_data = JSON.parsefile(pv_scenario_file_path)
            input_data["ElectricLoad"]["annual_kwh"] = 500*8760
            input_data["PV"]["array_type"] = 0  # ground
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            roof_cost_expected = pv_defaults_all["size_classes"][s.pvs[1].size_class]["roof"]["avg_installed_cost_per_kw"] 
            cost_factor = pv_defaults_all["size_classes"][s.pvs[1].size_class]["mount_premiums"]["ground"]["cost_premium"] 
            @test s.pvs[1].installed_cost_per_kw == round(roof_cost_expected * cost_factor, digits=0)

            # Test 4: User-provided costs fully override all default logic.
            input_data = JSON.parsefile(pv_scenario_file_path)
            input_data["PV"]["installed_cost_per_kw"] = 2500.0
            input_data["PV"]["om_cost_per_kw"] = 2500.0
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            @test s.pvs[1].installed_cost_per_kw == input_data["PV"]["installed_cost_per_kw"]
            @test s.pvs[1].om_cost_per_kw == input_data["PV"]["om_cost_per_kw"]
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.001, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.001, "output_flag" => false, "log_to_console" => false))
            results = run_reopt([m1,m2], inputs)
            @test results["PV"]["installed_cost_per_kw"] == input_data["PV"]["installed_cost_per_kw"]
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()            

            # Test 5: User-defined cost curve is correctly passed to the model.
            input_data = JSON.parsefile(pv_scenario_file_path)
            input_data["PV"]["min_kw"] = 400.0
            input_data["PV"]["max_kw"] = 400.0
            input_data["PV"]["tech_sizes_for_cost_curve"] = [100.0, 2000.0]
            input_data["PV"]["installed_cost_per_kw"] = [1710.0, 1420.0]
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.001, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.001, "output_flag" => false, "log_to_console" => false))
            results = run_reopt([m1,m2], inputs)
            @test results["Financial"]["lifecycle_capital_costs"] >= results["PV"]["size_kw"] * input_data["PV"]["installed_cost_per_kw"][2]
            @test results["Financial"]["lifecycle_capital_costs"] <= results["PV"]["size_kw"] * input_data["PV"]["installed_cost_per_kw"][1]
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()            

            # Test 6: size_class is 1 based on Site.roof_squarefeet
            kw_per_square_foot = 0.01
            acres_per_kw = 6e-3
            input_data = JSON.parsefile(pv_scenario_file_path)
            input_data["PV"]["array_type"] = 1  # roof
            input_data["PV"]["location"] = "roof"
            input_data["Site"]["roof_squarefeet"] = 9 / kw_per_square_foot
            input_data["ElectricLoad"]["annual_kwh"] = 500*8760
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            @test s.pvs[1].size_class == 1
            
            # Test 7: size_class input is preserved and only the user-input installed_cost_per_kw overwrites the default
            kw_per_square_foot = 0.01
            acres_per_kw = 6e-3
            input_data = JSON.parsefile(pv_scenario_file_path)
            input_data["PV"]["array_type"] = 0  # ground
            input_data["PV"]["location"] = "ground"
            input_data["Site"]["land_acres"] = 9 * acres_per_kw
            input_data["ElectricLoad"]["annual_kwh"] = 500*8760
            input_data["PV"]["size_class"] = 2
            input_data["PV"]["installed_cost_per_kw"] = 2500.0
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            @test s.pvs[1].size_class == 2
            @test s.pvs[1].installed_cost_per_kw == input_data["PV"]["installed_cost_per_kw"]
            ground_premium = pv_defaults_all["size_classes"][s.pvs[1].size_class]["mount_premiums"]["ground"]["om_premium"]
            @test s.pvs[1].om_cost_per_kw == round(pv_defaults_all["size_classes"][s.pvs[1].size_class]["roof"]["om_cost_per_kw"] * ground_premium, digits=0)
        
            # Test 8: Mismatched cost curve inputs throw an error.
            input_data = JSON.parsefile(pv_scenario_file_path)
            input_data["PV"]["installed_cost_per_kw"] = [1710.0, 1420.0]
            input_data["PV"]["tech_sizes_for_cost_curve"] = [100.0, 500.0, 2000.0] # Mismatched length
            @test_throws Exception s = Scenario(input_data)

            # Test 9: An invalid size_class is clamped and warns the user.
            input_data = JSON.parsefile(pv_scenario_file_path)
            input_data["PV"]["size_class"] = 99
            s = Scenario(input_data)
            @test s.pvs[1].size_class == 5 # Clamped to largest class

            input_data["PV"]["size_class"] = 0
            s = Scenario(input_data)
            @test s.pvs[1].size_class == 1 # Clamped to smallest class
            
        end

        @testset "Battery O&M Cost Fraction" begin
            """
            Test that the battery O&M cost fraction is applied correctly to the initial capital costs
            """
            input_data = JSON.parsefile("./scenarios/battery_om_cost_fraction.json")
            input_data["PV"]["max_kw"] = 0.0
            input_data["ElectricStorage"]["min_kw"] = 200.0
            input_data["ElectricStorage"]["min_kwh"] = 800.0
            s = Scenario(input_data)
            inputs = REoptInputs(s)

            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            results = run_reopt([m1,m2], inputs)

            init_capital_costs =  results["Financial"]["initial_capital_costs"]
            year_one_om = results["Financial"]["year_one_om_costs_before_tax"]
            @test isapprox(year_one_om / init_capital_costs, 0.025; atol=0.0005)
            finalize(backend(m1))
            empty!(m1)
            finalize(backend(m2))
            empty!(m2)
            GC.gc()
        end

        @testset "Peak load scaling" begin
            # With reference building
            input_data = JSON.parsefile("./scenarios/no_techs_load_scale.json")
            input_data["ElectricLoad"] = Dict()
            input_data["ElectricLoad"]["year"] = 2024
            input_data["ElectricLoad"]["doe_reference_name"] = "MediumOffice"
            input_data["ElectricLoad"]["monthly_totals_kwh"] = ones(12) .* 7.0e6/12
            monthly_peak_kw = 1700.0
            input_data["ElectricLoad"]["monthly_peaks_kw"] = ones(12) .* monthly_peak_kw
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, inputs)
            @test results["ElectricLoad"]["annual_calculated_kwh"] ≈ sum(input_data["ElectricLoad"]["monthly_totals_kwh"]) rtol=1.0e-4
            demand_charge = input_data["ElectricTariff"]["blended_annual_demand_rate"]
            @test results["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ 12.0 * monthly_peak_kw * demand_charge rtol=5.0e-4
            finalize(backend(m))
            empty!(m)
            GC.gc()

            # With custom load profile
            input_data = JSON.parsefile("./scenarios/no_techs_load_scale.json")
            input_data["ElectricLoad"] = Dict()
            input_data["ElectricLoad"]["loads_kw"] = readdlm("./data/loads_kw_largeoffice_sanfran.csv", ',')[:,1]
            input_data["ElectricLoad"]["year"] = 2023
            input_data["ElectricLoad"]["normalize_and_scale_load_profile_input"] = true
            input_data["ElectricLoad"]["monthly_totals_kwh"] = ones(12) .* 7.0e6/12
            monthly_peak_kw = 1700.0
            input_data["ElectricLoad"]["monthly_peaks_kw"] = ones(12) .* monthly_peak_kw
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, inputs)
            @test results["ElectricLoad"]["annual_calculated_kwh"] ≈ sum(input_data["ElectricLoad"]["monthly_totals_kwh"]) rtol=1.0e-4
            demand_charge = input_data["ElectricTariff"]["blended_annual_demand_rate"]
            @test results["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ 12.0 * monthly_peak_kw * demand_charge rtol=1.0e-4
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

        @testset "Peak load scaling in simulated_load" begin
            # CRB (hourly) with monthly energy and peak load scaling
            monthly_peak_kw = 1700.0
            annual_kwh = 7.0e6
            sim_input = Dict(
                "load_type" => "electric",
                "doe_reference_name" => "LargeOffice",
                "latitude" => 39.7391536,
                "longitude" => -104.9847034,
                "year" => 2017,
                "monthly_peaks_kw" => ones(12) .* monthly_peak_kw,
                "monthly_totals_kwh" => ones(12) .* annual_kwh / 12.0
            )

            # Run simulated_load() to check energy and peaks of scaled load
            sim_result = simulated_load(sim_input)
            
            # Test array consistency
            @test sim_result["monthly_totals_kwh"] ≈ sim_input["monthly_totals_kwh"] rtol=1.0e-3
            @test sim_result["monthly_peaks_kw"] ≈ sim_input["monthly_peaks_kw"] rtol=0.01

            # Custom load profile scaled to monthly energy and peak load
            hourly = readdlm("./data/loads_kw_largeoffice_sanfran.csv", ',')[:,1]
            # The data below is from an external spreadsheet and is used to validate REopt.jl implementation consistency with that
            hourly_peak_scaled = readdlm("./data/loads_kw_largeoffice_sanfran_peak_scaled.csv", ',')[:,1]
            monthly_peak_kw = 1700.0
            annual_kwh = 7.0e6
            sim_input = Dict(
                "load_type" => "electric",
                "load_profile" => hourly,
                "normalize_and_scale_load_profile_input" => true,
                "latitude" => 39.7391536,
                "longitude" => -104.9847034,
                "year" => 2023,
                "monthly_peaks_kw" => ones(12) .* monthly_peak_kw,
                "monthly_totals_kwh" => ones(12) .* annual_kwh / 12.0
            )

            # Run simulated_load() to check energy and peaks of scaled load
            sim_result = simulated_load(sim_input)
            
            # Test array consistency
            @test sim_result["loads_kw"] ≈ hourly_peak_scaled rtol=1.0e-3
            @test sim_result["monthly_totals_kwh"] ≈ sim_input["monthly_totals_kwh"] rtol=1.0e-3
            @test sim_result["monthly_peaks_kw"] ≈ sim_input["monthly_peaks_kw"] rtol=0.01

            # 15-min load profile scaled to monthly energy and peak load
            fifteen = repeat(hourly, inner=4)
            monthly_peak_kw = 1000.0
            sim_input["monthly_peaks_kw"] = ones(12) .* monthly_peak_kw
            sim_input["load_profile"] = fifteen
            sim_input["time_steps_per_hour"] = 4

            # Run simulated_load() to check energy and peaks of scaled load
            sim_result = simulated_load(sim_input)

            # Test array consistency
            @test sim_result["monthly_totals_kwh"] ≈ sim_input["monthly_totals_kwh"] rtol=1.0e-3
            @test sim_result["monthly_peaks_kw"] ≈ sim_input["monthly_peaks_kw"] rtol=0.01
            @test sum(sim_result["loads_kw"])/sim_input["time_steps_per_hour"] ≈ sum(sim_input["monthly_totals_kwh"]) rtol=1.0e-2
        end   

        @testset "Monthly ElectricTariff Results" begin
            # Test URDB rate outputs for monthly energy and demand costs
            input_data = JSON.parsefile("./scenarios/urdb_rate.json")
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, inputs)

            @test length(results["ElectricTariff"]["monthly_energy_cost_series_before_tax"]) == 12
            @test sum(results["ElectricTariff"]["monthly_energy_cost_series_before_tax"]) > 100.0
            @test length(results["ElectricTariff"]["monthly_demand_cost_series_before_tax"]) == 12
            @test sum(results["ElectricTariff"]["monthly_demand_cost_series_before_tax"]) > 100.0

            finalize(backend(m))
            empty!(m)
            GC.gc()            
            
            # Test blended rates (not URDB rate) alignment with monthly costs
            input_data = JSON.parsefile("./scenarios/urdb_rate.json")
            blended_energy_rate = 0.12  # $/kWh
            blended_demand_rate = 20.0  # $/kW/month
            
            input_data["ElectricTariff"] = Dict(
                "blended_annual_demand_rate" => blended_demand_rate,
                "blended_annual_energy_rate" => blended_energy_rate
            )
            
            s = Scenario(input_data)
            inputs = REoptInputs(s)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            results = run_reopt(m, inputs)

            # Calculate expected costs manually and compare with REopt results
            monthly_energy_kwh = results["ElectricLoad"]["monthly_calculated_kwh"]
            monthly_peaks_kw = results["ElectricLoad"]["monthly_peaks_kw"]
            
            # Expected energy costs: monthly energy * energy rate
            expected_energy_costs = monthly_energy_kwh .* blended_energy_rate
            actual_energy_costs = results["ElectricTariff"]["monthly_energy_cost_series_before_tax"]
            
            # Expected demand costs: monthly peak * demand rate
            expected_demand_costs = monthly_peaks_kw .* blended_demand_rate
            actual_demand_costs = results["ElectricTariff"]["monthly_demand_cost_series_before_tax"]

            # Test energy cost alignment (within 1% tolerance)
            for month in 1:12
                @test actual_energy_costs[month] ≈ expected_energy_costs[month] rtol=0.01
            end
            
            # Test demand cost alignment (within 1% tolerance)
            for month in 1:12
                @test actual_demand_costs[month] ≈ expected_demand_costs[month] rtol=0.01
            end
            
            energy_rate_series = results["ElectricTariff"]["energy_rate_series"]["Tier_1"]
            @test all(rate -> rate ≈ blended_energy_rate, energy_rate_series)
            
            monthly_demand_rates = results["ElectricTariff"]["facility_demand_monthly_rate_series"]["Tier_1"]
            @test all(rate -> rate ≈ blended_demand_rate, monthly_demand_rates)

            # Load metrics consistency - verify annual = sum of monthly
            annual_calc_load = results["ElectricLoad"]["annual_calculated_kwh"]
            sum_monthly_load = sum(results["ElectricLoad"]["monthly_calculated_kwh"])
            annual_peak = results["ElectricLoad"]["annual_peak_kw"]
            max_monthly_peak = maximum(results["ElectricLoad"]["monthly_peaks_kw"])
            
            @test annual_calc_load ≈ sum_monthly_load rtol=0.01
            @test annual_peak ≈ max_monthly_peak rtol=0.01
            
            # Monthly bill calculation accuracy
            # Total monthly bill should equal energy cost + demand cost for each month
            for month in 1:12
                total_monthly_cost = results["ElectricTariff"]["monthly_energy_cost_series_before_tax"][month] + 
                                    results["ElectricTariff"]["monthly_demand_cost_series_before_tax"][month]
                expected_monthly_cost = (monthly_energy_kwh[month] * blended_energy_rate) + 
                                        (monthly_peaks_kw[month] * blended_demand_rate)
                @test total_monthly_cost ≈ expected_monthly_cost rtol=0.01
            end
            
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

        @testset "ElectricTariff 15-minute Interval Tests" begin
            # Test ElectricTariff rate and cost outputs for 15-minute interval load profiles
            # This test validates that sub-hourly billing calculations work correctly with
            # time_steps_per_hour = 4 and verifies proper aggregation to monthly costs
            input_data = JSON.parsefile("./scenarios/urdb_rate.json")
            # These blended rates will overwrite the urdb_rate input from the loaded file
            blended_energy_rate = 0.10  # $/kWh
            blended_demand_rate = 15.0  # $/kW/month
            input_data["ElectricTariff"] = Dict(
                    "blended_annual_demand_rate" => blended_demand_rate,
                    "blended_annual_energy_rate" => blended_energy_rate
                )            

            # Create a base hourly load profile (with reference building)
            s_hourly = Scenario(input_data)
            base_hourly_loads = s_hourly.electric_load.loads_kw

            # Create 15-minute load profile with sine wave sub-hourly variations
            fifteen_min_loads = Float64[]

            for (hour_idx, hourly_load) in enumerate(base_hourly_loads)
                # Create 4 sub-hourly values per hour with sine wave variation
                # Base load with ±10% sine wave variation within each hour
                for quarter_hour in 1:4
                    # Intra-hour phase angle for this quarter hour (0, π/2, π, 3π/2)
                    intra_hour_phase = (quarter_hour - 1) * π / 2
                    # Sine wave variation: ±10% of hourly load
                    variation = 0.1 * sin(intra_hour_phase + 2π * hour_idx / 24)  # Daily cycle component
                    sub_hourly_load = hourly_load * (1.0 + variation)
                    push!(fifteen_min_loads, max(0.0, sub_hourly_load))  # Ensure non-negative
                end
            end

            # Update input data for 15-minute intervals
            input_data["Settings"] = Dict("time_steps_per_hour" => 4)
            input_data["ElectricLoad"] = Dict("loads_kw" => fifteen_min_loads, "year" => 2023)

            # Run REopt with 15-minute data
            s_fifteen = Scenario(input_data)
            inputs_fifteen = REoptInputs(s_fifteen)
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
            results_fifteen = run_reopt(m, inputs_fifteen)

            # Verify correct time resolution setup
            @test length(results_fifteen["ElectricLoad"]["load_series_kw"]) == length(fifteen_min_loads)
            @test results_fifteen["ElectricLoad"]["load_series_kw"] ≈ fifteen_min_loads rtol=1e-6

            # Verify energy rate series has correct length for 15-minute data
            energy_rate_series_15min = results_fifteen["ElectricTariff"]["energy_rate_series"]["Tier_1"]
            @test length(energy_rate_series_15min) == 8760 * 4  # 15-minute intervals
            @test all(rate -> rate ≈ blended_energy_rate, energy_rate_series_15min)

            # Calculate expected costs manually for 15-minute data
            monthly_energy_kwh_15min = results_fifteen["ElectricLoad"]["monthly_calculated_kwh"]
            monthly_peaks_kw_15min = results_fifteen["ElectricLoad"]["monthly_peaks_kw"]

            expected_energy_costs_15min = monthly_energy_kwh_15min .* blended_energy_rate
            actual_energy_costs_15min = results_fifteen["ElectricTariff"]["monthly_energy_cost_series_before_tax"]

            expected_demand_costs_15min = monthly_peaks_kw_15min .* blended_demand_rate
            actual_demand_costs_15min = results_fifteen["ElectricTariff"]["monthly_demand_cost_series_before_tax"]

            # Test 15-minute energy cost alignment
            for month in 1:12
                @test actual_energy_costs_15min[month] ≈ expected_energy_costs_15min[month] rtol=0.01
            end

            # Test 15-minute demand cost alignment  
            for month in 1:12
                @test actual_demand_costs_15min[month] ≈ expected_demand_costs_15min[month] rtol=0.01
            end

            # Verify annual totals consistency
            annual_energy_cost_15min = sum(actual_energy_costs_15min)
            annual_demand_cost_15min = sum(actual_demand_costs_15min)

            @test results_fifteen["ElectricTariff"]["year_one_energy_cost_before_tax"] ≈ annual_energy_cost_15min rtol=0.01
            @test results_fifteen["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ annual_demand_cost_15min rtol=0.01

            # Verify load metrics consistency for 15-minute data
            annual_calc_load_15min = results_fifteen["ElectricLoad"]["annual_calculated_kwh"]
            sum_monthly_load_15min = sum(results_fifteen["ElectricLoad"]["monthly_calculated_kwh"])
            annual_peak_15min = results_fifteen["ElectricLoad"]["annual_peak_kw"]
            max_monthly_peak_15min = maximum(results_fifteen["ElectricLoad"]["monthly_peaks_kw"])

            @test annual_calc_load_15min ≈ sum_monthly_load_15min rtol=0.01
            @test annual_peak_15min ≈ max_monthly_peak_15min rtol=0.01

            # Test monthly bill accuracy for 15-minute data
            for month in 1:12
                total_monthly_cost_15min = actual_energy_costs_15min[month] + actual_demand_costs_15min[month]
                expected_monthly_cost_15min = (monthly_energy_kwh_15min[month] * blended_energy_rate) + 
                                                (monthly_peaks_kw_15min[month] * blended_demand_rate)
                @test total_monthly_cost_15min ≈ expected_monthly_cost_15min rtol=0.01
            end
            
            # Validate that 15-minute energy totals approximately match hourly totals
            # (accounting for sine wave variations that should average out over time)
            hourly_annual_energy = sum(base_hourly_loads)  # Already in kWh for hourly data
            fifteen_min_annual_energy = annual_calc_load_15min
            @test fifteen_min_annual_energy ≈ hourly_annual_energy rtol=0.05  # 5% tolerance for sine variations
            finalize(backend(m))
            empty!(m)
            GC.gc()
        end

    end
end