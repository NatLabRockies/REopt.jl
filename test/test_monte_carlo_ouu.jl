# using Revise
using JuMP
using HiGHS
# using Xpress
using JSON
using REopt
using Logging
using DotEnv
# using PlotlyJS  # Commented out for GitHub Actions
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

println("\n" * "="^80)
println("Testing Monte Carlo vs Discrete OUU Methods")
println("="^80)

# Suppress info/warning messages
original_logger = Logging.global_logger()
Logging.global_logger(Logging.SimpleLogger(stderr, Logging.Error))

# ============================================================================
# Test 0: Baseline (No Uncertainty) with BAU
# ============================================================================
println("\n" * "─"^80)
println("Test 0: Baseline (No Uncertainty)")
println("─"^80)
println("Single scenario with no uncertainty, comparing BAU vs technology optimization")

scenario_baseline = JSON.parsefile("scenarios/ouu_base.json")

print("Building scenario... ")
s_baseline = Scenario(scenario_baseline)
println("✓")

print("Building REoptInputs... ")
inputs_baseline = REoptInputs(s_baseline)
println("✓")
println("  └─ Number of scenarios: ", inputs_baseline.n_scenarios)

# Create BAU and technology optimization models
m_bau = create_model()

m_tech = create_model()

print("Building and solving models (BAU + Technology Optimization)... ")
results_baseline = run_reopt([m_bau, m_tech], inputs_baseline)
println("✓")

if termination_status(m_bau) == MOI.OPTIMAL && termination_status(m_tech) == MOI.OPTIMAL
    println("\n📊 Baseline Results:")
    println("  BAU (Business as Usual):")
    println("    └─ Objective value: \$", round(objective_value(m_bau), digits=2))
    println("    └─ Grid energy supplied: ", round(results_baseline["ElectricUtility"]["annual_energy_supplied_kwh_bau"], digits=1), " kWh")
    println("\n  Technology Optimal:")
    println("    └─ Objective value: \$", round(objective_value(m_tech), digits=2))
    println("    └─ Grid energy supplied: ", round(results_baseline["ElectricUtility"]["annual_energy_supplied_kwh"], digits=1), " kWh")
    println("    └─ PV size: ", round(results_baseline["PV"]["size_kw"], digits=1), " kW")
    println("    └─ Battery power: ", round(results_baseline["ElectricStorage"]["size_kw"], digits=1), " kW")
    println("    └─ Battery energy: ", round(results_baseline["ElectricStorage"]["size_kwh"], digits=1), " kWh")
    
    savings = objective_value(m_bau) - objective_value(m_tech)
    println("\n  Technology Savings: \$", round(savings, digits=2), " (", round(savings/objective_value(m_bau)*100, digits=2), "%)")
else
    println("\n⚠️  Baseline model status - BAU: ", termination_status(m_bau), ", Tech: ", termination_status(m_tech))
end

# ============================================================================
# Test 1: Time-Invariant Method (Original Implementation)
# ============================================================================
println("\n" * "─"^80)
println("Test 1: Time-Invariant Method")
println("─"^80)
println("Creates 3 load scenarios × 3 PV scenarios = 9 total scenarios")
println("Each scenario has uniform deviation across all timesteps")

scenario_invariant = JSON.parsefile("scenarios/ouu_base.json")
scenario_invariant["ElectricLoad"]["uncertainty"] = Dict(
    "enabled" => true,
    "method" => "time_invariant",
    "deviation_fractions" => [-0.1, 0.0, 0.1],
    "deviation_probabilities" => [0.25, 0.50, 0.25]
)
scenario_invariant["PV"]["production_uncertainty"] = Dict(
    "enabled" => true,
    "method" => "time_invariant",
    "deviation_fractions" => [-0.2, 0.0, 0.2],
    "deviation_probabilities" => [0.25, 0.50, 0.25]
)

print("Building scenario... ")
s_invariant = Scenario(scenario_invariant)
println("✓")

print("Building REoptInputs... ")
inputs_invariant = REoptInputs(s_invariant)
println("✓")
println("  └─ Number of scenarios: ", inputs_invariant.n_scenarios)
println("  └─ Scenario probabilities: ", round.(inputs_invariant.scenario_probabilities[1:min(10, end)], digits=4))

m_invariant = create_model()

m_invariant_bau = create_model()

print("Building and solving models (BAU + Technology Optimization)... ")
results_invariant = run_reopt([m_invariant_bau, m_invariant], inputs_invariant)
println("✓")

if termination_status(m_invariant) == MOI.OPTIMAL
    println("\n📊 Time-Invariant Method Results:")
    println("  Technology Optimal:")
    println("    └─ Objective value: \$", round(objective_value(m_invariant), digits=2))
    println("    └─ Grid energy supplied: ", round(results_invariant["ElectricUtility"]["annual_energy_supplied_kwh"], digits=1), " kWh")
    println("    └─ PV size: ", round(results_invariant["PV"]["size_kw"], digits=1), " kW")
    println("    └─ Battery power: ", round(results_invariant["ElectricStorage"]["size_kw"], digits=1), " kW")
    println("    └─ Battery energy: ", round(results_invariant["ElectricStorage"]["size_kwh"], digits=1), " kWh")
    if termination_status(m_invariant_bau) == MOI.OPTIMAL
        println("\n  BAU:")
        println("    └─ Objective value: \$", round(objective_value(m_invariant_bau), digits=2))
        println("    └─ Grid energy supplied: ", round(results_invariant["ElectricUtility"]["annual_energy_supplied_kwh_bau"], digits=1), " kWh")
        savings = objective_value(m_invariant_bau) - objective_value(m_invariant)
        println("    └─ Technology Savings: \$", round(savings, digits=2), " (", round(savings/objective_value(m_invariant_bau)*100, digits=2), "%)")
    end
else
    println("\n⚠️  Time-Invariant model status: ", termination_status(m_invariant))
end

# ============================================================================
# Test 2: Monte Carlo Method (New Implementation)
# ============================================================================
println("\n" * "─"^80)
println("Test 2: Monte Carlo Method")
println("─"^80)
println("Creates 9 scenarios (3 load samples × 3 PV samples)")
println("Each scenario has timestep-varying deviations sampled from distribution")

scenario_mc = JSON.parsefile("scenarios/ouu_base.json")
scenario_mc["ElectricLoad"]["uncertainty"] = Dict(
    "enabled" => true,
    "method" => "discrete",
    "deviation_fractions" => [-0.1, 0.0, 0.1],
    "deviation_probabilities" => [0.25, 0.50, 0.25],
    "n_samples" => 3  # Each sample has different deviation per timestep
)
scenario_mc["PV"]["production_uncertainty"] = Dict(
    "enabled" => true,
    "method" => "discrete",
    "deviation_fractions" => [-0.2, 0.0, 0.2],
    "deviation_probabilities" => [0.25, 0.50, 0.25],
    "n_samples" => 3
)

print("Building scenario... ")
s_mc = Scenario(scenario_mc)
println("✓")

print("Building REoptInputs... ")
inputs_mc = REoptInputs(s_mc)
println("✓")
println("  └─ Number of scenarios: ", inputs_mc.n_scenarios)
println("  └─ Scenario probabilities (first 5): ", round.(inputs_mc.scenario_probabilities[1:min(5, end)], digits=4))
println("  └─ All equal? ", all(x -> isapprox(x, inputs_mc.scenario_probabilities[1], atol=1e-10), inputs_mc.scenario_probabilities))

m_mc = create_model()

m_mc_bau = create_model()

print("Building and solving models (BAU + Technology Optimization)... ")
results_mc = run_reopt([m_mc_bau, m_mc], inputs_mc)
println("✓")

if termination_status(m_mc) == MOI.OPTIMAL
    println("\n📊 Monte Carlo Method Results:")
    println("  Technology Optimal:")
    println("    └─ Objective value: \$", round(objective_value(m_mc), digits=2))
    println("    └─ Grid energy supplied: ", round(results_mc["ElectricUtility"]["annual_energy_supplied_kwh"], digits=1), " kWh")
    println("    └─ PV size: ", round(results_mc["PV"]["size_kw"], digits=1), " kW")
    println("    └─ Battery power: ", round(results_mc["ElectricStorage"]["size_kw"], digits=1), " kW")
    println("    └─ Battery energy: ", round(results_mc["ElectricStorage"]["size_kwh"], digits=1), " kWh")
    if termination_status(m_mc_bau) == MOI.OPTIMAL
        println("\n  BAU:")
        println("    └─ Objective value: \$", round(objective_value(m_mc_bau), digits=2))
        println("    └─ Grid energy supplied: ", round(results_mc["ElectricUtility"]["annual_energy_supplied_kwh_bau"], digits=1), " kWh")
        savings = objective_value(m_mc_bau) - objective_value(m_mc)
        println("    └─ Technology Savings: \$", round(savings, digits=2), " (", round(savings/objective_value(m_mc_bau)*100, digits=2), "%)")
    end
else
    println("\n⚠️  Monte Carlo model status: ", termination_status(m_mc))
end

# ============================================================================
# Comparison
# ============================================================================
if termination_status(m_invariant) == MOI.OPTIMAL && termination_status(m_mc) == MOI.OPTIMAL
    println("\n" * "─"^80)
    println("Comparison:")
    println("─"^80)
    
    pv_diff = results_mc["PV"]["size_kw"] - results_invariant["PV"]["size_kw"]
    batt_kw_diff = results_mc["ElectricStorage"]["size_kw"] - results_invariant["ElectricStorage"]["size_kw"]
    batt_kwh_diff = results_mc["ElectricStorage"]["size_kwh"] - results_invariant["ElectricStorage"]["size_kwh"]
    cost_diff = objective_value(m_mc) - objective_value(m_invariant)
    
    println("  Δ PV size: ", round(pv_diff, digits=1), " kW (", round(pv_diff/results_invariant["PV"]["size_kw"]*100, digits=1), "%)")
    println("  Δ Battery power: ", round(batt_kw_diff, digits=1), " kW (", round(batt_kw_diff/results_invariant["ElectricStorage"]["size_kw"]*100, digits=1), "%)")
    println("  Δ Battery energy: ", round(batt_kwh_diff, digits=1), " kWh (", round(batt_kwh_diff/results_invariant["ElectricStorage"]["size_kwh"]*100, digits=1), "%)")
    println("  Δ Cost: \$", round(cost_diff, digits=2), " (", round(cost_diff/objective_value(m_invariant)*100, digits=2), "%)")
    
    println("\n💡 Key Insight:")
    println("  Monte Carlo captures timestep-level uncertainty, while discrete assumes")
    println("  all timesteps move together. This can lead to different optimal sizing.")
    
    # ============================================================================
    # Visualization: Compare scenario profiles
    # ============================================================================
    println("\n" * "─"^80)
    println("Plotting scenario profiles...")
    println("─"^80)
    
    # Plot first 168 hours (1 week) for visibility
    # Plotting code commented out for GitHub Actions (PlotlyJS not available)
    # plot_hours = 1:min(8760, length(inputs_invariant.time_steps))
    # 
    # # Find baseline scenario (zero deviation) in time_invariant - should be scenario 2 with deviation=0.0
    # baseline_scenario_id = 5  # Middle scenario with 0.0 deviation
    # mc_scenario_id = 2  # First Monte Carlo scenario
    # 
    # # Create load comparison plot
    # load_trace1 = PlotlyJS.scatter(
    #     x=collect(plot_hours),
    #     y=inputs_discrete.loads_kw_by_scenario[baseline_scenario_id][plot_hours],
    #     mode="lines",
    #     name="Baseline (No Deviation)",
    #     line=attr(width=2, color="blue")
    # )
    # load_trace2 = PlotlyJS.scatter(
    #     x=collect(plot_hours),
    #     y=inputs_mc.loads_kw_by_scenario[mc_scenario_id][plot_hours],
    #     mode="lines",
    #     name="Discrete Monte Carlo Sample",
    #     line=attr(width=2, color="red", dash="dash")
    # )
    # 
    # load_layout = PlotlyJS.Layout(
    #     title="Load Profile Comparison (First Week)",
    #     xaxis_title="Hour",
    #     yaxis_title="Load (kW)",
    #     hovermode="x unified"
    # )
    # 
    # load_plot = PlotlyJS.plot([load_trace1, load_trace2], load_layout)
    # 
    # # Create PV production comparison plot
    # pv_trace1 = PlotlyJS.scatter(
    #     x=collect(plot_hours),
    #     y=inputs_discrete.production_factor_by_scenario[baseline_scenario_id]["PV"][plot_hours],
    #     mode="lines",
    #     name="Baseline (No Deviation)",
    #     line=attr(width=2, color="blue")
    # )
    # pv_trace2 = PlotlyJS.scatter(
    #     x=collect(plot_hours),
    #     y=inputs_mc.production_factor_by_scenario[mc_scenario_id]["PV"][plot_hours],
    #     mode="lines",
    #     name="Discrete Monte Carlo Sample",
    #     line=attr(width=2, color="red", dash="dash")
    # )
    # 
    # pv_layout = PlotlyJS.Layout(
    #     title="PV Production Profile Comparison (First Week)",
    #     xaxis_title="Hour",
    #     yaxis_title="Production Factor",
    #     hovermode="x unified"
    # )
    # 
    # pv_plot = PlotlyJS.plot([pv_trace1, pv_trace2], pv_layout)
    # 
    # # Save plots
    # PlotlyJS.savefig(load_plot, "load_comparison.html")
    # PlotlyJS.savefig(pv_plot, "pv_comparison.html")
    # println("  └─ Plots saved to load_comparison.html and pv_comparison.html")
end

# Restore logger
Logging.global_logger(original_logger)

println("\n" * "="^80)
println("✅ Tests Complete")
println("="^80)
