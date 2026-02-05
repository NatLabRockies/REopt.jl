# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.
# Test suite for Optimization Under Uncertainty (OUU) implementation
# Tests validate expected behavior and impacts of uncertainty on results
# using Revise
using Test
using JuMP
using HiGHS
# using Xpress
using JSON
using REopt
using DotEnv
DotEnv.load!()

# ============================================================================
# SOLVER CONFIGURATION - Change solver here
# ============================================================================
const USE_XPRESS = false  # Set to false to use HiGHS

"""
Helper function to create model with configured solver
"""
function create_model(mip_gap::Float64=0.05; verbose::Bool=false)
    if USE_XPRESS
        m = Model(Xpress.Optimizer)
        set_optimizer_attribute(m, "OUTPUTLOG", verbose ? 1 : 0)
        set_optimizer_attribute(m, "MIPRELSTOP", mip_gap)
    else
        m = Model(HiGHS.Optimizer)
        set_optimizer_attribute(m, "output_flag", verbose)
        set_optimizer_attribute(m, "log_to_console", verbose)
        set_optimizer_attribute(m, "mip_rel_gap", mip_gap)
    end
    return m
end

"""
Helper function to create base scenario dict for OUU testing
"""
function create_base_ouu_scenario(;
    load_uncertainty_enabled=false,
    load_deviation=0.0,
    pv_uncertainty_enabled=false,
    pv_deviation=0.0,
    annual_kwh=1000000.0,
    pv_max_kw=500.0
)
    scenario = Dict{String, Any}(
        "Site" => Dict{String, Any}(
            "latitude" => 39.7407,
            "longitude" => -105.1694
        ),
        "ElectricLoad" => Dict{String, Any}(
            "annual_kwh" => annual_kwh,
            "doe_reference_name" => "LargeOffice"
        ),
        "ElectricTariff" => Dict{String, Any}(
            "blended_annual_energy_rate" => 0.10,
            "blended_annual_demand_rate" => 0.0  # Disable demand charges for simplicity
        ),
        "PV" => Dict{String, Any}(
            "max_kw" => pv_max_kw
        ),
        "ElectricStorage" => Dict{String, Any}(
            "max_kw" => 500.0,
            "max_kwh" => 2000.0
        )
    )
    
    # Add load uncertainty if requested
    if load_uncertainty_enabled
        scenario["ElectricLoad"]["uncertainty"] = Dict{String, Any}(
            "enabled" => true,
            "deviation_fractions" => [-load_deviation, 0.0, load_deviation],
            "deviation_probabilities" => [0.25, 0.50, 0.25]
        )
    end
    
    # Add PV uncertainty if requested
    if pv_uncertainty_enabled
        scenario["PV"]["production_uncertainty"] = Dict{String, Any}(
            "enabled" => true,
            "deviation_fractions" => [-pv_deviation, 0.0, pv_deviation],
            "deviation_probabilities" => [0.25, 0.50, 0.25]
        )
    end
    
    return scenario
end

"""
Helper function to run optimization and return key results
"""
function run_ouu_test(scenario_dict)
    m = create_model()
    
    s = Scenario(scenario_dict)
    inputs = REoptInputs(s)
    results = run_reopt(m, inputs)
    
    return (
        inputs = inputs,
        results = results,
        pv_size = results["PV"]["size_kw"],
        battery_power = results["ElectricStorage"]["size_kw"],
        battery_energy = results["ElectricStorage"]["size_kwh"],
        objective = results["Financial"]["lcc"]
    )
end
    

@testset verbose=true "OUU Foundation Tests" begin
    
    @testset "Scenario Generation" begin
        @testset "Load Scenarios - Single Uncertainty" begin
            scenario = create_base_ouu_scenario(
                load_uncertainty_enabled=true,
                load_deviation=0.1
            )
            
            s = Scenario(scenario)
            inputs = REoptInputs(s)
            
            # Should create 3 scenarios (low, mid, high)
            @test inputs.n_scenarios == 3
            
            # Probabilities should sum to 1
            @test sum(inputs.scenario_probabilities) ≈ 1.0 atol=1e-6
            
            # Probabilities should match specification
            @test inputs.scenario_probabilities ≈ [0.25, 0.50, 0.25]
            
            # Check load scaling
            nominal_load = s.electric_load.loads_kw
            for ts in 1:length(nominal_load)
                @test inputs.loads_kw_by_scenario[1][ts] ≈ nominal_load[ts] * 0.9 atol=1e-6
                @test inputs.loads_kw_by_scenario[2][ts] ≈ nominal_load[ts] atol=1e-6
                @test inputs.loads_kw_by_scenario[3][ts] ≈ nominal_load[ts] * 1.1 atol=1e-6
            end
        end
        
        @testset "PV Scenarios - Single Uncertainty" begin
            scenario = create_base_ouu_scenario(
                pv_uncertainty_enabled=true,
                pv_deviation=0.2
            )
            
            s = Scenario(scenario)
            inputs = REoptInputs(s)
            
            # Should create 3 scenarios
            @test inputs.n_scenarios == 3
            @test sum(inputs.scenario_probabilities) ≈ 1.0
            
            # Check PV production factor scaling
            @test haskey(inputs.production_factor_by_scenario[1], "PV")
            
            # Get nominal factor from deterministic run
            scenario_det = create_base_ouu_scenario()
            s_det = Scenario(scenario_det)
            inputs_det = REoptInputs(s_det)
            nominal_pf = inputs_det.production_factor["PV", :]
            
            for ts in 1:length(nominal_pf)
                @test inputs.production_factor_by_scenario[1]["PV"][ts] ≈ nominal_pf[ts] * 0.8 atol=1e-6
                @test inputs.production_factor_by_scenario[2]["PV"][ts] ≈ nominal_pf[ts] atol=1e-6
                @test inputs.production_factor_by_scenario[3]["PV"][ts] ≈ nominal_pf[ts] * 1.2 atol=1e-6
            end
        end
        
        @testset "Combined Scenarios - Both Uncertainties" begin
            scenario = create_base_ouu_scenario(
                load_uncertainty_enabled=true,
                load_deviation=0.1,
                pv_uncertainty_enabled=true,
                pv_deviation=0.15
            )
            
            s = Scenario(scenario)
            inputs = REoptInputs(s)
            
            # Should create 9 combined scenarios
            @test inputs.n_scenarios == 9
            
            # Probabilities should sum to 1
            @test sum(inputs.scenario_probabilities) ≈ 1.0 atol=1e-6
            
            # Check joint probabilities (independence assumption)
            expected_probs = [
                0.25*0.25, 0.25*0.50, 0.25*0.25,  # Low load with low/mid/high PV
                0.50*0.25, 0.50*0.50, 0.50*0.25,  # Mid load
                0.25*0.25, 0.25*0.50, 0.25*0.25   # High load
            ]
            @test inputs.scenario_probabilities ≈ expected_probs atol=1e-6
        end
    end
    
    @testset "Uncertainty Impact on Sizing" begin
        @testset "Uncertainty Impact on Sizing and Cost" begin
            println("\n  Testing how uncertainty affects sizing and cost...")
            
            # Test with increasing load uncertainty
            deviations = [0.0, 0.05, 0.10, 0.20]
            pv_sizes = Float64[]
            battery_powers = Float64[]
            objectives = Float64[]
            
            for dev in deviations
                scenario = create_base_ouu_scenario(
                    load_uncertainty_enabled = (dev > 0),
                    load_deviation = dev,
                    annual_kwh = 1000000.0,
                    pv_max_kw = 1000.0
                )
                
                result = run_ouu_test(scenario)
                push!(pv_sizes, result.pv_size)
                push!(battery_powers, result.battery_power)
                push!(objectives, result.objective)
            end
            
            println("    Deviation | PV Size | Battery | Objective")
            for i in 1:length(deviations)
                println("    $(lpad(Int(deviations[i]*100), 3))%      | $(lpad(round(pv_sizes[i], digits=1), 7)) | $(lpad(round(battery_powers[i], digits=1), 7)) | \$$(round(objectives[i], digits=0))")
            end
            
            # Objective (expected cost) should be non-decreasing with uncertainty
            # (accounting for more scenarios can't decrease expected cost)
            for i in 2:length(objectives)
                @test objectives[i] >= objectives[i-1] - 10.0  # Small tolerance for numerical issues
            end
            
            # Sizing relationship is problem-dependent - just verify solutions are valid
            @test all(pv_sizes .>= 0.0)
            @test all(battery_powers .>= 0.0)
            
            # Print sizing trends for analysis
            println("\n    Sizing may increase, decrease, or stay similar depending on:")
            println("    - Electricity rate structure")
            println("    - Capital vs operating cost trade-offs")
            println("    - Probability distribution of scenarios")
        end
        
        @testset "Boundary Test: Zero Uncertainty = Deterministic" begin
            println("\n  Testing boundary condition (0% uncertainty = deterministic)...")
            
            # Deterministic scenario
            scenario_det = create_base_ouu_scenario(
                load_uncertainty_enabled=false,
                pv_uncertainty_enabled=false
            )
            result_det = run_ouu_test(scenario_det)
            
            # OUU with zero uncertainty
            scenario_ouu_zero = create_base_ouu_scenario(
                load_uncertainty_enabled=true,
                load_deviation=0.0,
                pv_uncertainty_enabled=true,
                pv_deviation=0.0
            )
            result_ouu_zero = run_ouu_test(scenario_ouu_zero)
            
            println("    Deterministic: PV=$(round(result_det.pv_size, digits=1)) kW, Battery=$(round(result_det.battery_power, digits=1)) kW")
            println("    OUU (0% dev):  PV=$(round(result_ouu_zero.pv_size, digits=1)) kW, Battery=$(round(result_ouu_zero.battery_power, digits=1)) kW")
            
            # Results should be very similar (allowing for numerical differences)
            @test result_ouu_zero.pv_size ≈ result_det.pv_size rtol=0.02
            @test result_ouu_zero.battery_power ≈ result_det.battery_power rtol=0.02
            @test result_ouu_zero.objective ≈ result_det.objective rtol=0.01
        end
        
        @testset "Economic Optimization: OUU vs Individual Scenarios" begin
            println("\n  Testing OUU economic optimization vs individual scenarios...")
            
            # Run OUU with combined uncertainty
            scenario_ouu = create_base_ouu_scenario(
                load_uncertainty_enabled=true,
                load_deviation=0.1,
                pv_uncertainty_enabled=true,
                pv_deviation=0.15,
                annual_kwh=1000000.0
            )
            result_ouu = run_ouu_test(scenario_ouu)
            
            # Run deterministic for worst case: High load + Low PV
            scenario_worst = create_base_ouu_scenario(
                annual_kwh=1100000.0  # 110% of base
            )
            scenario_worst["PV"]["max_kw"] = 500.0 * 0.85  # Effectively lower production
            result_worst = run_ouu_test(scenario_worst)
            
            # Best case: Low load + High PV
            scenario_best = create_base_ouu_scenario(
                annual_kwh=900000.0  # 90% of base
            )
            scenario_best["PV"]["max_kw"] = 500.0 * 1.15
            result_best = run_ouu_test(scenario_best)
            
            # Middle/expected case
            scenario_mid = create_base_ouu_scenario(
                annual_kwh=1000000.0
            )
            result_mid = run_ouu_test(scenario_mid)
            
            println("    Scenario      | PV Size | Battery | Cost")
            println("    Best case     | $(lpad(round(result_best.pv_size, digits=1), 7)) | $(lpad(round(result_best.battery_power, digits=1), 7)) | \$$(round(result_best.objective, digits=0))")
            println("    Expected case | $(lpad(round(result_mid.pv_size, digits=1), 7)) | $(lpad(round(result_mid.battery_power, digits=1), 7)) | \$$(round(result_mid.objective, digits=0))")
            println("    Worst case    | $(lpad(round(result_worst.pv_size, digits=1), 7)) | $(lpad(round(result_worst.battery_power, digits=1), 7)) | \$$(round(result_worst.objective, digits=0))")
            println("    OUU (robust)  | $(lpad(round(result_ouu.pv_size, digits=1), 7)) | $(lpad(round(result_ouu.battery_power, digits=1), 7)) | \$$(round(result_ouu.objective, digits=0))")
            
            # OUU sizing finds economic optimum - doesn't necessarily match any single scenario
            # Just verify it's within reasonable bounds
            @test result_ouu.pv_size >= min(result_best.pv_size, result_mid.pv_size, result_worst.pv_size) * 0.80
            @test result_ouu.pv_size <= max(result_best.pv_size, result_mid.pv_size, result_worst.pv_size) * 1.20
            
            println("\n    OUU finds economically optimal sizing that balances:")
            println("    - Capital costs (sizing decisions)")
            println("    - Expected operating costs (across all scenarios)")
            println("    - Probability-weighted performance")
        end
    end
    
    @testset "Uncertainty Impact on Costs" begin
        @testset "Expected Cost Relationship: OUU vs Deterministic" begin
            println("\n  Testing expected cost relationship...")
            
            # Deterministic (expected case only)
            scenario_det = create_base_ouu_scenario()
            result_det = run_ouu_test(scenario_det)
            
            # OUU with 10% uncertainty
            scenario_ouu = create_base_ouu_scenario(
                load_uncertainty_enabled=true,
                load_deviation=0.10,
                pv_uncertainty_enabled=true,
                pv_deviation=0.10
            )
            result_ouu = run_ouu_test(scenario_ouu)
            
            cost_increase = result_ouu.objective - result_det.objective
            cost_increase_pct = 100 * cost_increase / result_det.objective
            
            println("    Deterministic LCC: \$$(round(result_det.objective, digits=0))")
            println("    OUU LCC:          \$$(round(result_ouu.objective, digits=0))")
            println("    Difference:       \$$(round(cost_increase, digits=0)) ($(round(cost_increase_pct, digits=2))%)")
            
            # OUU expected cost typically >= deterministic cost at expected case
            # (must perform well across all scenarios, not just expected case)
            @test result_ouu.objective >= result_det.objective * 0.98  # Allow small tolerance
            
            println("\n    Note: OUU objective accounts for probability-weighted costs")
            println("    across all scenarios, while deterministic only considers")
            println("    the expected case. Difference represents value of robustness.")
        end
        
        @testset "Cost Scaling with Uncertainty Magnitude" begin
            println("\n  Testing cost scaling with uncertainty magnitude...")
            
            deviations = [0.05, 0.10, 0.15, 0.20]
            costs = Float64[]
            
            base_scenario = create_base_ouu_scenario()
            base_result = run_ouu_test(base_scenario)
            base_cost = base_result.objective
            
            for dev in deviations
                scenario = create_base_ouu_scenario(
                    load_uncertainty_enabled=true,
                    load_deviation=dev
                )
                result = run_ouu_test(scenario)
                push!(costs, result.objective)
            end
            
            println("    Deviation | LCC      | Premium vs Det")
            println("    Base (0%) | \$$(round(base_cost, digits=0)) | --")
            for i in 1:length(deviations)
                premium_pct = 100 * (costs[i] - base_cost) / base_cost
                println("    $(lpad(Int(deviations[i]*100), 3))%      | \$$(round(costs[i], digits=0)) | $(round(premium_pct, digits=2))%")
            end
            
            # Costs should increase monotonically
            for i in 2:length(costs)
                @test costs[i] >= costs[i-1]
            end
            
            # All OUU costs should exceed deterministic
            for cost in costs
                @test cost >= base_cost
            end
        end
    end
    
    @testset "Independent vs Combined Uncertainty" begin
        println("\n  Testing interaction of load and PV uncertainty...")
        
        # Only load uncertainty
        scenario_load = create_base_ouu_scenario(
            load_uncertainty_enabled=true,
            load_deviation=0.10
        )
        result_load = run_ouu_test(scenario_load)
        
        # Only PV uncertainty
        scenario_pv = create_base_ouu_scenario(
            pv_uncertainty_enabled=true,
            pv_deviation=0.10
        )
        result_pv = run_ouu_test(scenario_pv)
        
        # Both uncertainties
        scenario_both = create_base_ouu_scenario(
            load_uncertainty_enabled=true,
            load_deviation=0.10,
            pv_uncertainty_enabled=true,
            pv_deviation=0.10
        )
        result_both = run_ouu_test(scenario_both)
        
        println("    Scenario        | n_scen | PV Size | Battery | Cost")
        println("    Load only       | $(result_load.inputs.n_scenarios)      | $(lpad(round(result_load.pv_size, digits=1), 7)) | $(lpad(round(result_load.battery_power, digits=1), 7)) | \$$(round(result_load.objective, digits=0))")
        println("    PV only         | $(result_pv.inputs.n_scenarios)      | $(lpad(round(result_pv.pv_size, digits=1), 7)) | $(lpad(round(result_pv.battery_power, digits=1), 7)) | \$$(round(result_pv.objective, digits=0))")
        println("    Both            | $(result_both.inputs.n_scenarios)      | $(lpad(round(result_both.pv_size, digits=1), 7)) | $(lpad(round(result_both.battery_power, digits=1), 7)) | \$$(round(result_both.objective, digits=0))")
        
        # Scenarios should combine multiplicatively
        @test result_load.inputs.n_scenarios == 3
        @test result_pv.inputs.n_scenarios == 3
        @test result_both.inputs.n_scenarios == 9
        
        # Combined sizing should be at least as large as individual
        @test result_both.pv_size >= max(result_load.pv_size, result_pv.pv_size) * 0.95
        @test result_both.battery_power >= max(result_load.battery_power, result_pv.battery_power) * 0.95
        
        # Combined cost should exceed individual costs
        @test result_both.objective >= max(result_load.objective, result_pv.objective)
    end
    
    @testset "Probability Distribution Impact" begin
        println("\n  Testing different probability distributions...")
        
        # Symmetric distribution (baseline)
        scenario_sym = create_base_ouu_scenario(
            load_uncertainty_enabled=true,
            load_deviation=0.10
        )
        scenario_sym["ElectricLoad"]["uncertainty"]["deviation_probabilities"] = [0.25, 0.50, 0.25]
        result_sym = run_ouu_test(scenario_sym)
        
        # Pessimistic distribution (higher weight on high load)
        scenario_pess = create_base_ouu_scenario(
            load_uncertainty_enabled=true,
            load_deviation=0.10
        )
        scenario_pess["ElectricLoad"]["uncertainty"]["deviation_probabilities"] = [0.10, 0.40, 0.50]
        result_pess = run_ouu_test(scenario_pess)
        
        # Optimistic distribution (higher weight on low load)
        scenario_opt = create_base_ouu_scenario(
            load_uncertainty_enabled=true,
            load_deviation=0.10
        )
        scenario_opt["ElectricLoad"]["uncertainty"]["deviation_probabilities"] = [0.50, 0.40, 0.10]
        result_opt = run_ouu_test(scenario_opt)
        
        println("    Distribution | PV Size | Battery | Cost")
        println("    Symmetric    | $(lpad(round(result_sym.pv_size, digits=1), 7)) | $(lpad(round(result_sym.battery_power, digits=1), 7)) | \$$(round(result_sym.objective, digits=0))")
        println("    Pessimistic  | $(lpad(round(result_pess.pv_size, digits=1), 7)) | $(lpad(round(result_pess.battery_power, digits=1), 7)) | \$$(round(result_pess.objective, digits=0))")
        println("    Optimistic   | $(lpad(round(result_opt.pv_size, digits=1), 7)) | $(lpad(round(result_opt.battery_power, digits=1), 7)) | \$$(round(result_opt.objective, digits=0))")
        
        # Pessimistic should have larger sizing (hedging against high load)
        @test result_pess.pv_size >= result_opt.pv_size * 0.98  # May be close
        @test result_pess.battery_power >= result_opt.battery_power * 0.98
        
        # Pessimistic should have higher expected cost
        @test result_pess.objective >= result_opt.objective * 0.99
    end
    
    @testset "Backward Compatibility" begin
        println("\n  Testing backward compatibility (uncertainty disabled)...")
        
        # Scenario without uncertainty keys
        scenario_old = create_base_ouu_scenario()
        
        # Should not error
        s = Scenario(scenario_old)
        @test !s.load_uncertainty.enabled
        @test !s.production_uncertainty.enabled
        
        inputs = REoptInputs(s)
        @test inputs.n_scenarios == 1
        @test inputs.scenario_probabilities == [1.0]
        
        # Should produce valid results
        result = run_ouu_test(scenario_old)
        @test result.pv_size >= 0.0
        @test result.objective > 0.0
    end
end

println("\n" * "="^70)
println("✅ OUU Foundation Tests Complete")
println("="^70)
