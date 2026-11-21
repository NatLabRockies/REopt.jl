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


@testset "CHP monthly fuel costs" begin
    monthly_costs = collect(1.0:12.0)
    month_days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    for time_steps_per_hour in (1, 4)
        input_data = JSON.parsefile(joinpath(@__DIR__, "scenarios", "chp_sizing.json"))
        input_data["CHP"]["fuel_cost_per_mmbtu"] = JSON.parse(JSON.json(monthly_costs))
        input_data["Settings"] = Dict("time_steps_per_hour" => time_steps_per_hour)
        scenario = Scenario(input_data)
        inputs = REoptInputs(scenario)
        chp = only(scenario.chps)
        fuel_costs = inputs.fuel_cost_per_kwh[chp.name]

        @test chp.fuel_cost_per_mmbtu == monthly_costs
        @test length(fuel_costs) == 8760 * time_steps_per_hour
        first_step = 1
        for month_index in 1:12
            last_step = first_step + month_days[month_index] * 24 * time_steps_per_hour - 1
            @test all(cost -> isapprox(cost, monthly_costs[month_index] / REopt.KWH_PER_MMBTU),
                fuel_costs[first_step:last_step])
            first_step = last_step + 1
        end
    end
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

    finalize(backend(m1)); empty!(m1)
    finalize(backend(m2)); empty!(m2)
    GC.gc()
end

###############   Existing CHP Net Load Adjustment and Sizing   ###################
@testset "CHP Existing KW" begin
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
        s_existing.chps[1].supplementary_firing_installed_cost_per_mmbtu_per_hour * r_existing["CHP"]["size_supplemental_firing_mmbtu_per_hour"]

    @test r_existing["CHP"]["initial_capital_costs"] ≈ expected_capex atol=1e-2

    bau_s = REopt.BAUScenario(s_existing)
    @test length(bau_s.chps) == 1
    @test bau_s.chps[1].existing_kw == 100.0
    @test bau_s.chps[1].supplementary_firing_installed_cost_per_mmbtu_per_hour == 0.0

    bau_inputs = REopt.BAUInputs(p_existing)
    @test bau_inputs.max_sizes[chp_name] == 100.0
    @test bau_inputs.min_sizes[chp_name] == 100.0
    @test bau_inputs.cap_cost_slope[chp_name] == 0.0

    finalize(backend(m)); empty!(m); GC.gc()
end

###############   CHP Binary Creation Tests    ###################
# Tests to verify that binCHPIsOnInTS is only created when needed

function chp_binary_test_data()
    data = JSON.parsefile("./scenarios/chp_unavailability_outage.json")
    data["PV"]["production_factor_series"] = zeros(8760)
    return data
end

@testset "CHP Binary Creation Tests" begin
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

        finalize(backend(m)); empty!(m); GC.gc()
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

        finalize(backend(m)); empty!(m); GC.gc()
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

        finalize(backend(m)); empty!(m); GC.gc()
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

        finalize(backend(m)); empty!(m); GC.gc()
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

        finalize(backend(m)); empty!(m); GC.gc()
    end

    @testset "CHP with supplementary firing (binary SHOULD be created)" begin
        data = chp_binary_test_data()
        data["CHP"]["min_turn_down_fraction"] = 0.3
        data["CHP"]["electric_efficiency_full_load"] = 0.35
        data["CHP"]["electric_efficiency_half_load"] = 0.35
        data["CHP"]["thermal_efficiency_full_load"] = 0.45
        data["CHP"]["thermal_efficiency_half_load"] = 0.45
        data["CHP"]["om_cost_per_hr_per_kw_rated"] = 0.0
        data["CHP"]["supplementary_firing_max_ratio"] = 1.2
        delete!(data, "ElectricUtility")
        data["ElectricUtility"] = Dict("net_metering_limit_kw" => 0.0, "co2_from_avert" => true)

        s = Scenario(data)
        inputs = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        build_reopt!(m, inputs)

        @test haskey(m.obj_dict, :binCHPIsOnInTS)

        finalize(backend(m)); empty!(m); GC.gc()
    end

    @testset "CHP supplementary firing requires a positive min_turn_down_fraction" begin
        # Supplementary firing is only allowed while the prime mover is running, which is enforced
        # through binCHPIsOnInTS and min_turn_down_fraction. A min_turn_down_fraction of zero would
        # let the CHP be "on" while producing nothing, so it is rejected up front.
        data = chp_binary_test_data()
        data["CHP"]["min_turn_down_fraction"] = 0.0
        data["CHP"]["supplementary_firing_max_ratio"] = 1.2
        @test_throws ArgumentError Scenario(data)
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

    m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.05))
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

    prod_matching_input_data = deepcopy(input_data)
    prod_matching_input_data["ElectricLoad"]["loads_kw"] = fill(200.0, 8760)
    prod_matching_input_data["CHP"]["min_turn_down_fraction"] = 0.0
    prod_matching_input_data["CHP"]["follow_electrical_load"] = true
    prod_matching_input_data["CHP"]["production_factor_series"] = vcat(repeat([0.5], 4380), repeat([1.0], 4380))
    prod_matching_s = Scenario(prod_matching_input_data)
    prod_matching_p = REoptInputs(prod_matching_s)
    @test prod_matching_s.chps[1].follow_electrical_load

    m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
    prod_matching_results = run_reopt(m, prod_matching_p)
    chp_name = prod_matching_s.chps[1].name
    chp_size_kw = prod_matching_results[chp_name]["size_kw"]
    expected_chp_output = [
        chp_size_kw * prod_matching_p.production_factor[chp_name, ts]
        for ts in prod_matching_p.time_steps
    ]
    actual_chp_output = prod_matching_results[chp_name]["electric_production_series_kw"]
    @test maximum(abs.(actual_chp_output .- expected_chp_output)) <= 1.0e-3

    first_half_avg = sum(actual_chp_output[1:4380]) / 4380
    second_half_avg = sum(actual_chp_output[4381:8760]) / 4380
    # Avg output is less than average of prod factor because of unavailability from maintenance periods
    @test first_half_avg < 0.5 * chp_size_kw
    @test second_half_avg < 1.0 * chp_size_kw

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

@testset "CHP Supplementary firing framework" begin
    function run_supplementary_following_case(label; supplementary_efficiency, follow_heating_load, supplementary_ratio=1 + 2.66,
            supplementary_installed_cost_per_mmbtu_per_hour=10 * REopt.KWH_PER_MMBTU, min_turn_down_fraction=0.25)
        data = JSON.parsefile("./scenarios/supplementary_following.json")
        data["CHP"]["supplementary_firing_installed_cost_per_mmbtu_per_hour"] = supplementary_installed_cost_per_mmbtu_per_hour
        data["CHP"]["supplementary_firing_max_ratio"] = supplementary_ratio
        data["CHP"]["supplementary_firing_efficiency"] = supplementary_efficiency
        data["CHP"]["follow_heating_load"] = follow_heating_load
        # Supplementary firing requires a positive min_turn_down_fraction so that binCHPIsOnInTS
        # cannot be 1 while the prime mover produces nothing.
        data["CHP"]["min_turn_down_fraction"] = min_turn_down_fraction

        m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
        m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => 0.01))
        s = Scenario(data)
        inputs = REoptInputs(s)
        chp_name = s.chps[1].name
        results = run_reopt([m1, m2], inputs)
        # m2 holds the optimal (non-BAU) model; BAU has no CHP decision variables
        supplementary_thermal_series_mmbtu_per_hour = [
            value(m2[:dvSupplementaryThermalProduction][chp_name, ts]) / REopt.KWH_PER_MMBTU
            for ts in inputs.time_steps
        ]

        finalize(backend(m1))
        empty!(m1)
        finalize(backend(m2))
        empty!(m2)
        GC.gc()

        return (; results, supplementary_ratio, supplementary_thermal_series_mmbtu_per_hour)
    end

    economic_below = run_supplementary_following_case(
        "Economic supplementary sizing below boiler efficiency";
        supplementary_efficiency=0.88,
        follow_heating_load=false
    )

    economic_above = run_supplementary_following_case(
        "Economic supplementary sizing above boiler efficiency";
        supplementary_efficiency=0.95,
        follow_heating_load=false
    )

    follow_heating = run_supplementary_following_case(
        "Heating load following with supplementary sizing within max ratio";
        supplementary_efficiency=0.88,
        follow_heating_load=true
    )

    @test economic_above.results["CHP"]["size_supplemental_firing_mmbtu_per_hour"] > 0.0
    @test economic_below.results["CHP"]["size_supplemental_firing_mmbtu_per_hour"] <= economic_above.results["CHP"]["size_supplemental_firing_mmbtu_per_hour"] + 1.0e-6
    @test follow_heating.results["CHP"]["size_supplemental_firing_mmbtu_per_hour"] > 0.0
    @test sum(follow_heating.results["ExistingBoiler"]["thermal_to_load_series_mmbtu_per_hour"]) <
          sum(economic_below.results["ExistingBoiler"]["thermal_to_load_series_mmbtu_per_hour"])
    max_total_to_unfired_ratio = follow_heating.supplementary_ratio
    actual_total_to_unfired_ratio = follow_heating.results["CHP"]["size_supplementary_firing_ratio"]
    @test actual_total_to_unfired_ratio <= max_total_to_unfired_ratio + 1.0e-6
    @test actual_total_to_unfired_ratio >= 1.0 - 1.0e-6
    @test all(
        supp <= 1.0e-6 || elec > 1.0e-6 for
        (elec, supp) in zip(
            follow_heating.results["CHP"]["electric_production_series_kw"],
            follow_heating.supplementary_thermal_series_mmbtu_per_hour
        )
    )

    # Supplementary firing must be zero whenever the prime mover is not producing. The min turndown
    # constraint forces binCHPIsOnInTS to 0 when rated production is 0, which in turn zeroes out
    # supplementary firing.
    off_state_data = JSON.parsefile("./scenarios/supplementary_following.json")
    off_state_data["CHP"]["supplementary_firing_installed_cost_per_mmbtu_per_hour"] = 10 * REopt.KWH_PER_MMBTU
    off_state_data["CHP"]["supplementary_firing_max_ratio"] = 1 + 2.66
    off_state_data["CHP"]["supplementary_firing_efficiency"] = 0.88
    off_state_data["CHP"]["min_turn_down_fraction"] = 0.25
    m_off = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
    s_off = Scenario(off_state_data)
    inputs_off = REoptInputs(s_off)
    build_reopt!(m_off, inputs_off)
    chp_name_off = s_off.chps[1].name
    for ts in inputs_off.time_steps
        fix(m_off[:dvRatedProduction][chp_name_off, ts], 0.0, force=true)
    end
    @objective(m_off, Max, sum(m_off[:dvSupplementaryThermalProduction][chp_name_off, ts] for ts in inputs_off.time_steps))
    optimize!(m_off)
    @test termination_status(m_off) == JuMP.MOI.OPTIMAL
    @test objective_value(m_off) ≈ 0.0 atol = 1.0e-6

    finalize(backend(m_off))
    empty!(m_off)
    GC.gc()
end

@testset "Numeric boolean inputs" begin
    @test REopt.dictkeys_tosymbols(Dict("off_grid_flag" => 0.0))[:off_grid_flag] === false
    @test REopt.dictkeys_tosymbols(Dict("off_grid_flag" => 1.0))[:off_grid_flag] === true
    @test_throws ArgumentError REopt.dictkeys_tosymbols(Dict("off_grid_flag" => 2.0))
end

@testset "Dual Fuel CHP" begin

    @testset "Present worth factors for a fuel switch" begin
        n1, n2, d = 5, 7, 0.083
        esc1, esc2 = 0.034, 0.02
        pwf1, pwf2 = REopt.annuity_split_periods(n1, n2, esc1, esc2, d)

        # Each price escalates from year 1 and is discounted from year 1, whichever period it falls in
        @test isapprox(pwf1, sum(((1 + esc1) / (1 + d))^n for n in 1:n1), atol=1e-4)
        @test isapprox(pwf2, sum(((1 + esc2) / (1 + d))^n for n in (n1 + 1):(n1 + n2)), atol=1e-4)

        # With a single escalation rate (e.g. the emissions $/tonne escalation), the two periods must add up to
        # the unsplit annuity, so a switch can't change the cost of anything that doesn't depend on the fuel
        pwf1_equal, pwf2_equal = REopt.annuity_split_periods(n1, n2, 0.042, 0.042, d)
        @test isapprox(pwf1_equal + pwf2_equal, REopt.annuity(n1 + n2, 0.042, d), rtol=1e-12)

        # Fuel 2 never reached within the analysis period
        @test REopt.annuity_split_periods(n1, 0, esc1, esc2, d)[2] == 0.0
    end

    @testset "Fuel cost escalation rate precedence" begin
        financial_rate = 0.034
        p = (s = (financial = (chp_fuel_cost_escalation_rate_fraction = financial_rate,),),)

        # No CHP-level rates: both fuels use the Financial rate
        chp = REopt.CHP(; fuel_cost_per_mmbtu=5.0)
        @test REopt.chp_fuel_cost_escalation_rates(p, chp) == (financial_rate, financial_rate)

        # CHP-level fuel rate overrides the Financial rate, and fuel 2 inherits it
        chp = REopt.CHP(; fuel_cost_per_mmbtu=5.0, fuel_cost_escalation_rate_fraction=0.01)
        @test REopt.chp_fuel_cost_escalation_rates(p, chp) == (0.01, 0.01)

        # A fuel 2 rate applies only to fuel 2
        chp = REopt.CHP(; fuel_cost_per_mmbtu=5.0, fuel_cost_escalation_rate_fraction=0.01, fuel2_cost_escalation_rate_fraction=-0.02)
        @test REopt.chp_fuel_cost_escalation_rates(p, chp) == (0.01, -0.02)

        # Without a fuel rate, a fuel 2 rate still leaves fuel 1 on the Financial rate
        chp = REopt.CHP(; fuel_cost_per_mmbtu=5.0, fuel2_cost_escalation_rate_fraction=-0.02)
        @test REopt.chp_fuel_cost_escalation_rates(p, chp) == (financial_rate, -0.02)
    end

    @testset "Time steps grouped by period" begin
        days = REopt.get_time_steps_by_period("day", 2017)
        @test length(days) == 365 && all(length.(days) .== 24)
        @test reduce(vcat, days) == collect(1:8760)

        # 365 days is 52 full weeks plus a final day
        weeks = REopt.get_time_steps_by_period("week", 2017)
        @test length(weeks) == 53 && all(length.(weeks[1:52]) .== 168) && length(weeks[53]) == 24
        @test reduce(vcat, weeks) == collect(1:8760)

        months = REopt.get_time_steps_by_period("month", 2017)
        @test length.(months) == 24 .* [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

        # Sub-hourly time steps
        days_15min = REopt.get_time_steps_by_period("day", 2017; time_steps_per_hour=4)
        @test length(days_15min) == 365 && all(length.(days_15min) .== 96)

        # An hourly limit is a rate limit on each time step, not a volume limit over groups of time steps
        @test_throws ArgumentError REopt.get_time_steps_by_period("hour", 2017)
    end

    # The validation and default tests build CHPs directly (without a Scenario), since only the fuel inputs matter
    chp_inputs(; kwargs...) = merge(Dict{String,Any}("fuel_cost_per_mmbtu" => 5.0, "prime_mover" => "recip_engine", "max_kw" => 1000.0),
                                    Dict{String,Any}(string(k) => v for (k, v) in kwargs))
    build_chp(d) = REopt.CHP(d; sector="commercial/industrial", federal_procurement_type="")

    @testset "Input validation and defaults" begin
        # Cannot combine the long-term fuel switch with a fuel limit
        @test_throws ArgumentError build_chp(chp_inputs(fuel2_switch_start_year=6, fuel2_cost_per_mmbtu=8.0, fuel_max_period="hour", fuel_max_mmbtu_per_period=2.0))

        # fuel_max_period and fuel_max_mmbtu_per_period must be set together, and the period must be an allowed value
        @test_throws ArgumentError build_chp(chp_inputs(fuel_max_period="week"))
        @test_throws ArgumentError build_chp(chp_inputs(fuel_max_mmbtu_per_period=2.0))
        @test_throws ArgumentError build_chp(chp_inputs(fuel_max_period="quarter", fuel_max_mmbtu_per_period=500.0))
        @test_throws ArgumentError build_chp(chp_inputs(fuel2_cost_per_mmbtu=8.0, fuel2_switch_start_year=0))

        # fuel2_type indicates dual fuel and requires fuel2_cost_per_mmbtu
        @test_throws ArgumentError build_chp(chp_inputs(fuel2_type="propane"))

        # Any other fuel2 input without fuel2_type defaults fuel2_type to natural_gas, with natural_gas defaults
        for fuel2_input in [Dict(:fuel2_cost_per_mmbtu => 8.0, :fuel2_switch_start_year => 6),
                            Dict(:fuel2_cost_per_mmbtu => 8.0, :fuel_max_period => "hour", :fuel_max_mmbtu_per_period => 3.0),
                            Dict(:fuel2_cost_per_mmbtu => 8.0, :fuel2_cost_escalation_rate_fraction => 0.01, :fuel2_switch_start_year => 6)]
            chp = build_chp(chp_inputs(; fuel2_input...))
            @test chp.fuel2_type == "natural_gas"
            @test chp.fuel2_renewable_energy_fraction == REopt.FUEL_DEFAULTS["fuel_renewable_energy_fraction"]["natural_gas"]
            @test chp.fuel2_emissions_factor_lb_CO2_per_mmbtu == REopt.FUEL_DEFAULTS["emissions_factor_lb_CO2_per_mmbtu"]["natural_gas"]
        end
        # ... which then requires the cost
        @test_throws ArgumentError build_chp(chp_inputs(fuel2_switch_start_year=6))

        # Fuel 2 would never be used without a fuel limit or a fuel switch
        @test_throws ArgumentError build_chp(chp_inputs(fuel2_type="propane", fuel2_cost_per_mmbtu=8.0))
        @test_throws ArgumentError build_chp(chp_inputs(fuel2_cost_per_mmbtu=8.0))

        # A fuel switch is not allowed with an existing CHP, since the BAU emissions would not reflect the switch
        @test_throws ArgumentError build_chp(chp_inputs(existing_kw=500.0, fuel2_switch_start_year=6, fuel2_cost_per_mmbtu=8.0))
        chp = build_chp(chp_inputs(existing_kw=500.0, fuel_max_period="hour", fuel_max_mmbtu_per_period=3.0, fuel2_cost_per_mmbtu=8.0))
        @test chp.existing_kw == 500.0

        # An explicit fuel2_type determines the fuel2 defaults
        chp = build_chp(chp_inputs(fuel2_type="propane", fuel2_cost_per_mmbtu=8.0, fuel2_switch_start_year=6))
        @test chp.fuel2_emissions_factor_lb_CO2_per_mmbtu == REopt.FUEL_DEFAULTS["emissions_factor_lb_CO2_per_mmbtu"]["propane"]

        # A fuel limit alone is a cap on the CHP fuel use, not dual fuel
        chp = build_chp(chp_inputs(fuel_max_period="hour", fuel_max_mmbtu_per_period=3.0))
        @test isnothing(chp.fuel2_type) && isnothing(chp.fuel2_cost_per_mmbtu)
        @test chp.fuel_max_period == "hour" && chp.fuel_max_mmbtu_per_period == 3.0
    end

    @testset "Custom fuel types" begin
        custom_fuel_inputs = Dict(
            "fuel_cost_escalation_rate_fraction" => 0.01,
            "fuel_renewable_energy_fraction" => 0.4,
            "emissions_factor_lb_CO2_per_mmbtu" => 101.0,
            "emissions_factor_lb_NOx_per_mmbtu" => 0.11,
            "emissions_factor_lb_SO2_per_mmbtu" => 0.012,
            "emissions_factor_lb_PM25_per_mmbtu" => 0.013,
        )
        custom_fuel2_inputs = Dict(
            "fuel2_cost_escalation_rate_fraction" => 0.02,
            "fuel2_renewable_energy_fraction" => 0.6,
            "fuel2_emissions_factor_lb_CO2_per_mmbtu" => 202.0,
            "fuel2_emissions_factor_lb_NOx_per_mmbtu" => 0.21,
            "fuel2_emissions_factor_lb_SO2_per_mmbtu" => 0.022,
            "fuel2_emissions_factor_lb_PM25_per_mmbtu" => 0.023,
        )
        all_custom_inputs = merge(custom_fuel_inputs, custom_fuel2_inputs)
        d_custom = merge(chp_inputs(fuel_type="custom", fuel2_type="custom", fuel2_cost_per_mmbtu=8.0, fuel2_switch_start_year=6), all_custom_inputs)

        # Custom fuel 1 and fuel 2 use the provided values, not fuel type defaults
        chp = build_chp(deepcopy(d_custom))
        @test chp.fuel_type == "custom" && chp.fuel2_type == "custom"
        for (k, v) in all_custom_inputs
            @test getproperty(chp, Symbol(k)) == v
        end

        # A custom fuel requires its escalation rate and emissions factor inputs, but not the renewable fraction
        for k in keys(all_custom_inputs)
            d_missing = deepcopy(d_custom)
            delete!(d_missing, k)
            if occursin("renewable_energy_fraction", k)
                chp = build_chp(d_missing)
                @test getproperty(chp, Symbol(k)) == 0.0
            else
                @test_throws ArgumentError build_chp(d_missing)
            end
        end

        # All of the input errors are reported together in a single error
        d_errors = chp_inputs(fuel_type="custom", fuel2_type="custom")
        err = try build_chp(d_errors); nothing catch e e end
        @test err isa ArgumentError
        for fragment in ["CHP.fuel_type \"custom\"", "CHP.fuel2_cost_per_mmbtu is required", "CHP.fuel2_type \"custom\""]
            @test occursin(fragment, err.msg)
        end
    end

    # The optimization tests use a flat 1000 kW electric load, no heating load, and a CHP with the same electric efficiency
    # at all loads and no unavailability, so the CHP runs at full load in every time step and its fuel use, size and costs
    # can be calculated by hand. All of the inputs that determine them (rates, costs, efficiencies, emissions factors) are
    # set in chp_dual_fuel.json or here, rather than relying on defaults.
    load_kw = 1000.0
    electric_efficiency = 0.34  # full and half load, in chp_dual_fuel.json
    kwh_per_mmbtu = REopt.KWH_PER_MMBTU
    fuel1_cost_per_mmbtu = 5.0  # in chp_dual_fuel.json
    fuel2_cost_per_mmbtu = 8.0
    co2_lb_per_mmbtu_fuel1 = 100.0  # in chp_dual_fuel.json
    co2_lb_per_mmbtu_fuel2 = 200.0
    full_load_fuel_mmbtu_per_hour = load_kw / electric_efficiency / kwh_per_mmbtu  # fuel needed to serve the whole load
    thermal_efficiency = 0.45  # full and half load, in chp_dual_fuel.json
    # Optional heating load, served by the CHP and an existing boiler: the load is a boiler fuel load, so the thermal load is
    # that times the boiler efficiency. It is larger than the CHP thermal output, so all of the CHP thermal output is used.
    heating_fuel_load_mmbtu_per_hour = 6.0
    boiler_efficiency = 0.8
    boiler_fuel_cost_per_mmbtu = 10.0
    boiler_lb_per_mmbtu = Dict("CO2" => 120.0, "NOx" => 0.2, "SO2" => 0.002, "PM25" => 0.01)

    function chp_dual_fuel_inputs(; fuel2=true, heating=false)
        d = JSON.parsefile("./scenarios/chp_dual_fuel.json")
        d["ElectricLoad"] = Dict("loads_kw" => fill(load_kw, 8760), "year" => 2017)
        if heating
            d["SpaceHeatingLoad"] = Dict("fuel_loads_mmbtu_per_hour" => fill(heating_fuel_load_mmbtu_per_hour, 8760), "year" => 2017)
            d["ExistingBoiler"] = Dict(
                "efficiency" => boiler_efficiency,
                "fuel_type" => "natural_gas",
                "fuel_cost_per_mmbtu" => boiler_fuel_cost_per_mmbtu,
                "fuel_renewable_energy_fraction" => 0.0,
                [("emissions_factor_lb_$(k)_per_mmbtu" => v) for (k, v) in boiler_lb_per_mmbtu]...
            )
        end
        if fuel2
            d["CHP"]["fuel2_type"] = "natural_gas"
            d["CHP"]["fuel2_cost_per_mmbtu"] = fuel2_cost_per_mmbtu
            d["CHP"]["fuel2_emissions_factor_lb_CO2_per_mmbtu"] = co2_lb_per_mmbtu_fuel2
        end
        return d
    end

    # Returns the Scenario, REoptInputs, the optimal model and its results, and the BAU model if requested
    function solve_chp_dual_fuel(d; with_bau=false)
        s = Scenario(d)
        p = REoptInputs(s)
        m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
        if with_bau
            m_bau = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results = run_reopt([m_bau, m], p)
        else
            m_bau = nothing
            results = run_reopt(m, p)
        end
        return s, p, m, results, m_bau
    end

    function finalize_models(models...)
        for m in models
            isnothing(m) && continue
            finalize(backend(m))
            empty!(m)
        end
        GC.gc()
    end

    @testset "Rate-limited fuel 1 with fuel 2" begin
        max_fuel1_mmbtu_per_hour = 4.0
        d = chp_dual_fuel_inputs()
        d["CHP"]["fuel_max_period"] = "hour"
        d["CHP"]["fuel_max_mmbtu_per_period"] = max_fuel1_mmbtu_per_hour
        s, p, m, results, _ = solve_chp_dual_fuel(d)
        r = results["CHP"]
        analysis_years = s.financial.analysis_years
        tax_rate = s.financial.offtaker_tax_rate_fraction

        # Fuel 1 is burned at its limit in every hour and fuel 2 supplies the rest of the fuel needed to serve the load
        fuel1_kwh = [value(m[:dvFuelUsageFuel1]["CHP", ts]) for ts in p.time_steps]
        fuel2_kwh = [value(m[:dvFuelUsageFuel2]["CHP", ts]) for ts in p.time_steps]
        @test all(isapprox.(fuel1_kwh, max_fuel1_mmbtu_per_hour * kwh_per_mmbtu, rtol=1e-5))
        @test all(isapprox.(fuel2_kwh, (full_load_fuel_mmbtu_per_hour - max_fuel1_mmbtu_per_hour) * kwh_per_mmbtu, rtol=1e-5))

        # The CHP is sized to the peak total fuel use: size_kw = electric efficiency x peak fuel (kW), which serves the load
        peak_fuel_kw = maximum(fuel1_kwh .+ fuel2_kwh)
        @test r["size_kw"] ≈ electric_efficiency * peak_fuel_kw rtol=1e-4
        @test r["size_kw"] ≈ load_kw rtol=1e-4

        # Annual fuel use: the combined total, less fuel 2's, is fuel 1's
        fuel1_mmbtu = max_fuel1_mmbtu_per_hour * 8760
        fuel2_mmbtu = (full_load_fuel_mmbtu_per_hour - max_fuel1_mmbtu_per_hour) * 8760
        @test r["annual_fuel2_consumption_mmbtu"] ≈ fuel2_mmbtu rtol=1e-4
        @test r["annual_fuel_consumption_mmbtu"] - r["annual_fuel2_consumption_mmbtu"] ≈ fuel1_mmbtu rtol=1e-4
        @test r["annual_fuel_consumption_mmbtu"] ≈ full_load_fuel_mmbtu_per_hour * 8760 rtol=1e-4

        # Year-one fuel costs
        @test r["year_one_fuel2_cost_before_tax"] ≈ fuel2_mmbtu * fuel2_cost_per_mmbtu rtol=1e-4
        @test r["year_one_fuel_cost_before_tax"] ≈ fuel1_mmbtu * fuel1_cost_per_mmbtu + fuel2_mmbtu * fuel2_cost_per_mmbtu rtol=1e-4

        # Lifecycle fuel costs: both fuels burn every year and escalate from year 1 at the Financial CHP fuel rate (fuel 2
        # inherits fuel 1's rate)
        pwf_fuel = REopt.annuity(analysis_years, s.financial.chp_fuel_cost_escalation_rate_fraction, s.financial.offtaker_discount_rate_fraction)
        @test r["pwf_fuel"] ≈ pwf_fuel atol=1e-4
        @test r["pwf_fuel2"] ≈ pwf_fuel atol=1e-4
        @test r["lifecycle_fuel2_cost_after_tax"] ≈ fuel2_mmbtu * fuel2_cost_per_mmbtu * pwf_fuel * (1 - tax_rate) rtol=1e-4
        @test r["lifecycle_fuel_cost_after_tax"] ≈ (fuel1_mmbtu * fuel1_cost_per_mmbtu + fuel2_mmbtu * fuel2_cost_per_mmbtu) * pwf_fuel * (1 - tax_rate) rtol=1e-4

        # Onsite emissions blend the emissions factors of the two fuels
        @test results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"] ≈
            (fuel1_mmbtu * co2_lb_per_mmbtu_fuel1 + fuel2_mmbtu * co2_lb_per_mmbtu_fuel2) * REopt.TONNE_PER_LB rtol=1e-4

        # Present worth factors in the Financial results
        f = results["Financial"]
        discount_rate = s.financial.offtaker_discount_rate_fraction
        @test f["pwf_e"] ≈ REopt.annuity(analysis_years, s.financial.elec_cost_escalation_rate_fraction, discount_rate) atol=1e-4
        @test f["pwf_om"] ≈ REopt.annuity(analysis_years, s.financial.om_cost_escalation_rate_fraction, s.financial.owner_discount_rate_fraction) atol=1e-4
        @test f["pwf_offtaker"] ≈ REopt.annuity(analysis_years, 0.0, discount_rate) atol=1e-4
        @test f["pwf_owner"] ≈ REopt.annuity(analysis_years, 0.0, s.financial.owner_discount_rate_fraction) atol=1e-4
        @test f["third_party_factor"] == 1.0
        @test !any(haskey(f, k) for k in ["pwf_fuel_existing_boiler", "pwf_fuel_boiler", "pwf_fuel_generator"])  # not modeled
        for emissions_type in ["CO2", "NOx", "SO2", "PM25"]
            @test haskey(f, "pwf_emissions_cost_$(emissions_type)_grid")
            @test haskey(f, "pwf_emissions_cost_$(emissions_type)_onsite")
            @test haskey(f, "pwf_grid_emissions_$(emissions_type)")
        end

        finalize_models(m)
    end

    @testset "Volume-limited fuel 1 (monthly) with fuel 2" begin
        max_fuel1_mmbtu_per_month = 1500.0  # below the fuel needed in any month, even February
        d = chp_dual_fuel_inputs()
        d["CHP"]["fuel_max_period"] = "month"
        d["CHP"]["fuel_max_mmbtu_per_period"] = max_fuel1_mmbtu_per_month
        s, p, m, results, _ = solve_chp_dual_fuel(d)
        r = results["CHP"]

        # In every month, fuel 1 is burned at its limit and fuel 2 supplies the rest of the fuel needed to serve the load
        fuel1_kwh = [value(m[:dvFuelUsageFuel1]["CHP", ts]) for ts in p.time_steps]
        fuel2_kwh = [value(m[:dvFuelUsageFuel2]["CHP", ts]) for ts in p.time_steps]
        monthly_time_steps = REopt.get_monthly_time_steps(s.electric_load.year; time_steps_per_hour=s.settings.time_steps_per_hour)
        for month_time_steps in monthly_time_steps
            @test sum(fuel1_kwh[month_time_steps]) / kwh_per_mmbtu ≈ max_fuel1_mmbtu_per_month rtol=1e-4
            @test sum(fuel2_kwh[month_time_steps]) / kwh_per_mmbtu ≈
                full_load_fuel_mmbtu_per_hour * length(month_time_steps) - max_fuel1_mmbtu_per_month rtol=1e-4
        end

        # The CHP is sized to the peak total fuel use, which serves the load
        peak_fuel_kw = maximum(fuel1_kwh .+ fuel2_kwh)
        @test r["size_kw"] ≈ electric_efficiency * peak_fuel_kw rtol=1e-4
        @test r["size_kw"] ≈ load_kw rtol=1e-4

        fuel1_mmbtu = 12 * max_fuel1_mmbtu_per_month
        fuel2_mmbtu = full_load_fuel_mmbtu_per_hour * 8760 - fuel1_mmbtu
        @test r["annual_fuel2_consumption_mmbtu"] ≈ fuel2_mmbtu rtol=1e-4
        @test r["annual_fuel_consumption_mmbtu"] - r["annual_fuel2_consumption_mmbtu"] ≈ fuel1_mmbtu rtol=1e-4
        @test r["year_one_fuel_cost_before_tax"] ≈ fuel1_mmbtu * fuel1_cost_per_mmbtu + fuel2_mmbtu * fuel2_cost_per_mmbtu rtol=1e-4

        finalize_models(m)
    end

    @testset "Rate-limited fuel 1 without fuel 2" begin
        # Without fuel2_type, the limit is a hard cap on the CHP fuel use, which also limits the CHP size
        max_fuel1_mmbtu_per_hour = 2.0
        d = chp_dual_fuel_inputs(fuel2=false)
        d["CHP"]["fuel_max_period"] = "hour"
        d["CHP"]["fuel_max_mmbtu_per_period"] = max_fuel1_mmbtu_per_hour
        s, p, m, results, _ = solve_chp_dual_fuel(d)
        r = results["CHP"]

        # No second fuel, so no fuel 2 results and no fuel 1 / fuel 2 split variables
        @test !haskey(r, "annual_fuel2_consumption_mmbtu")
        @test !haskey(m, :dvFuelUsageFuel1)

        # The CHP burns the maximum fuel in every hour and is sized to the peak fuel use: size_kw = efficiency x peak fuel
        fuel_kwh = [value(m[:dvFuelUsage]["CHP", ts]) for ts in p.time_steps]
        @test all(isapprox.(fuel_kwh, max_fuel1_mmbtu_per_hour * kwh_per_mmbtu, rtol=1e-5))
        @test r["size_kw"] ≈ electric_efficiency * maximum(fuel_kwh) rtol=1e-4
        @test r["size_kw"] ≈ electric_efficiency * max_fuel1_mmbtu_per_hour * kwh_per_mmbtu rtol=1e-4
        @test r["size_kw"] < load_kw  # the grid supplies the rest of the load

        fuel_mmbtu = max_fuel1_mmbtu_per_hour * 8760
        pwf_fuel = REopt.annuity(s.financial.analysis_years, s.financial.chp_fuel_cost_escalation_rate_fraction, s.financial.offtaker_discount_rate_fraction)
        @test r["annual_fuel_consumption_mmbtu"] ≈ fuel_mmbtu rtol=1e-4
        @test r["year_one_fuel_cost_before_tax"] ≈ fuel_mmbtu * fuel1_cost_per_mmbtu rtol=1e-4
        @test r["pwf_fuel"] ≈ pwf_fuel atol=1e-4
        @test r["lifecycle_fuel_cost_after_tax"] ≈ fuel_mmbtu * fuel1_cost_per_mmbtu * pwf_fuel * (1 - s.financial.offtaker_tax_rate_fraction) rtol=1e-4
        @test results["Site"]["annual_emissions_from_fuelburn_tonnes_CO2"] ≈ fuel_mmbtu * co2_lb_per_mmbtu_fuel1 * REopt.TONNE_PER_LB rtol=1e-4

        finalize_models(m)
    end

    @testset "Long-term fuel switch with a heating load and a zero-emission fuel 2" begin
        switch_year = 6
        fuel2_escalation_rate = 0.02  # differs from fuel 1's rate (the Financial CHP fuel rate)
        co2_cost_per_tonne = 100.0
        co2_cost_escalation_rate = 0.04
        d = chp_dual_fuel_inputs(heating=true)
        d["CHP"]["fuel2_switch_start_year"] = switch_year
        # A custom fuel 2 with no emissions, e.g. renewable hydrogen, with its escalation rate, emissions factors and renewable fraction
        d["CHP"]["fuel2_type"] = "custom"
        d["CHP"]["fuel2_cost_escalation_rate_fraction"] = fuel2_escalation_rate
        d["CHP"]["fuel2_renewable_energy_fraction"] = 1.0
        for k in ["CO2", "NOx", "SO2", "PM25"]
            d["CHP"]["fuel2_emissions_factor_lb_$(k)_per_mmbtu"] = 0.0
        end
        # Monetize CO2 emissions in the objective
        d["Settings"]["include_climate_in_objective"] = true
        d["Financial"]["CO2_cost_per_tonne"] = co2_cost_per_tonne
        d["Financial"]["CO2_cost_escalation_rate_fraction"] = co2_cost_escalation_rate
        s, p, m, results, m_bau = solve_chp_dual_fuel(d; with_bau=true)
        r = results["CHP"]
        site = results["Site"]
        analysis_years = s.financial.analysis_years
        discount_rate = s.financial.offtaker_discount_rate_fraction
        esc1 = s.financial.chp_fuel_cost_escalation_rate_fraction
        tax_rate = s.financial.offtaker_tax_rate_fraction
        n_fuel1_years = switch_year - 1
        n_fuel2_years = analysis_years - n_fuel1_years
        year_one_fuel_mmbtu = full_load_fuel_mmbtu_per_hour * 8760  # the same every year

        # The dispatch is the same every year, so the CHP size is as in the other tests
        fuel_kwh = [value(m[:dvFuelUsage]["CHP", ts]) for ts in p.time_steps]
        @test r["size_kw"] ≈ electric_efficiency * maximum(fuel_kwh) rtol=1e-4
        @test r["size_kw"] ≈ load_kw rtol=1e-4
        @test r["annual_fuel_consumption_mmbtu"] ≈ year_one_fuel_mmbtu rtol=1e-4

        # Year one burns only fuel 1: year_one_fuel2_cost_* is the hypothetical year-one cost of fuel 2
        @test r["annual_fuel2_consumption_mmbtu"] == 0.0
        @test r["year_one_fuel_cost_before_tax"] ≈ year_one_fuel_mmbtu * fuel1_cost_per_mmbtu rtol=1e-4
        @test r["year_one_fuel2_cost_before_tax"] ≈ year_one_fuel_mmbtu * fuel2_cost_per_mmbtu rtol=1e-4
        @test r["year_one_fuel2_cost_after_tax"] ≈ r["year_one_fuel2_cost_before_tax"] * (1 - tax_rate) rtol=1e-6

        # Lifecycle fuel cost, built year by year: both prices are today's-dollars inputs that escalate from year 1 at their own
        # rates, fuel 1 is used in years 1..(switch year - 1) and fuel 2 from the switch year on, and every year is discounted from year 1
        expected_lifecycle_before_tax = sum(
            year_one_fuel_mmbtu * (yr < switch_year ? fuel1_cost_per_mmbtu * (1 + esc1)^yr : fuel2_cost_per_mmbtu * (1 + fuel2_escalation_rate)^yr) /
            (1 + discount_rate)^yr
            for yr in 1:analysis_years
        )
        @test r["lifecycle_fuel_cost_after_tax"] ≈ expected_lifecycle_before_tax * (1 - tax_rate) rtol=1e-5

        # The fuel present worth factors are split at the switch year
        pwf_fuel1, pwf_fuel2 = REopt.annuity_split_periods(n_fuel1_years, n_fuel2_years, esc1, fuel2_escalation_rate, discount_rate)
        @test r["pwf_fuel"] ≈ pwf_fuel1 atol=1e-4
        @test r["pwf_fuel2"] ≈ pwf_fuel2 atol=1e-4
        @test r["lifecycle_fuel2_cost_after_tax"] ≈ year_one_fuel_mmbtu * fuel2_cost_per_mmbtu * pwf_fuel2 * (1 - tax_rate) rtol=1e-5

        # Heating load: the CHP thermal output is used in full and the existing boiler serves the rest of the thermal load
        chp_thermal_mmbtu_per_hour = full_load_fuel_mmbtu_per_hour * thermal_efficiency
        thermal_load_mmbtu_per_hour = heating_fuel_load_mmbtu_per_hour * boiler_efficiency
        @test chp_thermal_mmbtu_per_hour < thermal_load_mmbtu_per_hour
        @test r["annual_thermal_production_mmbtu"] ≈ chp_thermal_mmbtu_per_hour * 8760 rtol=1e-4
        @test r["annual_thermal_curtailed_mmbtu"] ≈ 0.0 atol=1e-3
        boiler_fuel_mmbtu = (thermal_load_mmbtu_per_hour - chp_thermal_mmbtu_per_hour) / boiler_efficiency * 8760
        @test results["ExistingBoiler"]["annual_fuel_consumption_mmbtu"] ≈ boiler_fuel_mmbtu rtol=1e-4

        # Lifecycle onsite emissions: fuel 1's emissions factor applies only in the years before the switch and fuel 2 has no
        # emissions, while the boiler burns fuel in every year. Annual emissions are averaged over the analysis period.
        chp_lb_per_mmbtu_fuel1 = Dict("CO2" => co2_lb_per_mmbtu_fuel1, "NOx" => 0.1, "SO2" => 0.01, "PM25" => 0.02)  # in chp_dual_fuel.json
        for emissions_type in ["CO2", "NOx", "SO2", "PM25"]
            chp_lifecycle_lb = year_one_fuel_mmbtu * chp_lb_per_mmbtu_fuel1[emissions_type] * n_fuel1_years
            boiler_lifecycle_lb = boiler_fuel_mmbtu * boiler_lb_per_mmbtu[emissions_type] * analysis_years
            # The results are rounded to 2 decimals (lifecycle) and 3 decimals (annual)
            @test site["lifecycle_emissions_from_fuelburn_tonnes_$(emissions_type)"] ≈ (chp_lifecycle_lb + boiler_lifecycle_lb) * REopt.TONNE_PER_LB rtol=1e-4 atol=0.01
            @test site["annual_emissions_from_fuelburn_tonnes_$(emissions_type)"] ≈ (chp_lifecycle_lb + boiler_lifecycle_lb) * REopt.TONNE_PER_LB / analysis_years rtol=1e-4 atol=0.001
        end

        # Compared to the BAU, which only has the boiler, the CO2 reduction comes from the CHP fuel 1 years
        bau_boiler_fuel_mmbtu = heating_fuel_load_mmbtu_per_hour * 8760
        expected_lifecycle_co2_lb = year_one_fuel_mmbtu * co2_lb_per_mmbtu_fuel1 * n_fuel1_years + boiler_fuel_mmbtu * boiler_lb_per_mmbtu["CO2"] * analysis_years
        bau_lifecycle_co2_lb = bau_boiler_fuel_mmbtu * boiler_lb_per_mmbtu["CO2"] * analysis_years
        @test site["lifecycle_emissions_reduction_CO2_fraction"] ≈ 1 - expected_lifecycle_co2_lb / bau_lifecycle_co2_lb rtol=1e-4

        # The monetized CO2 emissions use the same year-by-year emissions, escalated and discounted from year 1
        expected_climate_cost = sum(
            ((yr < switch_year ? year_one_fuel_mmbtu * co2_lb_per_mmbtu_fuel1 : 0.0) + boiler_fuel_mmbtu * boiler_lb_per_mmbtu["CO2"]) *
            REopt.TONNE_PER_LB * co2_cost_per_tonne * (1 + co2_cost_escalation_rate)^yr / (1 + discount_rate)^yr
            for yr in 1:analysis_years
        )
        @test results["Financial"]["lifecycle_emissions_cost_climate"] ≈ expected_climate_cost rtol=1e-4

        # The pro forma cash flows are consistent with the lifecycle cost, which also includes the monetized emissions
        optimal_lcc = results["Financial"]["lcc"] - results["Financial"]["lifecycle_emissions_cost_climate"]
        optimal_cashflow_sum = -1*sum(results["Financial"]["offtaker_discounted_annual_free_cashflows"])
        @test isapprox(optimal_lcc, optimal_cashflow_sum, rtol=0.001)

        # A switch year beyond the analysis period never reaches fuel 2 (the dispatch does not depend on the switch year)
        d["CHP"]["fuel2_switch_start_year"] = analysis_years + 1
        breakdown = REopt.chp_fuel_cost_breakdown(m, REoptInputs(Scenario(d)), "CHP")
        @test breakdown.pwf_fuel2 == 0.0 && breakdown.lifecycle_fuel2 == 0.0 && breakdown.yr1_equivalent_fuel2 == 0.0
        @test breakdown.pwf_fuel1 ≈ REopt.annuity(analysis_years, esc1, discount_rate) rtol=1e-12
        @test breakdown.lifecycle_fuel1 ≈ year_one_fuel_mmbtu * fuel1_cost_per_mmbtu * REopt.annuity(analysis_years, esc1, discount_rate) rtol=1e-4

        # A switch in year 1 burns only fuel 2 in year one, so the year-one cost is fuel 2's and fuel 1 is never used
        d["CHP"]["fuel2_switch_start_year"] = 1
        breakdown = REopt.chp_fuel_cost_breakdown(m, REoptInputs(Scenario(d)), "CHP")
        @test breakdown.yr1_fuel1 == 0.0 && breakdown.pwf_fuel1 == 0.0 && breakdown.lifecycle_fuel1 == 0.0
        @test breakdown.yr1_fuel2 ≈ year_one_fuel_mmbtu * fuel2_cost_per_mmbtu rtol=1e-4
        @test breakdown.pwf_fuel2 ≈ REopt.annuity(analysis_years, fuel2_escalation_rate, discount_rate) rtol=1e-12
        @test breakdown.lifecycle_fuel2 ≈ year_one_fuel_mmbtu * fuel2_cost_per_mmbtu * breakdown.pwf_fuel2 rtol=1e-4

        finalize_models(m, m_bau)
    end
end
