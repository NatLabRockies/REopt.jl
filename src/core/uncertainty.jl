# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.

"""
    TimeSeriesUncertainty

Defines uncertainty parameters for time series data (loads, production factors, etc.).

# Fields
- `enabled::Bool`: Whether uncertainty is enabled
- `method::String`: Uncertainty method - "time_invariant", "discrete", "normal", or "uniform"
- `deviation_fractions::Array{<:Real,1}`: Array of fractional deviations from nominal (for time_invariant/discrete)
- `deviation_probabilities::Array{<:Real,1}`: Probability of each deviation (for time_invariant) or sampling distribution (for discrete), must sum to 1.0
- `n_samples::Int`: Number of samples to generate (used for discrete, normal, uniform)
- `mean::Union{Float64, Nothing}`: Mean of Normal distribution (for method="normal")
- `std::Union{Float64, Nothing}`: Standard deviation of Normal distribution (for method="normal")
- `lower_bound::Union{Float64, Nothing}`: Lower bound for Uniform distribution (for method="uniform")
- `upper_bound::Union{Float64, Nothing}`: Upper bound for Uniform distribution (for method="uniform")

# Example (Time-Invariant - fixed scenarios with same deviation across all timesteps)
```julia
TimeSeriesUncertainty(
    enabled=true,
    method="time_invariant",
    deviation_fractions=[-0.10, 0.0, 0.10],
    deviation_probabilities=[0.25, 0.50, 0.25]
)
```

# Example (Discrete - Monte Carlo sampling from discrete distribution at each timestep)
```julia
TimeSeriesUncertainty(
    enabled=true,
    method="discrete",
    deviation_fractions=[-0.10, 0.0, 0.10],
    deviation_probabilities=[0.25, 0.50, 0.25],
    n_samples=3
)
```

# Example (Normal - Monte Carlo sampling from Normal distribution at each timestep)
```julia
TimeSeriesUncertainty(
    enabled=true,
    method="normal",
    mean=0.0,
    std=0.15,
    n_samples=3
)
```

# Example (Uniform - Monte Carlo sampling from Uniform distribution at each timestep)
```julia
TimeSeriesUncertainty(
    enabled=true,
    method="uniform",
    lower_bound=-0.3,
    upper_bound=0.3,
    n_samples=3
)
```
"""
struct TimeSeriesUncertainty
    enabled::Bool
    method::String
    deviation_fractions::Array{<:Real,1}
    deviation_probabilities::Array{<:Real,1}
    n_samples::Int
    mean::Union{Float64, Nothing}
    std::Union{Float64, Nothing}
    lower_bound::Union{Float64, Nothing}
    upper_bound::Union{Float64, Nothing}
    
    function TimeSeriesUncertainty(;
        enabled::Bool = false,
        method::String = "time_invariant",
        deviation_fractions::Array{<:Real,1} = [-0.1, 0.0, 0.1],
        deviation_probabilities::Array{<:Real,1} = [0.25, 0.50, 0.25],
        n_samples::Int = 3,
        mean::Union{Float64, Nothing} = nothing,
        std::Union{Float64, Nothing} = nothing,
        lower_bound::Union{Float64, Nothing} = nothing,
        upper_bound::Union{Float64, Nothing} = nothing
    )
        # Validate method
        if !(method in ["time_invariant", "discrete", "normal", "uniform"])
            throw(@error("TimeSeriesUncertainty method must be 'time_invariant', 'discrete', 'normal', or 'uniform'"))
        end
        
        # Validate time_invariant/discrete parameters
        if method in ["time_invariant", "discrete"]
            if abs(sum(deviation_probabilities) - 1.0) > 1e-6
                throw(@error("TimeSeriesUncertainty deviation_probabilities must sum to 1.0"))
            end
            if length(deviation_fractions) != length(deviation_probabilities)
                throw(@error("TimeSeriesUncertainty deviation_fractions and deviation_probabilities must have the same length"))
            end
            if any(abs.(deviation_fractions) .> 1.0)
                throw(@error("TimeSeriesUncertainty deviation_fractions must be between -1 and 1"))
            end
        end
        
        # Validate that deviation_probabilities is not used for continuous distributions
        if method in ["normal", "uniform"] && deviation_probabilities != [0.25, 0.50, 0.25]
            throw(@error("TimeSeriesUncertainty deviation_probabilities should not be specified for method='$method'"))
        end
        
        # Validate normal distribution parameters
        if method == "normal"
            if isnothing(mean) || isnothing(std)
                throw(@error("TimeSeriesUncertainty method='normal' requires mean and std parameters"))
            end
            if std <= 0
                throw(@error("TimeSeriesUncertainty std must be positive for normal distribution"))
            end
        end
        
        # Validate uniform distribution parameters
        if method == "uniform"
            if isnothing(lower_bound) || isnothing(upper_bound)
                throw(@error("TimeSeriesUncertainty method='uniform' requires lower_bound and upper_bound parameters"))
            end
            if lower_bound >= upper_bound
                throw(@error("TimeSeriesUncertainty lower_bound must be less than upper_bound"))
            end
            if abs(lower_bound) > 1.0 || abs(upper_bound) > 1.0
                throw(@error("TimeSeriesUncertainty bounds must be between -1 and 1"))
            end
        end
        
        # Validate n_samples for sampling methods
        if method in ["discrete", "normal", "uniform"] && n_samples < 1
            throw(@error("TimeSeriesUncertainty n_samples must be at least 1 for sampling methods"))
        end
        
        new(enabled, method, deviation_fractions, deviation_probabilities, n_samples, mean, std, lower_bound, upper_bound)
    end
end


"""
    sample_deviation_from_distribution(deviation_fractions, deviation_probabilities)

Sample a single deviation value from the discrete probability distribution.

# Arguments
- `deviation_fractions::Array{<:Real, 1}`: Deviation values
- `deviation_probabilities::Array{<:Real, 1}`: Probabilities for each deviation

# Returns
- `deviation::Float64`: Sampled deviation value
"""
function sample_deviation_from_distribution(
    deviation_fractions::Array{<:Real, 1},
    deviation_probabilities::Array{<:Real, 1}
)
    # Create cumulative distribution
    cum_probs = cumsum(deviation_probabilities)
    
    # Sample uniform random number
    r = rand()
    
    # Find which bin it falls into
    for (idx, cum_prob) in enumerate(cum_probs)
        if r <= cum_prob
            return Float64(deviation_fractions[idx])
        end
    end
    
    # Fallback (should not reach here if probabilities sum to 1.0)
    return Float64(deviation_fractions[end])
end


"""
    sample_normal_deviation(mean, std)

Sample a deviation value from a Normal (Gaussian) distribution.

# Arguments
- `mean::Float64`: Mean of the distribution
- `std::Float64`: Standard deviation of the distribution

# Returns
- `deviation::Float64`: Sampled deviation value
"""
function sample_normal_deviation(mean::Float64, std::Float64)
    return randn() * std + mean
end


"""
    sample_uniform_deviation(lower_bound, upper_bound)

Sample a deviation value from a Uniform distribution.

# Arguments
- `lower_bound::Float64`: Lower bound of the distribution
- `upper_bound::Float64`: Upper bound of the distribution

# Returns
- `deviation::Float64`: Sampled deviation value
"""
function sample_uniform_deviation(lower_bound::Float64, upper_bound::Float64)
    return rand() * (upper_bound - lower_bound) + lower_bound
end


"""
    apply_sampled_deviations(nominal_values, n_samples, sampling_func)

Core sampling logic: apply random deviations to nominal values.

# Arguments
- `nominal_values::Array{<:Real, 1}`: Nominal values (loads or production factors)
- `n_samples::Int`: Number of scenario samples to generate
- `sampling_func::Function`: Function that returns a deviation when called

# Returns
- `scenarios::Dict{Int, Vector{Float64}}`: Sampled scenarios with deviations applied
"""
function apply_sampled_deviations(
    nominal_values::Array{<:Real, 1},
    n_samples::Int,
    sampling_func::Function
)
    n_timesteps = length(nominal_values)
    scenarios = Dict{Int, Vector{Float64}}()
    
    for sample_idx in 1:n_samples
        sampled_values = zeros(Float64, n_timesteps)
        for ts in 1:n_timesteps
            deviation = sampling_func()
            sampled_values[ts] = nominal_values[ts] * (1.0 + deviation)
        end
        scenarios[sample_idx] = sampled_values
    end
    
    return scenarios
end


"""
    generate_production_scenarios_generic(nominal_production_factor, n_samples, renewable_techs, sampling_func)

Generic production scenario generator - applies sampling to renewable techs only.

# Arguments
- `nominal_production_factor::Dict{String, Array{Float64, 1}}`: Nominal production factors by tech
- `n_samples::Int`: Number of samples to generate
- `renewable_techs::Array{String, 1}`: Technologies to apply uncertainty to
- `sampling_func::Function`: Function that returns a deviation when called

# Returns
- `scenarios::Dict{Int, Dict{String, Array{Float64, 1}}}`: Generated scenarios
- `probabilities::Array{Float64, 1}`: Equal probabilities for all scenarios
"""
function generate_production_scenarios_generic(
    nominal_production_factor::Dict{String, Array{Float64, 1}},
    n_samples::Int,
    renewable_techs::Array{String, 1},
    sampling_func::Function
)
    scenarios = Dict{Int, Dict{String, Vector{Float64}}}()
    
    for sample_idx in 1:n_samples
        scenarios[sample_idx] = Dict{String, Vector{Float64}}()
        
        for (tech, factors) in nominal_production_factor
            if tech in renewable_techs
                # Apply sampled deviations to this tech
                scenarios[sample_idx][tech] = apply_sampled_deviations(
                    factors, 1, sampling_func
                )[1]  # Get first (and only) sample
            else
                # No uncertainty for this tech
                scenarios[sample_idx][tech] = Float64.(copy(factors))
            end
        end
    end
    
    probabilities = fill(1.0 / n_samples, n_samples)
    return scenarios, probabilities
end


"""
    get_sampling_function(uncertainty::TimeSeriesUncertainty)

Create appropriate sampling function based on uncertainty method.

# Returns
- `Function`: A zero-argument function that returns a sampled deviation
"""
function get_sampling_function(uncertainty::TimeSeriesUncertainty)
    if uncertainty.method == "discrete"
        return () -> sample_deviation_from_distribution(
            uncertainty.deviation_fractions,
            uncertainty.deviation_probabilities
        )
    elseif uncertainty.method == "normal"
        return () -> sample_normal_deviation(uncertainty.mean, uncertainty.std)
    elseif uncertainty.method == "uniform"
        return () -> sample_uniform_deviation(uncertainty.lower_bound, uncertainty.upper_bound)
    else
        error("Invalid method for sampling: $(uncertainty.method)")
    end
end


"""
    generate_load_scenarios(nominal_loads_kw, uncertainty)

Generate load scenarios based on uncertainty specification.
"""
function generate_load_scenarios(
    nominal_loads_kw::Array{<:Real, 1},
    uncertainty::TimeSeriesUncertainty
)
    if !uncertainty.enabled
        return Dict{Int, Vector{Float64}}(1 => Float64.(nominal_loads_kw)), [1.0]
    end
    
    if uncertainty.method == "time_invariant"
        return generate_load_scenarios_time_invariant(nominal_loads_kw, uncertainty)
    else
        # All sampling methods (discrete, normal, uniform) use same logic
        sampling_func = get_sampling_function(uncertainty)
        scenarios = apply_sampled_deviations(nominal_loads_kw, uncertainty.n_samples, sampling_func)
        probabilities = fill(1.0 / uncertainty.n_samples, uncertainty.n_samples)
        return scenarios, probabilities
    end
end


"""
    generate_load_scenarios_time_invariant(nominal_loads_kw, uncertainty)

Generate time-invariant load scenarios.
All timesteps in a scenario have the same deviation applied.

# Arguments
- `nominal_loads_kw::Array{<:Real, 1}`: Nominal load profile
- `uncertainty::TimeSeriesUncertainty`: Uncertainty specification

# Returns
- `scenarios::Dict{Int, Array{Float64, 1}}`: Dictionary mapping scenario ID to load profile
- `probabilities::Array{Float64, 1}`: Probability of each scenario
"""
function generate_load_scenarios_time_invariant(
    nominal_loads_kw::Array{<:Real, 1},
    uncertainty::TimeSeriesUncertainty
)
    scenarios = Dict{Int, Vector{Float64}}()
    probabilities = Float64[]
    
    # Generate scenario for each deviation
    for (idx, (deviation, prob)) in enumerate(zip(uncertainty.deviation_fractions, uncertainty.deviation_probabilities))
        scenarios[idx] = Float64.(nominal_loads_kw .* (1.0 + deviation))
        push!(probabilities, prob)
    end
    
    return scenarios, probabilities
end


"""
    generate_production_scenarios(nominal_production_factor, uncertainty, renewable_techs)

Generate production factor scenarios for renewable technologies.
"""
function generate_production_scenarios(
    nominal_production_factor::Dict{String, Array{Float64, 1}},
    uncertainty::TimeSeriesUncertainty,
    renewable_techs::Array{String, 1}
)
    if !uncertainty.enabled
        return Dict{Int, Dict{String, Vector{Float64}}}(1 => nominal_production_factor), [1.0]
    end
    
    if uncertainty.method == "time_invariant"
        return generate_production_scenarios_time_invariant(nominal_production_factor, uncertainty, renewable_techs)
    else
        # All sampling methods (discrete, normal, uniform) use same logic
        sampling_func = get_sampling_function(uncertainty)
        return generate_production_scenarios_generic(
            nominal_production_factor, uncertainty.n_samples, renewable_techs, sampling_func
        )
    end
end


"""
    generate_production_scenarios_time_invariant(nominal_production_factor, uncertainty, renewable_techs)

Generate time-invariant production scenarios.
All timesteps in a scenario have the same deviation applied.

# Arguments
- `nominal_production_factor::Dict{String, Array{Float64, 1}}`: Nominal production factors by tech
- `uncertainty::TimeSeriesUncertainty`: Uncertainty specification
- `renewable_techs::Array{String, 1}`: Technologies to apply uncertainty to

# Returns
- `scenarios::Dict{Int, Dict{String, Array{Float64, 1}}}`: Dictionary mapping scenario ID to production factors by tech
- `probabilities::Array{Float64, 1}`: Probability of each scenario
"""
function generate_production_scenarios_time_invariant(
    nominal_production_factor::Dict{String, Array{Float64, 1}},
    uncertainty::TimeSeriesUncertainty,
    renewable_techs::Array{String, 1}
)
    scenarios = Dict{Int, Dict{String, Vector{Float64}}}()
    probabilities = Float64[]
    
    # Generate scenario for each deviation
    for (idx, (deviation, prob)) in enumerate(zip(uncertainty.deviation_fractions, uncertainty.deviation_probabilities))
        scenarios[idx] = Dict{String, Vector{Float64}}()
        
        # Copy all tech production factors
        for (tech, factors) in nominal_production_factor
            if tech in renewable_techs
                # Apply uncertainty
                scenarios[idx][tech] = Float64.(factors .* (1.0 + deviation))
            else
                # No uncertainty for this tech
                scenarios[idx][tech] = Float64.(copy(factors))
            end
        end
        
        push!(probabilities, prob)
    end
    
    return scenarios, probabilities
end


"""
    combine_load_production_scenarios(load_scenarios, load_probs, prod_scenarios, prod_probs)

Combine independent load and production scenarios into joint scenarios.
Assumes independence between load and production uncertainty.

# Arguments
- `load_scenarios::Dict{Int, Array{Float64, 1}}`: Load scenarios
- `load_probs::Array{Float64, 1}`: Load scenario probabilities
- `prod_scenarios::Dict{Int, Dict{String, Array{Float64, 1}}}`: Production scenarios
- `prod_probs::Array{Float64, 1}`: Production scenario probabilities

# Returns
- `combined_loads::Dict{Int, Array{Float64, 1}}`: Combined load scenarios
- `combined_prods::Dict{Int, Dict{String, Array{Float64, 1}}}`: Combined production scenarios
- `combined_probs::Array{Float64, 1}`: Combined scenario probabilities

# Note
If both load and production uncertainty are enabled, this creates 9 scenarios (3 load × 3 production).
"""
function combine_load_production_scenarios(
    load_scenarios::Dict{Int, Array{Float64, 1}},
    load_probs::Array{Float64, 1},
    prod_scenarios::Dict{Int, Dict{String, Array{Float64, 1}}},
    prod_probs::Array{Float64, 1}
)
    n_load = length(load_scenarios)
    n_prod = length(prod_scenarios)
    
    combined_loads = Dict{Int, Array{Float64, 1}}()
    combined_prods = Dict{Int, Dict{String, Array{Float64, 1}}}()
    combined_probs = Float64[]
    
    scenario_id = 1
    for i in 1:n_load
        for j in 1:n_prod
            combined_loads[scenario_id] = load_scenarios[i]
            combined_prods[scenario_id] = prod_scenarios[j]
            push!(combined_probs, load_probs[i] * prod_probs[j])
            scenario_id += 1
        end
    end
    
    return combined_loads, combined_prods, combined_probs
end
