# using Revise
using JuMP
using HiGHS
# using Xpress
using JSON
using REopt
using Logging
using DotEnv
DotEnv.load!()

# ============================================================================
# SOLVER CONFIGURATION - Change solver here
# ============================================================================
const USE_XPRESS = false  # Set to true to use Xpress

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

# Create a minimal test scenario with OUU
scenario = Dict(
    "Site" => Dict(
        "latitude" => 39.7407,
        "longitude" => -105.1694,
        "min_resil_time_steps" => 4
    ),
    "ElectricLoad" => Dict(
        "doe_reference_name" => "LargeHotel",
        "annual_kwh" => 2000000.0,
        "uncertainty" => Dict(
            "enabled" => true,
            "method" => "time_invariant",
            "deviation_fractions" => [-0.1, 0.0, 0.1],
            "deviation_probabilities" => [0.25, 0.50, 0.25]
        ),
        "critical_load_fraction" => 1.0
    ),
    # "ElectricUtility" => Dict(
    #     "outage_start_time_steps" => [19, 5214],
    #     "outage_durations" => [4]
    # ),
    "ElectricTariff" => Dict(
        "urdb_label" => "5ed6c1a15457a3367add15ae"
        # "blended_annual_energy_rate" => 0.08,
        # "blended_annual_demand_rate" => 10.0
    ),
    "PV" => Dict(
        "max_kw" => 2000.0,
        "production_uncertainty" => Dict(
            "enabled" => true,
            "method" => "time_invariant",
            "deviation_fractions" => [-0.2, 0.0],# 0.2],
            "deviation_probabilities" => [0.25, 0.75],# 0.25]
        )
    ),
    "ElectricStorage" => Dict(
        "max_kw" => 2000.0,
        "max_kwh" => 10000.0
    )
)

# Write scenario to JSON file
# open("scenarios/ouu_outages.json", "w") do f
#     JSON.print(f, scenario, 4)
# end

println("\n" * "="^60)
println("Testing OUU Implementation")
println("="^60)

# try
# Suppress info/warning messages temporarily
original_logger = Logging.global_logger()
Logging.global_logger(Logging.SimpleLogger(stderr, Logging.Error))

# Create model with logging enabled
m = create_model(verbose=true)

print("Building Scenario... ")
s = Scenario(scenario)
println("✓")

print("Building REoptInputs... ")
inputs = REoptInputs(s)
println("✓")
println("  └─ n_scenarios: ", inputs.n_scenarios)
println("  └─ probabilities: ", round.(inputs.scenario_probabilities, digits=4))

print("Building optimization model... ")
build_reopt!(m, inputs)
println("✓")
println("  └─ Variables: ", num_variables(m))
println("  └─ Constraints: ", num_constraints(m, AffExpr, MOI.EqualTo{Float64}))

print("Solving... ")
optimize!(m)

# Restore logger
Logging.global_logger(original_logger)

if termination_status(m) == MOI.OPTIMAL
    println("✓")
    println("\n✅ SUCCESS: Model solved to optimality")
    println("  └─ Objective value: \$", round(objective_value(m), digits=2))
    
    print("\nProcessing results... ")
    results = reopt_results(m, inputs)
    println("✓")
    
    println("\n📊 Key Results:")
    println("  PV:")
    if haskey(results, "PV")
        println("    └─ Size: ", results["PV"]["size_kw"], " kW")
        println("    └─ Annual production: ", results["PV"]["annual_energy_produced_kwh"], " kWh")
    end
    
    println("  Battery:")
    if haskey(results, "ElectricStorage")
        println("    └─ Power: ", results["ElectricStorage"]["size_kw"], " kW")
        println("    └─ Energy: ", results["ElectricStorage"]["size_kwh"], " kWh")
    end
    
    println("  Grid:")
    if haskey(results, "ElectricUtility")
        println("    └─ Annual energy: ", results["ElectricUtility"]["annual_energy_supplied_kwh"], " kWh")
    end
else
    println("✗")
    println("\n⚠️  Model status: ", termination_status(m))
end

# catch e
#     println("\n" * "="^60)
#     println("❌ ERROR ENCOUNTERED")
#     println("="^60)
#     showerror(stdout, e)
#     println("\n")
#     for (exc, bt) in Base.catch_stack()
#         showerror(stdout, exc, bt)
#         println()
#     end
#     println("="^60)
# end
