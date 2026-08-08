# using Revise
# using REopt
# using JSON
# using DelimitedFiles
# using PlotlyJS
# using Dates
# using Test
# using JuMP
# using HiGHS
# using DotEnv
# DotEnv.load!()

@testset "Numeric boolean inputs" begin
    @test REopt.dictkeys_tosymbols(Dict("off_grid_flag" => 0.0))[:off_grid_flag] === false
    @test REopt.dictkeys_tosymbols(Dict("off_grid_flag" => 1.0))[:off_grid_flag] === true
    @test_throws ArgumentError REopt.dictkeys_tosymbols(Dict("off_grid_flag" => 2.0))
end


###############   Multiple CHPs Test    ###################
@testset "Multiple CHPs" begin
    # With BAU Scenario
    input_data = JSON.parsefile("./scenarios/multiple_chps.json")
    s = Scenario(input_data)
    inputs = REoptInputs(s)

    m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.05, "output_flag" => false, "log_to_console" => false))
    m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.05, "output_flag" => false, "log_to_console" => false))
    results = run_reopt([m1,m2], inputs)

    @test length(results["CHP"]) == 2
    CHP_recip_engine = results["CHP"][findfirst(chp -> chp["name"] == "CHP_recip_engine", results["CHP"])]
    CHP_micro_turbine = results["CHP"][findfirst(chp -> chp["name"] == "CHP_micro_turbine", results["CHP"])]

    # Check that each CHP has sizing results
    @test CHP_recip_engine["size_kw"] > 10.0
    @test CHP_micro_turbine["size_kw"] > 10.0

    # Check that results include electric production for each CHP
    @test sum(CHP_recip_engine["electric_production_series_kw"]) > 500.0
    @test sum(CHP_micro_turbine["electric_production_series_kw"]) > 500.0

    # Test that LCC matches sum of discounted cashflows for optimal case (within 0.1% tolerance)
    # Note, cashflows are negative where lcc is positive, so negating cashflows in comparison
    optimal_lcc = results["Financial"]["lcc"]
    optimal_cashflow_sum = -1*sum(results["Financial"]["offtaker_discounted_annual_free_cashflows"])
    @test isapprox(optimal_lcc, optimal_cashflow_sum, rtol=0.001)

    # Test that LCC matches sum of discounted cashflows for BAU case (within 0.1% tolerance)
    bau_lcc = results["Financial"]["lcc_bau"]
    bau_cashflow_sum = -1*sum(results["Financial"]["offtaker_discounted_annual_free_cashflows_bau"])
    @test isapprox(bau_lcc, bau_cashflow_sum, rtol=0.001)

    # Add a test to compare npv with difference in optimal and bau cashflows
    npv_calculated = bau_cashflow_sum - optimal_cashflow_sum
    npv_reported = results["Financial"]["npv"]
    @test isapprox(npv_calculated, npv_reported, rtol=0.001)

    outage_data = JSON.parsefile("./scenarios/multiple_chps.json")
    outage_data["ElectricUtility"] = Dict(
        "outage_start_time_steps" => [1],
        "outage_durations" => [2],
        "outage_probabilities" => [1.0]
    )
    outage_s = Scenario(outage_data)
    outage_inputs = REoptInputs(outage_s)
    outage_model = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
    build_reopt!(outage_model, outage_inputs)
    for chp in outage_s.chps
        @test outage_model[:binMGCHPIsOnInTS][chp.name, 1, 1, 1] isa VariableRef
        @test outage_model[:dvMGCHPOnSize][chp.name, 1, 1, 1] isa VariableRef
    end

    finalize(backend(m1)); empty!(m1)
    finalize(backend(m2)); empty!(m2)
    finalize(backend(outage_model)); empty!(outage_model)
    GC.gc()
end

###############   CHP Binary Creation Tests    ###################
# Tests to verify that binCHPIsOnInTS is only created when needed

function chp_binary_test_data()
    data = JSON.parsefile("./scenarios/chp_unavailability_outage.json")
    data["PV"]["production_factor_series"] = zeros(8760)
    return data
end

@testset verbose=true "CHP Binary Creation Tests" begin
    # These only need the model built (variables + constraints), not solved, since
    # binary_needed in add_chp_constraints is decided purely from input parameters.

    @testset "CHP with min_turn_down_fraction > 0 (binary SHOULD be created)" begin
        # Test that binCHPIsOnInTS gets created when min_turn_down_fraction > 0
        data = chp_binary_test_data()

        # Set min_turn_down_fraction to a non-zero value
        data["CHP"]["min_turn_down_fraction"] = 0.5

        # Remove outage to simplify the test
        delete!(data, "ElectricUtility")
        data["ElectricUtility"] = Dict("net_metering_limit_kw" => 0.0, "co2_from_avert" => true)

        s = Scenario(data)
        inputs = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        build_reopt!(m, inputs)

        # Verify the binary variable was created
        @test haskey(m.obj_dict, :binCHPIsOnInTS)

        finalize(backend(m))
        empty!(m)
    end

    @testset "CHP with min_turn_down_fraction = 0 (binary should NOT be created)" begin
        # Test that binCHPIsOnInTS is NOT created when all conditions are zero/equal
        data = chp_binary_test_data()

        # Set min_turn_down_fraction to zero
        data["CHP"]["min_turn_down_fraction"] = 0.0

        # Ensure no intercepts by making efficiencies equal (no part-load curve)
        # When electric_efficiency_full_load == electric_efficiency_half_load, intercept = 0
        data["CHP"]["electric_efficiency_full_load"] = 0.35
        data["CHP"]["electric_efficiency_half_load"] = 0.35
        data["CHP"]["thermal_efficiency_full_load"] = 0.45
        data["CHP"]["thermal_efficiency_half_load"] = 0.45

        # Ensure no hourly O&M cost
        data["CHP"]["om_cost_per_hr_per_kw_rated"] = 0.0

        # Remove outage to simplify
        delete!(data, "ElectricUtility")
        data["ElectricUtility"] = Dict("net_metering_limit_kw" => 0.0, "co2_from_avert" => true)

        s = Scenario(data)
        inputs = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        build_reopt!(m, inputs)

        # Verify the binary variable was NOT created
        @test !haskey(m.obj_dict, :binCHPIsOnInTS)

        finalize(backend(m))
        empty!(m)
    end

    @testset "CHP with fuel_burn_intercept > 0 (binary SHOULD be created)" begin
        # Test that binary is created when fuel burn has non-zero intercept
        data = chp_binary_test_data()

        # Set min_turn_down_fraction to zero
        data["CHP"]["min_turn_down_fraction"] = 0.0

        # Create non-zero fuel burn intercept by having different efficiencies
        data["CHP"]["electric_efficiency_full_load"] = 0.40
        data["CHP"]["electric_efficiency_half_load"] = 0.30  # Different from full load
        data["CHP"]["thermal_efficiency_full_load"] = 0.45
        data["CHP"]["thermal_efficiency_half_load"] = 0.45  # Keep thermal same to isolate fuel burn

        # Ensure no hourly O&M cost
        data["CHP"]["om_cost_per_hr_per_kw_rated"] = 0.0

        delete!(data, "ElectricUtility")
        data["ElectricUtility"] = Dict("net_metering_limit_kw" => 0.0, "co2_from_avert" => true)

        s = Scenario(data)
        inputs = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        build_reopt!(m, inputs)

        # Verify the binary variable was created
        @test haskey(m.obj_dict, :binCHPIsOnInTS)

        finalize(backend(m))
        empty!(m)
    end

    @testset "CHP with thermal_prod_intercept > 0 (binary SHOULD be created)" begin
        # Test that binary is created when thermal production has non-zero intercept
        data = chp_binary_test_data()

        # Set min_turn_down_fraction to zero
        data["CHP"]["min_turn_down_fraction"] = 0.0

        # Create non-zero thermal prod intercept by having different thermal efficiencies
        data["CHP"]["electric_efficiency_full_load"] = 0.35
        data["CHP"]["electric_efficiency_half_load"] = 0.35  # Keep electric same
        data["CHP"]["thermal_efficiency_full_load"] = 0.40
        data["CHP"]["thermal_efficiency_half_load"] = 0.50  # Different from full load

        # Ensure no hourly O&M cost
        data["CHP"]["om_cost_per_hr_per_kw_rated"] = 0.0

        delete!(data, "ElectricUtility")
        data["ElectricUtility"] = Dict("net_metering_limit_kw" => 0.0, "co2_from_avert" => true)

        s = Scenario(data)
        inputs = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        build_reopt!(m, inputs)

        # Verify the binary variable was created
        @test haskey(m.obj_dict, :binCHPIsOnInTS)

        finalize(backend(m))
        empty!(m)
    end

    @testset "CHP with om_cost_per_hr_per_kw_rated > 0 (binary SHOULD be created)" begin
        # Test that binary is created when hourly O&M cost is non-zero
        data = chp_binary_test_data()

        # Set min_turn_down_fraction to zero
        data["CHP"]["min_turn_down_fraction"] = 0.0

        # Make efficiencies equal (no intercepts)
        data["CHP"]["electric_efficiency_full_load"] = 0.35
        data["CHP"]["electric_efficiency_half_load"] = 0.35
        data["CHP"]["thermal_efficiency_full_load"] = 0.45
        data["CHP"]["thermal_efficiency_half_load"] = 0.45

        # Set non-zero hourly O&M cost
        data["CHP"]["om_cost_per_hr_per_kw_rated"] = 0.01

        delete!(data, "ElectricUtility")
        data["ElectricUtility"] = Dict("net_metering_limit_kw" => 0.0, "co2_from_avert" => true)

        s = Scenario(data)
        inputs = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        build_reopt!(m, inputs)

        # Verify the binary variable was created
        @test haskey(m.obj_dict, :binCHPIsOnInTS)

        finalize(backend(m))
        empty!(m)
    end

    @testset "CHP with supplementary firing (binary SHOULD be created)" begin
        data = chp_binary_test_data()
        data["CHP"]["min_turn_down_fraction"] = 0.0
        data["CHP"]["electric_efficiency_full_load"] = 0.35
        data["CHP"]["electric_efficiency_half_load"] = 0.35
        data["CHP"]["thermal_efficiency_full_load"] = 0.45
        data["CHP"]["thermal_efficiency_half_load"] = 0.45
        data["CHP"]["om_cost_per_hr_per_kw_rated"] = 0.0
        data["CHP"]["supplementary_firing_max_steam_ratio"] = 1.2
        delete!(data, "ElectricUtility")
        data["ElectricUtility"] = Dict("net_metering_limit_kw" => 0.0, "co2_from_avert" => true)

        s = Scenario(data)
        inputs = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        build_reopt!(m, inputs)

        @test haskey(m.obj_dict, :binCHPIsOnInTS)

        finalize(backend(m))
        empty!(m)
    end
end

###############   Off-Grid CHP with Operating Reserves Test    ###################
@testset "Off-Grid CHP" begin
    # Test off-grid scenario with CHP and ElectricStorage where CHP requires 10% operating reserves
    # This tests that ElectricStorage provides the required reserves for CHP generation

    input_data = JSON.parsefile("./scenarios/chp_offgrid.json")
    input_data["ElectricLoad"]["min_load_met_annual_fraction"] = 0.999
    input_data["ElectricLoad"]["operating_reserve_required_fraction"] = 0.0
    input_data["CHP"]["operating_reserve_required_fraction"] = 0.2

    # Create scenario and run optimization
    s = Scenario(input_data)
    inputs = REoptInputs(s)

    m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
    results = run_reopt(m, inputs)

    # Check that the model solved successfully
    @test termination_status(m) == MOI.OPTIMAL || termination_status(m) == MOI.LOCALLY_SOLVED

    # Calculate operating reserve requirements
    chp_production_to_load = results["CHP"]["electric_to_load_series_kw"]
    chp_or_required = sum(chp_production_to_load .* s.chps[1].operating_reserve_required_fraction)
    load_or_required = sum(s.electric_load.critical_loads_kw .* s.electric_load.operating_reserve_required_fraction)
    total_or_required = chp_or_required + load_or_required

    # Get operating reserve provided
    or_provided = sum(results["ElectricLoad"]["offgrid_annual_oper_res_provided_series_kwh"])

    # Test 1: Operating reserves provided >= operating reserves required (with tolerance for solver gap)
    @test or_provided >= total_or_required * (1 - 0.02)  # Allow 2% gap due to mip_rel_gap and rounding

    # Test 2: CHP produces electricity in off-grid scenario
    chp_annual_production = sum(results["CHP"]["electric_to_load_series_kw"]) +
                            sum(results["CHP"]["electric_to_storage_series_kw"])
    @test chp_annual_production > 0

    # Test 3: Battery is sized to provide operating reserves
    battery_sized = results["ElectricStorage"]["size_kw"] > 0 || results["ElectricStorage"]["size_kwh"] > 0
    @test battery_sized

    # Test 4: Load is met according to minimum fraction
    @test results["ElectricLoad"]["offgrid_load_met_fraction"] >= s.electric_load.min_load_met_annual_fraction

    # Test 5: No grid interaction in off-grid scenario
    @test results["ElectricUtility"]["annual_energy_supplied_kwh"] ≈ 0.0 atol=0.01

    # Test 6: Financial calculation includes off-grid costs
    f = results["Financial"]
    lcc_check = f["lifecycle_generation_tech_capital_costs"] + f["lifecycle_storage_capital_costs"] +
                f["lifecycle_om_costs_after_tax"] + f["lifecycle_fuel_costs_after_tax"] +
                f["lifecycle_chp_standby_cost_after_tax"] + f["lifecycle_elecbill_after_tax"] +
                f["lifecycle_offgrid_other_annual_costs_after_tax"] + f["lifecycle_offgrid_other_capital_costs"] +
                f["lifecycle_outage_cost"] + f["lifecycle_MG_upgrade_and_fuel_cost"] -
                f["lifecycle_production_incentive_after_tax"]
    @test lcc_check ≈ f["lcc"] atol=1.0

    finalize(backend(m)); empty!(m); GC.gc()
end

###############   CHP Ramp Rate Test    ###################
@testset "CHP Ramp Rate" begin
    # CHP electric-only with a ramp rate limit, forced to peak-load size, with a full-year
    # outage so REopt must size the battery to cover load changes CHP can't ramp fast enough to follow.
    input_data = JSON.parsefile("./scenarios/nuclear_battery.json")

    # Ramp rate input/constraint (fraction of capacity per hour)
    input_data["CHP"]["ramp_rate_fraction_per_hour"] = 0.1

    # Year-long outage scenario
    input_data["ElectricLoad"] = Dict("doe_reference_name" => "Hospital", "annual_kwh" => 4.0e6)
    input_data["ElectricLoad"]["critical_load_fraction"] = 1.0
    input_data["ElectricUtility"] = Dict("outage_start_time_step" => 1,
                                        "outage_end_time_step" => 8760)
    input_data["ElectricStorage"] = Dict()

    # Force CHP to peak load size (estimated from annual energy assuming 50% capacity factor),
    # so the battery is what has to absorb the ramp rate limit
    estimated_peak_load_kw = 740.0
    input_data["CHP"]["min_kw"] = estimated_peak_load_kw
    input_data["CHP"]["max_kw"] = estimated_peak_load_kw

    s = Scenario(input_data)
    inputs = REoptInputs(s)
    ts_per_hour = s.settings.time_steps_per_hour

    m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
    results = run_reopt(m, inputs)

    @test results["status"] == "optimal"
    @test results["CHP"]["size_kw"] ≈ estimated_peak_load_kw atol=1.0

    # CHP output between consecutive timesteps must respect the ramp rate limit
    chp_production_kw = results["CHP"]["electric_production_series_kw"]
    ramp_limit_kw = input_data["CHP"]["ramp_rate_fraction_per_hour"] * results["CHP"]["size_kw"] / ts_per_hour
    @test maximum(abs.(diff(chp_production_kw))) <= ramp_limit_kw + 1e-3

    # Battery must be sized to cover load changes CHP can't ramp fast enough to follow
    @test results["ElectricStorage"]["size_kw"] > 0.0

    finalize(backend(m)); empty!(m); GC.gc()
end

###########   CHP production_factor_series test   #############
@testset "CHP with production_factor_series" begin
    # Create a simple scenario with electric-only CHP and a custom production factor
    input_data = Dict(
        "Site" => Dict(
            "latitude" => 39.7,
            "longitude" => -104.9
        ),
        "ElectricLoad" => Dict(
            "loads_kw" => repeat([100.0], 8760),
            "year" => 2025
        ),
        "ElectricTariff" => Dict(
            "urdb_label" => "5ed6c1a15457a3367add15ae"
        ),
        "CHP" => Dict(
            "is_electric_only" => true,
            "fuel_cost_per_mmbtu" => 4.0,
            "max_kw" => 100.0,
            "min_kw" => 100.0,
            "production_factor_series" => vcat(repeat([0.5], 4380), repeat([1.0], 4380))  # 50% for first half year, 100% for second half
        )
    )

    s = Scenario(input_data)
    p = REoptInputs(s)

    # Verify the production factor series was properly assigned
    @test !isnothing(s.chps[1].production_factor_series)
    @test length(s.chps[1].production_factor_series) == 8760
    @test s.chps[1].production_factor_series[1] ≈ 0.5 atol=0.001
    @test s.chps[1].production_factor_series[8760] ≈ 1.0 atol=0.001
    @test_throws ArgumentError REopt.get_chp_by_name("missing", s.chps)

    subhourly_input_data = deepcopy(input_data)
    subhourly_input_data["Settings"] = Dict("time_steps_per_hour" => 2)
    subhourly_s = Scenario(subhourly_input_data)
    @test length(subhourly_s.chps[1].production_factor_series) == 17520
    @test subhourly_s.chps[1].production_factor_series[1:2] == [0.5, 0.5]

    empty_series_input_data = deepcopy(input_data)
    empty_series_input_data["CHP"]["production_factor_series"] = Float64[]
    @test_throws ArgumentError Scenario(empty_series_input_data)

    load_following_input_data = deepcopy(input_data)
    load_following_input_data["ElectricLoad"]["loads_kw"] = fill(40.0, 8760)
    load_following_input_data["CHP"]["min_kw"] = 100.0
    load_following_input_data["CHP"]["max_kw"] = 100.0
    load_following_input_data["CHP"]["min_turn_down_fraction"] = 0.5
    load_following_input_data["CHP"]["follow_electrical_load"] = true
    load_following_input_data["CHP"]["production_factor_series"] = fill(0.5, 8760)
    @test Scenario(load_following_input_data).chps[1].follow_electrical_load

    # Run the optimization
    m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
    results = run_reopt(m, p)

    # Production should be lower in the first half of the year (0.5 factor) than the second half (1.0 factor)
    first_half_avg = sum(results["CHP"]["electric_production_series_kw"][1:4380]) / 4380
    second_half_avg = sum(results["CHP"]["electric_production_series_kw"][4381:8760]) / 4380
    @test second_half_avg > first_half_avg

    finalize(backend(m)); empty!(m); GC.gc()
end

@testset "CHP production_factor_series with unavailability and outage" begin
    production_factor_series = fill(1.0, 8760)
    production_factor_series[121] = 0.8
    production_factor_series[122] = 0.9
    production_factor_series[123] = 0.7

    input_data = Dict(
        "Site" => Dict(
            "latitude" => 39.7,
            "longitude" => -104.9
        ),
        "ElectricLoad" => Dict(
            "loads_kw" => repeat([100.0], 8760),
            "year" => 2025
        ),
        "ElectricTariff" => Dict(
            "urdb_label" => "5ed6c1a15457a3367add15ae"
        ),
        "ElectricUtility" => Dict(
            "outage_start_time_step" => 121,
            "outage_end_time_step" => 122
        ),
        "CHP" => Dict(
            "is_electric_only" => true,
            "fuel_cost_per_mmbtu" => 4.0,
            "max_kw" => 100.0,
            "min_kw" => 100.0,
            "production_factor_series" => production_factor_series,
            "unavailability_periods" => [Dict(
                "month" => 1,
                "start_week_of_month" => 2,
                "start_day_of_week" => 1,
                "start_hour" => 1,
                "duration_hours" => 3
            )]
        )
    )

    s = Scenario(input_data)
    p = REoptInputs(s)
    chp_name = s.chps[1].name
    prod_factor = p.production_factor[chp_name, :].data

    @test prod_factor[121] ≈ 0.8 atol=0.001
    @test prod_factor[122] ≈ 0.9 atol=0.001
    @test prod_factor[123] ≈ 0.0 atol=0.001
    @test prod_factor[124] ≈ 1.0 atol=0.001
end