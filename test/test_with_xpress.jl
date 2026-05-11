# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
using Xpress
using Random
using DelimitedFiles
Random.seed!(42)  # for test consistency, random prices used in FlexibleHVAC tests

@testset "Heating loads and addressable load fraction" begin
    # Default LargeOffice CRB with SpaceHeatingLoad and DomesticHotWaterLoad are served by ExistingBoiler
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    results = run_reopt(m, "./scenarios/thermal_load.json")

    @test round(results["ExistingBoiler"]["annual_fuel_consumption_mmbtu"], digits=0) ≈ 2904
    
    # Hourly fuel load inputs with addressable_load_fraction are served as expected
    data = JSON.parsefile("./scenarios/thermal_load.json")
    data["DomesticHotWaterLoad"]["fuel_loads_mmbtu_per_hour"] = repeat([0.5], 8760)
    data["DomesticHotWaterLoad"]["addressable_load_fraction"] = 0.6
    data["SpaceHeatingLoad"]["fuel_loads_mmbtu_per_hour"] = repeat([0.5], 8760)
    data["SpaceHeatingLoad"]["addressable_load_fraction"] = 0.8
    s = Scenario(data)
    inputs = REoptInputs(s)
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    results = run_reopt(m, inputs)
    @test round(results["ExistingBoiler"]["annual_fuel_consumption_mmbtu"], digits=0) ≈ 8760 * (0.5 * 0.6 + 0.5 * 0.8)
    
    # Monthly fuel load input with addressable_load_fraction is processed to expected thermal load
    data = JSON.parsefile("./scenarios/thermal_load.json")
    data["DomesticHotWaterLoad"]["monthly_mmbtu"] = repeat([100], 12)
    data["DomesticHotWaterLoad"]["addressable_load_fraction"] = repeat([0.6], 12)
    data["SpaceHeatingLoad"]["monthly_mmbtu"] = repeat([200], 12)
    data["SpaceHeatingLoad"]["addressable_load_fraction"] = repeat([0.8], 12)

    s = Scenario(data)
    inputs = REoptInputs(s)

    dhw_thermal_load_expected = sum(data["DomesticHotWaterLoad"]["monthly_mmbtu"] .* data["DomesticHotWaterLoad"]["addressable_load_fraction"]) .* s.existing_boiler.efficiency
    space_thermal_load_expected = sum(data["SpaceHeatingLoad"]["monthly_mmbtu"] .* data["SpaceHeatingLoad"]["addressable_load_fraction"]) .* s.existing_boiler.efficiency
    @test round(sum(s.dhw_load.loads_kw) / REopt.KWH_PER_MMBTU) ≈ sum(dhw_thermal_load_expected)
    @test round(sum(s.space_heating_load.loads_kw) / REopt.KWH_PER_MMBTU) ≈ sum(space_thermal_load_expected)
end

@testset "CHP" begin
    @testset "CHP Sizing" begin
        # Sizing CHP with non-constant efficiency, no cost curve, no unavailability_periods
        data_sizing = JSON.parsefile("./scenarios/chp_sizing.json")
        s = Scenario(data_sizing)
        inputs = REoptInputs(s)
        m = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
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
        m = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
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
        m = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
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
        m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
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
        m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
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
        m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
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

        m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
        m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
        results = run_reopt([m1,m2], inputs)
        @test abs(results["Financial"]["simple_payback_years"] - 8.12) <= 0.02
        finalize(backend(m1))
        empty!(m1)
        finalize(backend(m2))
        empty!(m2)
        GC.gc()
    end

@testset "FlexibleHVAC" begin

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

        m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        r = run_reopt([m1,m2], d)
        @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === false
        @test r["Financial"]["npv"] == 0

        # put in a time varying fuel cost, which should make purchasing the FlexibleHVAC system economical
        # with flat ElectricTariff the ExistingChiller does not benefit from FlexibleHVAC
        d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = rand(Float64, (8760))*(50-5).+5;
        m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        r = run_reopt([m1,m2], d)
        # all of the savings are from the ExistingBoiler fuel costs
        @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === true
        fuel_cost_savings = r["ExistingBoiler"]["lifecycle_fuel_cost_after_tax_bau"] - r["ExistingBoiler"]["lifecycle_fuel_cost_after_tax"]
        @test fuel_cost_savings - d["FlexibleHVAC"]["installed_cost"] ≈ r["Financial"]["npv"] atol=0.1

        # now increase the FlexibleHVAC installed_cost to the fuel costs savings + 100 and expect that the FlexibleHVAC is not purchased
        d["FlexibleHVAC"]["installed_cost"] = fuel_cost_savings + 100
        m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        r = run_reopt([m1,m2], d)
        @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === false
        @test r["Financial"]["npv"] == 0

        # add TOU ElectricTariff and expect to benefit from using ExistingChiller intelligently
        d["ElectricTariff"] = Dict("urdb_label" => "5ed6c1a15457a3367add15ae")

        m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        r = run_reopt([m1,m2], d)

        elec_cost_savings = r["ElectricTariff"]["lifecycle_demand_cost_after_tax_bau"] + 
                            r["ElectricTariff"]["lifecycle_energy_cost_after_tax_bau"] - 
                            r["ElectricTariff"]["lifecycle_demand_cost_after_tax"] - 
                            r["ElectricTariff"]["lifecycle_energy_cost_after_tax"]

        fuel_cost_savings = r["ExistingBoiler"]["lifecycle_fuel_cost_after_tax_bau"] - r["ExistingBoiler"]["lifecycle_fuel_cost_after_tax"]
        @test fuel_cost_savings + elec_cost_savings - d["FlexibleHVAC"]["installed_cost"] ≈ r["Financial"]["npv"] atol=0.1

        # now increase the FlexibleHVAC installed_cost to the fuel costs savings + elec_cost_savings 
        # + 100 and expect that the FlexibleHVAC is not purchased
        d["FlexibleHVAC"]["installed_cost"] = fuel_cost_savings + elec_cost_savings + 100
        m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        r = run_reopt([m1,m2], d)
        @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === false
        @test r["Financial"]["npv"] == 0

    end

    # TODO test with hot/cold TES
    # TODO test with PV and Storage?

    # TODO plot deadband (BAU_HVAC) temperatures vs. optimal flexed temperatures
    #=
    using Plots
    plotlyjs()
    plot(r["FlexibleHVAC"]["temperatures_degC_node_by_time_bau"][1,:], label="bau")
    plot!(r["FlexibleHVAC"]["temperatures_degC_node_by_time"][1,:], line=(:dot))
    =#

    # @testset "placeholder 5 param RC model" begin
    #     # these tests pass locally but not on Actions ???
    #     d = JSON.parsefile("./scenarios/thermal_load.json");
    #     d["FlexibleHVAC"] = JSON.parsefile("./scenarios/placeholderFlexibleHVAC.json")["FlexibleHVAC"]
    #     s = Scenario(d; flex_hvac_from_json=true);
    #     p = REoptInputs(s);

    #     m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    #     m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))

    #     r = run_reopt([m1,m2], p)
    #     @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === false
    #     @test r["Financial"]["npv"] == 0

    #     #= put in a time varying fuel cost, which should make purchasing the FlexibleHVAC system economical
    #        with flat ElectricTariff the ExistingChiller does not benefit from FlexibleHVAC =#
    #     d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = rand(Float64, (8760))*(50-25).+25;
    #     m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    #     m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    #     r = run_reopt([m1,m2], REoptInputs(Scenario(d; flex_hvac_from_json=true)))
    #     # all of the savings are from the ExistingBoiler fuel costs
    #     @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === true
    #     fuel_cost_savings = r["ExistingBoiler"]["lifecycle_fuel_cost_bau"] - r["ExistingBoiler"]["lifecycle_fuel_cost"]
    #     @test fuel_cost_savings - d["FlexibleHVAC"]["installed_cost"] ≈ r["Financial"]["npv"] atol=0.1
       
    #     # now increase the FlexibleHVAC installed_cost to the fuel costs savings + 100 and expect that the FlexibleHVAC is not purchased
    #     d["FlexibleHVAC"]["installed_cost"] = fuel_cost_savings + 100
    #     m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    #     m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    #     r = run_reopt([m1,m2], REoptInputs(Scenario(d; flex_hvac_from_json=true)))
    #     @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === false
    #     @test r["Financial"]["npv"] == 0

    #     # add TOU ElectricTariff and expect to benefit from using ExistingChiller intelligently
    #     d["ElectricTariff"] = Dict("tou_energy_rates_per_kwh" => rand(Float64, (8760))*(0.80-0.45).+0.45)
    #     d["FlexibleHVAC"]["temperature_upper_bound_degC"] = 18.0  # lower the upper bound to give Chiller more cost savings opportunity
    #     d["FlexibleHVAC"]["installed_cost"] = 300
    #     m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    #     m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    #     r = run_reopt([m1,m2], REoptInputs(Scenario(d; flex_hvac_from_json=true)))

    #     elec_cost_savings = r["ElectricTariff"]["lifecycle_demand_cost_bau"] + 
    #                         r["ElectricTariff"]["lifecycle_energy_cost_bau"] - 
    #                         r["ElectricTariff"]["lifecycle_demand_cost"] - 
    #                         r["ElectricTariff"]["lifecycle_energy_cost"]

    #     fuel_cost_savings = r["ExistingBoiler"]["lifecycle_fuel_cost_bau"] - r["ExistingBoiler"]["lifecycle_fuel_cost"]
    #     @test fuel_cost_savings + elec_cost_savings - d["FlexibleHVAC"]["installed_cost"] ≈ r["Financial"]["npv"] atol=0.1

    #     # now increase the FlexibleHVAC installed_cost to the fuel costs savings + elec_cost_savings 
    #     # + 100 and expect that the FlexibleHVAC is not purchased
    #     d["FlexibleHVAC"]["installed_cost"] = fuel_cost_savings + elec_cost_savings + 100
    #     m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    #     m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    #     r = run_reopt([m1,m2], REoptInputs(Scenario(d; flex_hvac_from_json=true)))
    #     @test Meta.parse(r["FlexibleHVAC"]["purchased"]) === false
    #     @test r["Financial"]["npv"] == 0
    # end
end

#=
add a time-of-export rate that is greater than retail rate for the month of January,
check to make sure that PV does NOT export unless the site load is met first for the month of January.
=#
@testset "Do not allow_simultaneous_export_import" begin
    model = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
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

@testset "Solar and ElectricStorage w/BAU and degradation" begin
    m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
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

    # compare avg soc with and without degradation, 
    # using default augmentation battery maintenance strategy
    avg_soc_no_degr = sum(results["ElectricStorage"]["soc_series_fraction"]) / 8760
    d["ElectricStorage"]["model_degradation"] = true
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    r_degr = run_reopt(m, d)
    avg_soc_degr = sum(r_degr["ElectricStorage"]["soc_series_fraction"]) / 8760
    @test avg_soc_no_degr > avg_soc_degr

    # test the replacement strategy
    d["ElectricStorage"]["degradation"] = Dict("maintenance_strategy" => "replacement")
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    set_optimizer_attribute(m, "MIPRELSTOP", 0.01)
    r = run_reopt(m, d)
    #optimal SOH at end of horizon is 80\% to prevent any replacement
    @test sum(value.(m[:bmth_BkWh])) ≈ 0 atol=0.1
    # @test r["ElectricStorage"]["maintenance_cost"] ≈ 2972.66 atol=0.01 
    # the maintenance_cost comes out to 3004.39 on Actions, so we test the LCC since it should match
    @test r["Financial"]["lcc"] ≈ 1.240096e7  rtol=0.01
    @test last(value.(m[:SOH])) ≈ 66.633  rtol=0.01
    @test r["ElectricStorage"]["size_kwh"] ≈ 83.29  rtol=0.01

    # test minimum_avg_soc_fraction
    d["ElectricStorage"]["minimum_avg_soc_fraction"] = 0.72
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    set_optimizer_attribute(m, "MIPRELSTOP", 0.01)
    r = run_reopt(m, d)
    @test round(sum(r["ElectricStorage"]["soc_series_fraction"]), digits=2) / 8760 >= 0.7199
end

@testset "Outage with Generator, outage simulator, BAU critical load outputs" begin
    m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    p = REoptInputs("./scenarios/generator.json")
    results = run_reopt([m1,m2], p)
    @test results["Generator"]["size_kw"] ≈ 9.55 atol=0.01
    @test (sum(results["Generator"]["electric_to_load_series_kw"][i] for i in 1:9) + 
           sum(results["Generator"]["electric_to_load_series_kw"][i] for i in 13:8760)) == 0
    @test results["ElectricLoad"]["bau_critical_load_met"] == false
    @test results["ElectricLoad"]["bau_critical_load_met_time_steps"] == 0
    
    simresults = simulate_outages(results, p)
    @test simresults["resilience_hours_max"] == 11
end

@testset "Minimize Unserved Load" begin
        
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
    input_data = JSON.parsefile("./scenarios/outage.json")
    input_data["Settings"] = Dict("solver_name" => "Xpress")
    results = run_reopt(m, input_data)

    @test results["Outages"]["expected_outage_cost"] ≈ 0
    @test sum(results["Outages"]["unserved_load_per_outage_kwh"]) ≈ 0
    @test value(m[:binMGTechUsed]["Generator"]) ≈ 1
    @test value(m[:binMGTechUsed]["CHP"]) ≈ 1
    @test value(m[:binMGTechUsed]["PV"]) ≈ 1
    @test value(m[:binMGStorageUsed]) ≈ 1
    @test results["Financial"]["lcc"] ≈ 6.83633907986e7 atol=5e4

    #=
    Scenario with $0.001/kWh value_of_lost_load_per_kwh, 12x169 hour outages, 1kW load/hour, and min_resil_time_steps = 168
    - should meet 168 kWh in each outage such that the total unserved load is 12 kWh
    =#
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    input_data = JSON.parsefile("./scenarios/nogridcost_minresilhours.json")
    input_data["Settings"] = Dict("solver_name" => "Xpress")
    results = run_reopt(m, input_data)
    @test sum(results["Outages"]["unserved_load_per_outage_kwh"]) ≈ 12
    
    # testing dvUnserved load, which would output 100 kWh for this scenario before output fix
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    input_data = JSON.parsefile("./scenarios/nogridcost_multiscenario.json")
    input_data["Settings"] = Dict("solver_name" => "Xpress")
    results = run_reopt(m, input_data)    
    @test sum(results["Outages"]["unserved_load_per_outage_kwh"]) ≈ 60
    @test results["Outages"]["expected_outage_cost"] ≈ 485.43270 atol=1.0e-5  #avg duration (3h) * load per time step (10) * present worth factor (16.18109)
    @test results["Outages"]["max_outage_cost_per_outage_duration"][1] ≈ 161.8109 atol=1.0e-5

    # Scenario with generator, PV, electric storage
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    input_data = JSON.parsefile("./scenarios/outages_gen_pv_stor.json")
    input_data["Settings"] = Dict("solver_name" => "Xpress")
    results = run_reopt(m, input_data)
    @test results["Outages"]["expected_outage_cost"] ≈ 3.54476923e6 atol=10
    @test results["Financial"]["lcc"] ≈ 8.6413594727e7 rtol=0.001

    # Scenario with generator, PV, wind, electric storage
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    input_data = JSON.parsefile("./scenarios/outages_gen_pv_wind_stor.json")
    input_data["Settings"] = Dict("solver_name" => "Xpress")
    results = run_reopt(m, input_data)
    @test value(m[:binMGTechUsed]["Generator"]) ≈ 1
    @test value(m[:binMGTechUsed]["PV"]) ≈ 1
    @test value(m[:binMGTechUsed]["Wind"]) ≈ 1
    @test results["Outages"]["expected_outage_cost"] ≈ 446899.75 atol=1.0
    @test results["Financial"]["lcc"] ≈ 6.71661825335e7 rtol=0.001
end

@testset "Outages with Wind and supply-to-load no greater than critical load" begin
    input_data = JSON.parsefile("./scenarios/wind_outages.json")
    input_data["Settings"] = Dict("solver_name" => "Xpress")
    s = Scenario(input_data)
    inputs = REoptInputs(s)
    m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
    m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
    results = run_reopt([m1,m2], inputs)

    # Check that supply-to-load is equal to critical load during outages, including wind
    supply_to_load = results["Outages"]["storage_discharge_series_kw"] .+ results["Outages"]["wind_to_load_series_kw"]
    supply_to_load = [supply_to_load[:,:,i][1] for i in eachindex(supply_to_load)]
    critical_load = results["Outages"]["critical_loads_per_outage_series_kw"][1,1,:]
    check = .≈(supply_to_load, critical_load, atol=0.001)
    @test !(0 in check)

    # Check that the soc_series_fraction is the same length as the storage_discharge_series_kw
    @test size(results["Outages"]["soc_series_fraction"]) == size(results["Outages"]["storage_discharge_series_kw"])
end

@testset "Multiple Sites" begin
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    ps = [
        REoptInputs("./scenarios/pv_storage.json"),
        REoptInputs("./scenarios/monthly_rate.json"),
    ];
    results = run_reopt(m, ps)
    @test results[3]["Financial"]["lcc"] + results[10]["Financial"]["lcc"] ≈ 1.2830872235e7 rtol=1e-5
end

@testset "MPC" begin
    model = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    r = run_mpc(model, "./scenarios/mpc.json")
    @test maximum(r["ElectricUtility"]["to_load_series_kw"][1:15]) <= 98.0 
    @test maximum(r["ElectricUtility"]["to_load_series_kw"][16:24]) <= 97.0
    @test sum(r["PV"]["to_grid_series_kw"]) ≈ 0
    grid_draw = r["ElectricUtility"]["to_load_series_kw"] .+ r["ElectricUtility"]["to_battery_series_kw"]
    # the grid draw limit in the 10th time step is set to 90
    # without the 90 limit the grid draw is 98 in the 10th time step
    @test grid_draw[10] <= 90
end

@testset "Complex Incentives" begin
    """
    This test was compared against the API test:
        reo.tests.test_reopt_url.EntryResourceTest.test_complex_incentives
    when using the hardcoded levelization_factor in this package's REoptInputs function.
    The two LCC's matched within 0.00005%. (The Julia pkg LCC is  1.0971991e7)
    """
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    results = run_reopt(m, "./scenarios/incentives.json")
    @test results["Financial"]["lcc"] ≈ 1.094596365e7 atol=5e4  
end

@testset verbose = true "Rate Structures" begin

    @testset "Tiered Energy" begin
        m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        results = run_reopt(m, "./scenarios/tiered_energy_rate.json")
        @test results["ElectricTariff"]["year_one_energy_cost_before_tax"] ≈ 2342.88
        @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ 24000.0 atol=0.1
        @test results["ElectricLoad"]["annual_calculated_kwh"] ≈ 24000.0 atol=0.1
    end

    @testset "Lookback Demand Charges" begin
        # 1. Testing rate from URDB
        data = JSON.parsefile("./scenarios/lookback_rate.json")
        # urdb_label used https://apps.openei.org/IURDB/rate/view/539f6a23ec4f024411ec8bf9#2__Demand
        # has a demand charge lookback of 35% for all months with 2 different demand charges based on which month
        data["ElectricLoad"]["loads_kw"] = ones(8760)
        data["ElectricLoad"]["loads_kw"][8] = 100.0
        inputs = REoptInputs(Scenario(data))        
        m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        results = run_reopt(m, inputs)
        # Expected result is 100 kW demand for January, 35% of that for all other months and 
        # with 5x other $10.5/kW cold months and 6x $11.5/kW warm months
        @test results["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ 100 * (10.5 + 0.35*10.5*5 + 0.35*11.5*6)

        # 2. Testing custom rate from user with demand_lookback_months
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

        m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        r = run_reopt(m, REoptInputs(Scenario(d)))

        monthly_peaks = [300,300,300,400,300,500,300,300,300,300,300,300] # 300 = 400*0.75. Sets peak in all months excpet April and June
        expected_demand_cost = sum(monthly_peaks.*d["ElectricTariff"]["monthly_demand_rates"]) 
        @test r["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ expected_demand_cost

        # 3. Testing custom rate from user with demand_lookback_range
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

        m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        r = run_reopt(m, REoptInputs(Scenario(d)))

        monthly_peaks = [225, 225, 225, 400, 300, 500, 375, 375, 375, 375, 375, 375]
        expected_demand_cost = sum(monthly_peaks.*d["ElectricTariff"]["monthly_demand_rates"]) 
        @test r["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ expected_demand_cost

    end

    @testset "Blended tariff" begin
        model = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        results = run_reopt(model, "./scenarios/no_techs.json")
        @test results["ElectricTariff"]["year_one_energy_cost_before_tax"] ≈ 1000.0
        @test results["ElectricTariff"]["year_one_demand_cost_before_tax"] ≈ 136.99
    end

    @testset "Coincident Peak Charges" begin
        model = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        results = run_reopt(model, "./scenarios/coincident_peak.json")
        @test results["ElectricTariff"]["year_one_coincident_peak_cost_before_tax"] ≈ 15.0
    end

    @testset "URDB sell rate" begin
        #= The URDB contains at least one "Customer generation" tariff that only has a "sell" key in the energyratestructure (the tariff tested here)
        =#
        model = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        p = REoptInputs("./scenarios/URDB_customer_generation.json")
        results = run_reopt(model, p)
        @test results["PV"]["size_kw"] ≈ p.max_sizes["PV"]
    end

    # # tiered monthly demand rate  TODO: expected results?
    # m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    # data = JSON.parsefile("./scenarios/tiered_energy_rate.json")
    # data["ElectricTariff"]["urdb_label"] = "59bc22705457a3372642da67"
    # s = Scenario(data)
    # inputs = REoptInputs(s)
    # results = run_reopt(m, inputs)

    # TODO test for tiered TOU demand rates
end

@testset "EASIUR" begin
    d = JSON.parsefile("./scenarios/pv.json")
    d["Site"]["latitude"] = 30.2672
    d["Site"]["longitude"] = -97.7431
    scen = Scenario(d)
    @test scen.financial.NOx_grid_cost_per_tonne ≈ 5510.61 atol=0.1
end

@testset "Wind" begin
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    d = JSON.parsefile("./scenarios/wind.json")
    results = run_reopt(m, d)
    @test results["Wind"]["size_kw"] ≈ 3752 atol=0.1
    @test results["Financial"]["lcc"] ≈ 8.591017e6 rtol=1e-5
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

    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    d["Site"]["land_acres"] = 60 # = 2 MW (with 0.03 acres/kW)
    results = run_reopt(m, d)
    @test results["Wind"]["size_kw"] == 2000.0 # Wind should be constrained by land_acres

    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    d["Wind"]["min_kw"] = 2001 # min_kw greater than land-constrained max should error
    results = run_reopt(m, d)
    @test "errors" ∈ keys(results["Messages"])
    @test length(results["Messages"]["errors"]) > 0
    
end

@testset "Multiple PVs" begin
    m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
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
end

@testset "Thermal Energy Storage + Absorption Chiller" begin
    model = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG"=>0))
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
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
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
    m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    results = run_reopt([m1,m2], inputs)
    
    # BAU boiler loads
    load_thermal_mmbtu_bau = sum(s.space_heating_load.loads_kw + s.dhw_load.loads_kw) / REopt.KWH_PER_MMBTU
    existing_boiler_mmbtu = sum(results["ExistingBoiler"]["thermal_production_series_mmbtu_per_hour"])
    boiler_thermal_mmbtu = sum(results["Boiler"]["thermal_production_series_mmbtu_per_hour"])
    
    # Used monthly fuel cost for ExistingBoiler and Boiler, where ExistingBoiler has lower fuel cost only
    # in February (28 days), so expect ExistingBoiler to serve the flat/constant load 28 days of the year
    @test existing_boiler_mmbtu ≈ load_thermal_mmbtu_bau * 28 / 365 atol=0.00001
    @test boiler_thermal_mmbtu ≈ load_thermal_mmbtu_bau - existing_boiler_mmbtu atol=0.00001
end

@testset "OffGrid" begin
    ## Scenario 1: Solar, Storage, Fixed Generator
    post_name = "off_grid.json" 
    post = JSON.parsefile("./scenarios/$post_name")
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    r = run_reopt(m, post)
    scen = Scenario(post)
    
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

    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    r = run_reopt(m, post)

    # Test generator outputs
    @test r["Generator"]["annual_fuel_consumption_gal"] ≈ 7.52 # 99 kWh * 0.076 gal/kWh
    @test r["Generator"]["annual_energy_produced_kwh"] ≈ 99.0
    @test r["Generator"]["year_one_fuel_cost_before_tax"] ≈ 22.57
    @test r["Generator"]["lifecycle_fuel_cost_after_tax"] ≈ 205.35 
    @test r["Financial"]["initial_capital_costs"] ≈ 100*(700) 
    @test r["Financial"]["lifecycle_capital_costs"] ≈ 100*(700+324.235442*(1-0.26)) atol=0.1 # replacement in yr 10 is considered tax deductible
    @test r["Financial"]["initial_capital_costs_after_incentives"] ≈ 700*100 atol=0.1
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

    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    r = run_reopt(m, post)

    # Test generator outputs
    @test typeof(r) == Model # this is true when the model is infeasible

    ### Scenario 3: Indonesia. Wind (custom prod) and Generator only
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
    post_name = "wind_intl_offgrid.json" 
    post = JSON.parsefile("./scenarios/$post_name")
    post["ElectricLoad"]["loads_kw"] = [10.0 for i in range(1,8760)]
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
    m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.001, "OUTPUTLOG" => 0))
    m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.001, "OUTPUTLOG" => 0))
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
    @test round(boiler_served_mmbtu, digits=1) ≈ expected_boiler_served_mmbtu atol=1.0
    
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
end

@testset "Hybrid GHX and GHP calculated costs validation" begin
    ## Hybrid GHP validation.
    # Load base inputs
    input_data = JSON.parsefile("scenarios/ghp_financial_hybrid.json")

    inputs = REoptInputs(input_data)

    m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.001, "OUTPUTLOG" => 0))
    m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.001, "OUTPUTLOG" => 0))
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

    @test abs(results["Financial"]["lifecycle_capital_costs_plus_om_after_tax"] - (calc_om_cost_after_tax + 0.7*results["Financial"]["initial_capital_costs"])) < 150.0

    @test abs(results["Financial"]["lifecycle_capital_costs"] - 0.7*results["Financial"]["initial_capital_costs"]) < 150.0

    @test abs(results["Financial"]["npv"] - 840621) < 1.0
    @test results["Financial"]["simple_payback_years"] - 5.09 < 0.1
    @test results["Financial"]["internal_rate_of_return"] - 0.18 < 0.01

    @test haskey(results["ExistingBoiler"], "year_one_fuel_cost_before_tax_bau")

    ## Hybrid
    input_data["GHP"]["ghpghx_responses"] = [JSON.parsefile("scenarios/ghpghx_hybrid_results.json")]
    input_data["GHP"]["avoided_capex_by_ghp_present_value"] = 1.0e6
    input_data["GHP"]["ghx_useful_life_years"] = 35

    inputs = REoptInputs(input_data)

    m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.001, "OUTPUTLOG" => 0))
    m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.001, "OUTPUTLOG" => 0))
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

    # Test centralized GHP cost calculations
    input_data_wwhp = JSON.parsefile("scenarios/ghp_inputs_wwhp.json")
    response_wwhp = JSON.parsefile("scenarios/ghpghx_response_wwhp.json")
    input_data_wwhp["GHP"]["ghpghx_responses"] = [response_wwhp]

    s_wwhp = Scenario(input_data_wwhp)
    inputs_wwhp = REoptInputs(s_wwhp)
    m3 = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.001, "OUTPUTLOG" => 0))
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

    reopt_ghp_capex = results_wwhp["Financial"]["lifecycle_capital_costs"]
    @test calculated_ghp_capex ≈ reopt_ghp_capex atol=300
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

        m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
        m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
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
            @test results["PV"]["size_kw"] ≈ 60.12 atol=1e-1
            @test results["ElectricStorage"]["size_kw"] ≈ 0.0 atol=1e-1
            @test results["ElectricStorage"]["size_kwh"] ≈ 0.0 atol=1e-1
            @test results["Generator"]["size_kw"] ≈ 21.52 atol=1e-1
            @test results["Site"]["onsite_renewable_energy_fraction_of_total_load"] ≈ 0.8
            @test results["Site"]["onsite_renewable_energy_fraction_of_total_load_bau"] ≈ 0.147576 atol=1e-4
            @test results["Site"]["lifecycle_emissions_reduction_CO2_fraction"] ≈ 0.58694032 atol=1e-4
            @test results["Financial"]["breakeven_cost_of_emissions_reduction_per_tonne_CO2"] ≈ 355.8 atol=1
            @test results["Site"]["annual_emissions_tonnes_CO2"] ≈ 11.64 atol=1e-2
            @test results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"] ≈ 7.0605
            @test results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2_bau"] ≈ 0.0
            @test results["Financial"]["lifecycle_emissions_cost_climate"] ≈ 8315.69 atol=1
            @test results["Site"]["lifecycle_emissions_tonnes_CO2"] ≈ 232.85
            @test results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_CO2"] ≈ 141.21
            @test results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_CO2_bau"] ≈ 0.0
            @test results["ElectricUtility"]["annual_emissions_tonnes_CO2_bau"] ≈ 28.186 atol=1e-1
            @test results["ElectricUtility"]["lifecycle_emissions_tonnes_CO2_bau"] ≈ 563.72
        elseif i == 2
            #commented out values are results using same levelization factor as API
            @test results["PV"]["size_kw"] ≈ 106.13 atol=1
            @test results["ElectricStorage"]["size_kw"] ≈ 21.58 atol=1 # 20.29
            @test results["ElectricStorage"]["size_kwh"] ≈ 166.29 atol=1
            @test !haskey(results, "Generator")
            # Renewable energy
            @test results["Site"]["onsite_renewable_electricity_fraction_of_elec_load"] ≈ 0.78586 atol=1e-3
            @test results["Site"]["onsite_renewable_electricity_fraction_of_elec_load_bau"] ≈ 0.132118 atol=1e-3 #0.1354 atol=1e-3
            @test results["Site"]["annual_onsite_renewable_electricity_kwh_bau"] ≈ 13211.78 atol=10 # 13542.62 atol=10
            @test results["Site"]["onsite_renewable_energy_fraction_of_total_load_bau"] ≈ 0.132118 atol=1e-3 # 0.1354 atol=1e-3
            # CO2 emissions - totals ≈  from grid, from fuelburn, ER, $/tCO2 breakeven
            @test results["Site"]["lifecycle_emissions_reduction_CO2_fraction"] ≈ 0.8 atol=1e-3 # 0.8
            @test results["Financial"]["breakeven_cost_of_emissions_reduction_per_tonne_CO2"] ≈ 460.7 atol=1e-1
            @test results["Site"]["annual_emissions_tonnes_CO2"] ≈ 11.662 atol=1
            @test results["Site"]["annual_emissions_tonnes_CO2_bau"] ≈ 58.3095 atol=1
            @test results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"] ≈ 0.0 atol=1 # 0.0
            @test results["Financial"]["lifecycle_emissions_cost_climate"] ≈ 8401.1 atol=1
            @test results["Site"]["lifecycle_emissions_tonnes_CO2_bau"] ≈ 1166.19 atol=1
            @test results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_CO2"] ≈ 0.0 atol=1 # 0.0
            @test results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_CO2_bau"] ≈ 0.0 atol=1 # 0.0
            @test results["ElectricUtility"]["annual_emissions_tonnes_CO2_bau"] ≈ 58.3095 atol=1
            @test results["ElectricUtility"]["lifecycle_emissions_tonnes_CO2"] ≈ 233.24 atol=1


            #also test CO2 breakeven cost
            inputs["PV"]["min_kw"] = results["PV"]["size_kw"] - inputs["PV"]["existing_kw"]
            inputs["PV"]["max_kw"] = results["PV"]["size_kw"] - inputs["PV"]["existing_kw"]
            inputs["ElectricStorage"]["min_kw"] = results["ElectricStorage"]["size_kw"]
            inputs["ElectricStorage"]["max_kw"] = results["ElectricStorage"]["size_kw"]
            inputs["ElectricStorage"]["min_kwh"] = results["ElectricStorage"]["size_kwh"]
            inputs["ElectricStorage"]["max_kwh"] = results["ElectricStorage"]["size_kwh"]
            inputs["Financial"]["CO2_cost_per_tonne"] = results["Financial"]["breakeven_cost_of_emissions_reduction_per_tonne_CO2"]
            inputs["Settings"]["include_climate_in_objective"] = true
            m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
            m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
            results = run_reopt([m1, m2], inputs)
            @test results["Financial"]["breakeven_cost_of_emissions_reduction_per_tonne_CO2"] ≈ inputs["Financial"]["CO2_cost_per_tonne"] atol=1e-1
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
            @test results["Site"]["lifecycle_emissions_tonnes_CO2"] ≈ results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_CO2"] + results["ElectricUtility"]["lifecycle_emissions_tonnes_CO2"] atol=1
            @test results["Site"]["lifecycle_emissions_tonnes_NOx"] ≈ results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_NOx"] + results["ElectricUtility"]["lifecycle_emissions_tonnes_NOx"] atol=0.1
            @test results["Site"]["lifecycle_emissions_tonnes_SO2"] ≈ results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_SO2"] + results["ElectricUtility"]["lifecycle_emissions_tonnes_SO2"] atol=1e-2
            @test results["Site"]["lifecycle_emissions_tonnes_PM25"] ≈ results["Site"]["lifecycle_emissions_from_fuelburn_tonnes_PM25"] + results["ElectricUtility"]["lifecycle_emissions_tonnes_PM25"] atol=1.5e-2
            @test results["Site"]["annual_onsite_renewable_electricity_kwh"] ≈ results["PV"]["annual_energy_produced_kwh"] + inputs["CHP"]["fuel_renewable_energy_fraction"] * results["CHP"]["annual_electric_production_kwh"] atol=1
            @test results["Site"]["onsite_renewable_electricity_fraction_of_elec_load"] ≈ results["Site"]["annual_onsite_renewable_electricity_kwh"] / results["ElectricLoad"]["annual_calculated_kwh"] atol=1e-6#0.044285 atol=1e-4
            annual_RE_kwh = inputs["CHP"]["fuel_renewable_energy_fraction"] * results["CHP"]["annual_thermal_production_mmbtu"] * REopt.KWH_PER_MMBTU + results["Site"]["annual_onsite_renewable_electricity_kwh"]
            annual_heat_kwh = (results["CHP"]["annual_thermal_production_mmbtu"] + results["ExistingBoiler"]["annual_thermal_production_mmbtu"]) * REopt.KWH_PER_MMBTU
            @test results["Site"]["onsite_renewable_energy_fraction_of_total_load"] ≈ annual_RE_kwh / (annual_heat_kwh + results["ElectricLoad"]["annual_calculated_kwh"]) atol=1e-6
        end
    end
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
    m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
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
                                        ("om_cost_per_ton", 0.5)
                                        ])
    
    # Add Hot TES
    input_data["HotThermalStorage"] = Dict{Any, Any}([
                            ("min_gal", 50000.0),
                            ("max_gal", 50000.0)
                            ])
    
    s = Scenario(input_data)
    inputs = REoptInputs(s)
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => 0.01, "OUTPUTLOG" => 0))
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
end

@testset "Electric Heater" begin
    d = JSON.parsefile("./scenarios/electric_heater.json")
    d["SpaceHeatingLoad"]["annual_mmbtu"] = 0.5 * 8760
    d["DomesticHotWaterLoad"]["annual_mmbtu"] = 0.5 * 8760
    s = Scenario(d)
    p = REoptInputs(s)
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    results = run_reopt(m, p)

    #first run: Boiler produces the required heat instead of the electric heater - electric heater should not be purchased
    @test results["ElectricHeater"]["size_mmbtu_per_hour"] ≈ 0.0 atol=0.1
    @test results["ElectricHeater"]["annual_thermal_production_mmbtu"] ≈ 0.0 atol=0.1
    @test results["ElectricHeater"]["annual_electric_consumption_kwh"] ≈ 0.0 atol=0.1
    @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ 87600.0 atol=0.1
    
    d["ExistingBoiler"]["fuel_cost_per_mmbtu"] = 100
    d["ElectricHeater"]["installed_cost_per_mmbtu_per_hour"] = 1.0
    d["ElectricTariff"]["monthly_energy_rates"] = [0,0,0,0,0,0,0,0,0,0,0,0]
    s = Scenario(d)
    p = REoptInputs(s)
    m = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
    results = run_reopt(m, p)

    annual_thermal_prod = 0.8 * 8760  #80% efficient boiler --> 0.8 MMBTU of heat load per hour
    annual_electric_heater_consumption = annual_thermal_prod * REopt.KWH_PER_MMBTU  #1.0 COP
    annual_energy_supplied = 87600 + annual_electric_heater_consumption

    #Second run: ElectricHeater produces the required heat with free electricity
    @test results["ElectricHeater"]["size_mmbtu_per_hour"] ≈ 0.8 atol=0.1
    @test results["ElectricHeater"]["annual_thermal_production_mmbtu"] ≈ annual_thermal_prod rtol=1e-4
    @test results["ElectricHeater"]["annual_electric_consumption_kwh"] ≈ annual_electric_heater_consumption rtol=1e-4
    @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ annual_energy_supplied rtol=1e-4

end

@testset "Custom REopt logger" begin
    
    # Throw a handled error
    d = JSON.parsefile("./scenarios/logger.json")

    m1 = Model(Xpress.Optimizer)
    m2 = Model(Xpress.Optimizer)
    r = run_reopt([m1,m2], d)
    @test r["status"] == "error"
    @test "Messages" ∈ keys(r)
    @test "errors" ∈ keys(r["Messages"])
    @test "warnings" ∈ keys(r["Messages"])
    @test length(r["Messages"]["errors"]) > 0
    @test length(r["Messages"]["warnings"]) > 0
    @test r["Messages"]["has_stacktrace"] == false

    m = Model(Xpress.Optimizer)
    r = run_reopt(m, d)
    @test r["status"] == "error"
    @test "Messages" ∈ keys(r)
    @test "errors" ∈ keys(r["Messages"])
    @test "warnings" ∈ keys(r["Messages"])
    @test length(r["Messages"]["errors"]) > 0
    @test length(r["Messages"]["warnings"]) > 0

    # Type is dict when errors, otherwise type REoptInputs
    @test isa(REoptInputs(d), Dict)

    # Using filepath
    n1 = Model(Xpress.Optimizer)
    n2 = Model(Xpress.Optimizer)
    r = run_reopt([n1,n2], "./scenarios/logger.json")
    @test r["status"] == "error"
    @test "Messages" ∈ keys(r)
    @test "errors" ∈ keys(r["Messages"])
    @test "warnings" ∈ keys(r["Messages"])
    @test length(r["Messages"]["errors"]) > 0
    @test length(r["Messages"]["warnings"]) > 0

    n = Model(Xpress.Optimizer)
    r = run_reopt(n, "./scenarios/logger.json")
    @test r["status"] == "error"
    @test "Messages" ∈ keys(r)
    @test "errors" ∈ keys(r["Messages"])
    @test "warnings" ∈ keys(r["Messages"])
    @test length(r["Messages"]["errors"]) > 0
    @test length(r["Messages"]["warnings"]) > 0

    # Throw an unhandled error: Bad URDB rate -> stack gets returned for debugging
    d["ElectricLoad"]["doe_reference_name"] = "MidriseApartment"
    d["ElectricTariff"]["urdb_label"] = "62c70a6c40a0c425535d387x"

    m1 = Model(Xpress.Optimizer)
    m2 = Model(Xpress.Optimizer)
    r = run_reopt([m1,m2], d)
    @test r["status"] == "error"
    @test "Messages" ∈ keys(r)
    @test "errors" ∈ keys(r["Messages"])
    @test "warnings" ∈ keys(r["Messages"])
    @test length(r["Messages"]["errors"]) > 0
    @test length(r["Messages"]["warnings"]) > 0

    m = Model(Xpress.Optimizer)
    r = run_reopt(m, d)
    @test r["status"] == "error"
    @test "Messages" ∈ keys(r)
    @test "errors" ∈ keys(r["Messages"])
    @test "warnings" ∈ keys(r["Messages"])
    @test length(r["Messages"]["errors"]) > 0
    @test length(r["Messages"]["warnings"]) > 0

    # Type is dict when errors, otherwise type REoptInputs
    @test isa(REoptInputs(d), Dict)

    # Using filepath
    n1 = Model(Xpress.Optimizer)
    n2 = Model(Xpress.Optimizer)
    r = run_reopt([n1,n2], "./scenarios/logger.json")
    @test r["status"] == "error"
    @test "Messages" ∈ keys(r)
    @test "errors" ∈ keys(r["Messages"])
    @test "warnings" ∈ keys(r["Messages"])
    @test length(r["Messages"]["errors"]) > 0
    @test length(r["Messages"]["warnings"]) > 0

    n = Model(Xpress.Optimizer)
    r = run_reopt(n, "./scenarios/logger.json")
    @test r["status"] == "error"
    @test "Messages" ∈ keys(r)
    @test "errors" ∈ keys(r["Messages"])
    @test "warnings" ∈ keys(r["Messages"])
    @test length(r["Messages"]["errors"]) > 0
    @test length(r["Messages"]["warnings"]) > 0
end