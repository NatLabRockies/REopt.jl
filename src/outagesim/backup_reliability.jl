# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.

"""
transition_prob(start_gen::Vector{Int}, end_gen::Vector{Int}, fail_prob_vec::Vector{<:Real})::Vector{Float64}

Transition probability for multiple generator types. 
Return the probability of having ``end_gen`` working generators at the end of a period given ``start_gen`` generators are working at the start of the period and
given generators have a failure probability of ``fail_prob_vec``. 

``start_gen``, ``end_gen``, and fail_prob_vec are vectors of the form [x_1, ..., x_t] given there are t generator types.  

Function used to create transition probabilities in Markov matrix.

# Examples
```repl-julia
fail_prob_vec = [0.2, 0.5]; num_generators = [1,1]
num_generators_working = reshape(collect(Iterators.product((0:g for g in num_generators)...)), :, 1)
starting_gens = vec(repeat(num_generators_working, outer = prod(num_generators .+ 1)))
ending_gens = repeat(vec(num_generators_working), inner = prod(num_generators .+ 1))

julia> transition_prob(starting_gens, ending_gens, fail_prob_vec)
16-element Vector{Float64}:
 1.0
 0.2
 ...
 0.4
```
"""
function transition_prob(start_gen::Vector, end_gen::Vector, fail_prob_vec::Vector{<:Real})::Vector{Float64} 
    start_gen_matrix = hcat(collect.(start_gen)...)
    end_gen_matrix = hcat(collect.(end_gen)...)

    transitions =  [binomial.(start_gen_matrix[i, :], end_gen_matrix[i, :]).*(1-fail_prob_vec[i]).^(end_gen_matrix[i, :]).*(fail_prob_vec[i]).^(start_gen_matrix[i, :].-end_gen_matrix[i, :]) for i in eachindex(fail_prob_vec)]
    return .*(transitions...)
end


"""
    markov_matrix(num_generators::Vector{Int}, fail_prob_vec::Vector{<:Real})::Matrix{Float64} 

Markov Matrix for multiple generator types. 
Return an prod(``num_generators``.+1) by prod(``num_generators``.+1) matrix of transition probabilities of going from n (row) to n' (column) given probability ``fail_prob_vec``

Rows denote starting generators and columns denote ending generators. 
Generator availability scenarios are ordered such that the number of the leftmost generator type increments fastest.
For example, if `num_generators` = [2, 1], then the rows of the returned matrix correspond to the number of working generators by type as follows:
row    working generators
1           (0, 0) 
2           (1, 0)
3           (2, 0)
4           (0, 1)
5           (1, 1)
6           (2, 1)

# Arguments
- `num_generators::Vec{Int}`: Vector of the number of generators of each type 
- `fail_prob::Vec{Real}`: vector of probability of failure of each generator type

# Examples
```repl-julia
julia> markov_matrix([2, 1], [0.1, 0.25])
6×6 Matrix{Float64}:
 1.0   0.0     0.0     0.0  0.0     0.0
 0.1   0.0     0.225   0.0  0.0     0.675
 0.01  0.81    0.045   0.0  0.0     0.135
 0.0   0.25    0.0     0.0  0.75    0.0
 0.9   0.025   0.0     0.0  0.075   0.0
 0.18  0.0025  0.2025  0.0  0.0075  0.6075
```
"""
function markov_matrix(num_generators::Vector{Int}, fail_prob_vec::Vector{<:Real})::Matrix{Float64} 
    # num_generators_working is a vector of tuples, each tuple indicating a number of each gen type that is working
    num_generators_working = reshape(collect(Iterators.product((0:g for g in num_generators)...)), :, 1)
    starting_gens = vec(repeat(num_generators_working, outer = prod(num_generators .+ 1)))
    ending_gens = repeat(vec(num_generators_working), inner = prod(num_generators .+ 1))

    #Creates Markov matrix for generator transition probabilities
    M = reshape(transition_prob(starting_gens, ending_gens, fail_prob_vec), prod(num_generators.+1), prod(num_generators .+1))
    replace!(M, NaN => 0)
    return M
end


"""
    starting_probabilities(num_generators::Vector{Int}, generator_operational_availability::Vector{<:Real}, generator_failure_to_start::Vector{<:Real})::Matrix{Float64}

Starting Probabilities for multiple generator types. 
Return a 1 by prod(``num_generators`` .+ 1) matrix (row vector) of the probability that each number of generators 
(differentiated by generator type) is both operationally available (``generator_operational_availability``) 
and avoids a Failure to Start (``failure_to_start``) in an inital time step

Generator availability scenarios are ordered such that the number of the leftmost generator type increments fastest.
For example, if `num_generators` = [2, 1], then the columns of the returned matrix correspond to the number of working generators by type as follows:
col    working generators
1           (0, 0) 
2           (1, 0)
3           (2, 0)
4           (0, 1)
5           (1, 1)
6           (2, 1)

# Arguments
- `num_generators::Vec{Int}`: the number of generators of each type 
- `generator_operational_availability::Vec{Real}`: Operational Availability. The chance that a generator will be available (not down for maintenance) at the start of the outage
- `generator_failure_to_start::Vec{Real}`: Failure to Start. The chance that a generator fails to successfully start and take load.

# Examples
```repl-julia
julia> starting_probabilities([2, 1], [0.99,0.95], [0.05, 0.1])
1×6 Matrix{Float64}:
    0.000513336  0.0162283  0.128258  0.00302691  0.0956912  0.756282
```
"""
function starting_probabilities(num_generators::Vector{Int}, generator_operational_availability::Vector{<:Real}, generator_failure_to_start::Vector{<:Real})::Matrix{Float64} 
    starting_vec = markov_matrix(
        num_generators, 
        (1 .- generator_operational_availability) .+ (generator_failure_to_start .* generator_operational_availability)
    )[end, :]
    return reshape(starting_vec, 1, length(starting_vec))
end

"""
    bin_battery_charge(batt_soc_kwh::Vector, num_bins::Int, battery_size_kwh::Real)::Vector{Int}

Return a vector the same length as ``batt_soc_kwh`` of discritized battery charge bins

The first bin denotes zero battery charge, and each additional bin has size of ``battery_size_kwh``/(``num_bins``-1)
Values are rounded to nearest bin.

# Examples
```repl-julia
julia>  bin_battery_charge([30, 100, 170.5, 250, 251, 1000], 11, 1000)
6-element Vector{Int64}:
  1
  2
  3
  3
  4
 11
```
"""
function bin_battery_charge(batt_soc_kwh::Vector, num_bins::Int, battery_size_kwh::Real)::Vector{Int}  
    #Bins battery into discrete portions. Zero is one of the bins. 
    bin_size = battery_size_kwh / (num_bins-1)
    return min.(num_bins, round.(batt_soc_kwh./bin_size).+1)
end


"""
    generator_output(num_generators::Vector{Int}, generator_size_kw::Vector{<:Real})::Vector{Float64} 

Generator output for multiple generator types
Return a prod(``num_generators`` .+ 1) length vector of maximum generator capacity given 0 to ``num_generators`` of each type are available

Generator availability scenarios are ordered such that the number of the leftmost generator type increments fastest.
For example, if `num_generators` = [2, 1], then the elements of the returned vector correspond to the number of working generators by type as follows:
index    working generators
1           (0, 0) 
2           (1, 0)
3           (2, 0)
4           (0, 1)
5           (1, 1)
6           (2, 1)

#Examples
```repl-julia
generator_output([2,1], [250, 300])
6-element Vector{Float64}:
   0.0
 250.0
 500.0
 300.0
 550.0
 800.0
```
"""
function generator_output(num_generators::Vector{Int}, generator_size_kw::Vector{<:Real})::Vector{Float64} 
    gens_working = (0:g for g in num_generators)
    num_generators_working = reshape(collect(Iterators.product(gens_working...)), :, 1)
    #Returns vector of maximum generator output
    return vec([sum(gw[i] * generator_size_kw[i] for i in eachindex(generator_size_kw)) for gw in num_generators_working])
end


"""
    get_maximum_generation(battery_size_kw::Real, generator_size_kw::Vector{<:Real}, bin_size::Real, 
        num_bins::Int, num_generators::Vector{Int}, battery_discharge_efficiency::Real)::Matrix{Float64}

Maximum generation calculation for multiple generator types
Return a matrix of maximum total system output.

Rows denote battery state of charge bin and columns denote number of available generators, with the first column denoting zero available generators.

# Arguments
- `battery_size_kw::Real`: battery inverter size
- `generator_size_kw::Vector{Real}`: maximum output from single generator for each generator type. 
- `bin_size::Real`: size of discretized battery soc bin. is equal to battery_size_kwh / (num_bins - 1) 
- `num_bins::Int`: number of battery bins. 
- `num_generators::Vector{Int}`: number of generators by type in microgrid.
- `battery_discharge_efficiency::Real`: battery_discharge_efficiency = battery_discharge / battery_reduction_in_soc

# Examples
```repl-julia
julia>  get_maximum_generation(200, [50, 125], 100, 3, [2, 1], 0.98)
3×6 Matrix{Float64}:
   0.0   50.0  100.0  125.0  175.0  225.0
  98.0  148.0  198.0  223.0  273.0  323.0
 196.0  246.0  296.0  321.0  371.0  421.0
```
"""
function get_maximum_generation(battery_size_kw::Real, generator_size_kw::Vector{<:Real}, bin_size::Real, 
    num_bins::Int, num_generators::Vector{Int}, battery_discharge_efficiency::Real)::Matrix{Float64}
    #Returns a matrix of maximum generation (rows denote number of generators starting at 0, columns denote battery bin)
    N = prod(num_generators .+ 1)
    M = num_bins
    max_system_output = zeros(M, N)
    for i in 1:M
        max_system_output[i, :] = generator_output(num_generators, generator_size_kw) .+ min(battery_size_kw, (i-1)*bin_size*battery_discharge_efficiency)
    end
    return max_system_output
end

"""
    battery_bin_shift(excess_generation_kw::Vector, bin_size::Real, battery_size_kw::Real, battery_charge_efficiency::Real, battery_discharge_efficiency::Real)::Vector{Int} 

Return a vector of number of bins battery is shifted by, where each element of the vector corresponds to the number of working generators

Bins are the discritized battery sizes, with the first bin denoting zero charge and the last bin denoting full charge. Thus, if there are 101 bins, then each bin denotes 
a one percent difference in battery charge. The battery will attempt to dispatch to meet critical loads not met by other generation sources, and will charge from excess generation. 

# Arguments
- `excess_generation_kw::Vector`: maximum generator output minus net critical load for each number of working generators
- `bin_size::Real`: size of battery bin
- `battery_size_kw::Real`: inverter size
- `battery_charge_efficiency::Real`: battery_charge_efficiency = increase_in_soc_kwh / grid_input_kwh 
- `battery_discharge_efficiency::Real`: battery_discharge_efficiency = battery_discharge / battery_reduction_in_soc

#Examples
```repl-julia
julia>
excess_generation_kw = [-500, -120, 0, 50, 175, 400]
bin_size = 100
battery_size_kw = 300
battery_bin_shift(excess_generation_kw, bin_size, battery_size_kw, 1, 1)
7-element Vector{Int64}:
 -3
 -1
  0
  0
  0
  2
  3
  ```
"""
function battery_bin_shift(excess_generation_kw::Vector{<:Real}, bin_size::Real, battery_size_kw::Real,
                                battery_charge_efficiency::Real, battery_discharge_efficiency::Real)::Vector{Int} 
    #Determines how many battery bins to shift by
    #Lose energy charging battery and use more energy discharging battery
    #Need to shift battery up by less and down by more.
    
    #Battery cannot charge or discharge more than its capacity
    excess_generation_kw[excess_generation_kw .> battery_size_kw] .= battery_size_kw
    excess_generation_kw[excess_generation_kw .< -battery_size_kw] .= -battery_size_kw
    #Account for (dis)charge efficiency
    excess_generation_kw[excess_generation_kw .> 0] = excess_generation_kw[excess_generation_kw .> 0] .* battery_charge_efficiency
    excess_generation_kw[excess_generation_kw .< 0] = excess_generation_kw[excess_generation_kw .< 0] ./ battery_discharge_efficiency

    shift = round.(excess_generation_kw ./ bin_size)
    return shift
end

"""
    shift_gen_battery_prob_matrix!(gen_battery_prob_matrix::Matrix, shift_vector::Vector{Int})

Updates ``gen_battery_prob_matrix`` in place to account for change in battery state of charge bin

shifts probabiilities in column i by ``shift_vector``[i] positions, accounting for accumulation at 0 or full soc   

#Examples
```repl-julia
gen_battery_prob_matrix = [0.6 0.3;
                           0.2 0.3;
                           0.1 0.2;
                           0.1 0.2]
shift_vector = [-1, 2]
shift_gen_battery_prob_matrix!(gen_battery_prob_matrix, shift_vector)
gen_battery_prob_matrix
4×2 Matrix{Float64}:
 0.8  0.0
 0.1  0.0
 0.1  0.3
 0.0  0.7
```
"""
function shift_gen_battery_prob_matrix!(gen_battery_prob_matrix::Matrix, shift_vector::Vector{Int})
    M = size(gen_battery_prob_matrix, 1)
    
    for i in eachindex(shift_vector) 
        s = shift_vector[i]
        if s < 0 
            #TODO figure out why implementation of cirshift! is working locally but not on server
            # circshift!(view(gen_battery_prob_matrix, :, i), s)
            gen_battery_prob_matrix[:, i] = circshift(view(gen_battery_prob_matrix, :, i), s)
            gen_battery_prob_matrix[1, i] += sum(view(gen_battery_prob_matrix, max(2,M+s+1):M, i))
            gen_battery_prob_matrix[max(2,M+s+1):M, i] .= 0
        elseif s > 0
            # circshift!(view(gen_battery_prob_matrix, :, i), s)
            gen_battery_prob_matrix[:, i] = circshift(view(gen_battery_prob_matrix, :, i), s)
            gen_battery_prob_matrix[end, i] += sum(view(gen_battery_prob_matrix, 1:min(s,M-1), i))
            gen_battery_prob_matrix[1:min(s,M-1), i] .= 0
        end
    end
end

"""
update_survival!(survival, maximum_generation, net_critical_loads_kw_at_time_h)::Matrix{Int}

In place update of survival matrix with 0 in states where generation cannot meet load and 1 in states where it can.
"""
function update_survival!(survival, maximum_generation, net_critical_loads_kw_at_time_h)
    @inbounds for i in eachindex(maximum_generation)
        survival[i] = 1 * (maximum_generation[i] - net_critical_loads_kw_at_time_h >= 0)
    end
end

"""
survival_chance_mult(prob_matrix, survival)

More efficient implementation of sum(prob_matrix .* survival)
"""
function survival_chance_mult(prob_matrix, survival)::Real
    s = 0
    @inbounds for i in eachindex(prob_matrix)
        s += prob_matrix[i] * survival[i]
    end
    return s
end

"""
prob_matrix_update!(prob_matrix, survival)

More efficient implementation of prob_matrix = prob_matrix .* survival
"""
function prob_matrix_update!(prob_matrix, survival)
    @inbounds for i in eachindex(prob_matrix)
        prob_matrix[i] *= survival[i]
    end
end

"""
    survival_gen_only(;critical_load::Vector, generator_operational_availability::Real, generator_failure_to_start::Real, generator_mean_time_to_failure::Real, num_generators::Int,
                                generator_size_kw::Real, max_outage_duration::Int, marginal_survival = false)::Matrix{Float64}

Return a matrix of probability of survival with rows denoting outage start timestep and columns denoting outage duration

Solves for probability of survival given only backup generators (no battery backup). 
If ``marginal_survival`` = true then result is chance of surviving in given outage timestep, 
if ``marginal_survival`` = false then result is chance of surviving up to and including given outage timestep.

# Arguments
- `net_critical_loads_kw::Vector`: Vector of system critical loads. 
- `generator_operational_availability::Vector{<:Real}`: Operational Availability of backup generators.
- `generator_failure_to_start::Vector{<:Real}`: probability of generator Failure to Start and support load. 
- `generator_mean_time_to_failure::Vector{<:Real}`: Average number of time steps between a generator's failures. 1/(failure to run probability). 
- `num_generators::Vector{Int}`: number of generators in microgrid.
- `generator_size_kw::Vector{<:Real}`: size of generator.
- `max_outage_duration::Int`: maximum outage duration in timesteps.
- `marginal_survival::Bool`: indicates whether results are probability of survival in given outage duration timestep or probability of surviving up to and including the given timestep.

# Examples
Given generator_mean_time_to_failure = 5, the chance of no generators failing in 0.64 in time step 1, 0.4096 in time step 2, and 0.262144 in time step 3
Chance of 2 generators failing is 0.04 in time step 1, 0.1296 by time step 1, and 0.238144 by time step 3   
```repl-julia
julia> net_critical_loads_kw = [1,2,2,1]; generator_operational_availability = 1; failure_to_start = 0.0; MTTF = 0.2; num_generators = 2; generator_size_kw = 1; max_outage_duration = 3;
julia> survival_gen_only(net_critical_loads_kw=net_critical_loads_kw, generator_operational_availability=generator_operational_availability, 
                                generator_failure_to_start=failure_to_start, generator_mean_time_to_failure=MTTF, num_generators=num_generators, 
                                generator_size_kw=generator_size_kw, max_outage_duration=max_outage_duration, marginal_survival = true)
4×3 Matrix{Float64}:
 0.96  0.4096  0.262144
 0.64  0.4096  0.761856
 0.96  0.8704  0.761856
 0.96  0.8704  0.262144

julia> survival_gen_only(net_critical_loads_kw=net_critical_loads_kw, generator_operational_availability=generator_operational_availability, 
                                generator_failure_to_start=failure_to_start, generator_mean_time_to_failure=MTTF, num_generators=num_generators, 
                                generator_size_kw=generator_size_kw, max_outage_duration=max_outage_duration, marginal_survival = false)
4×3 Matrix{Float64}:
 0.96  0.4096  0.262144
 0.64  0.4096  0.393216
 0.64  0.6144  0.557056
 0.96  0.8704  0.262144
```
"""
function survival_gen_only(;
    net_critical_loads_kw::Vector, 
    generator_operational_availability::Vector{<:Real}, 
    generator_failure_to_start::Vector{<:Real}, 
    generator_mean_time_to_failure::Vector{<:Real},
    num_generators::Vector{Int}, 
    generator_size_kw::Vector{<:Real},
    max_outage_duration::Int,
    marginal_survival = false)::Matrix{Float64} 

    t_max = length(net_critical_loads_kw)
    
    generator_production = generator_output(num_generators, generator_size_kw) 
    #Initialize lost load matrix
    survival_probability_matrix = zeros(t_max, max_outage_duration)
    #initialize amount of extra generation for each critical load time step and each amount of generators
    generator_markov_matrix = markov_matrix(num_generators, 1 ./ generator_mean_time_to_failure)
  
    #Get starting generator vector
    starting_gens = starting_probabilities(num_generators, generator_operational_availability, generator_failure_to_start) #initialize gen battery prob matrix

    Threads.@threads for t = 1:t_max
        
        survival_probability_matrix[t, :] = gen_only_survival_single_start_time(
            t, starting_gens, net_critical_loads_kw, generator_production,
            generator_markov_matrix, max_outage_duration, t_max, marginal_survival) 
 
    end
    return survival_probability_matrix
end

"""
    survival_gen_only_single_start_time(t::Int, starting_gens::Matrix{Float64}, net_critical_loads_kw::Vector{Real}, generator_production::Vector{Float64}, 
    generator_markov_matrix::Matrix{Float64}, max_outage_duration::Int, t_max::Int, marginal_survival::Bool)::Vector{Float64}

Return a vector of probability of survival with for all outage durations given outages start time t. 
    Function is for internal loop of survival_gen_only
"""
function gen_only_survival_single_start_time(
    t::Int, 
    starting_gens::Matrix{Float64},
    net_critical_loads_kw::Vector, 
    generator_production::Vector{Float64},
    generator_markov_matrix::Matrix{Float64},
    max_outage_duration::Int,
    t_max::Int,
    marginal_survival::Bool)::Vector{Float64}

    survival_chances = zeros(max_outage_duration)
    gen_prob_array = [copy(starting_gens), copy(starting_gens)]
    survival = ones(1, length(generator_production))

    for d in 1:max_outage_duration
        h = mod(t + d - 2, t_max) + 1 #determines index accounting for looping around year
        update_survival!(survival, generator_production, net_critical_loads_kw[h])

        #Update probabilities to account for generator failures
        #This is a more memory efficient way of implementing gen_battery_prob_matrix *= generator_markov_matrix
        gen_matrix_counter_start = ((d-1) % 2) + 1 
        gen_matrix_counter_end = (d % 2) + 1 
        mul!(gen_prob_array[gen_matrix_counter_end], gen_prob_array[gen_matrix_counter_start], generator_markov_matrix)
        
        if marginal_survival == false
            prob_matrix_update!(gen_prob_array[gen_matrix_counter_end], survival) 
            survival_chances[d] = sum(gen_prob_array[gen_matrix_counter_end])
        else
            survival_chances[d] = survival_chance_mult(gen_prob_array[gen_matrix_counter_end], survival)
        end

    end
    return survival_chances
end

"""
    survival_with_battery(;net_critical_loads_kw::Vector, battery_starting_soc_kwh::Vector, generator_operational_availability::Vector{<:Real}, generator_failure_to_start::Vector{<:Real}, 
                        generator_mean_time_to_failure::Vector{<:Real}, num_generators::Vector{Int}, generator_size_kw::Vector{<:Real}, battery_size_kwh::Real, battery_size_kw::Real, num_bins::Int, 
                        max_outage_duration::Int, battery_charge_efficiency::Real, battery_discharge_efficiency::Real, marginal_survival::Bool = false, time_steps_per_hour::Real = 1)::Matrix{Float64} 

Return a matrix of probability of survival with rows denoting outage start and columns denoting outage duration

Solves for probability of survival given both networked generators and battery backup. 
If ``marginal_survival`` = true then result is chance of surviving in given outage time step, 
if ``marginal_survival`` = false then result is chance of surviving up to and including given outage time step.

# Arguments
- `net_critical_loads_kw::Vector`: Vector of system critical loads minus solar generation.
- `battery_starting_soc_kwh::Vector`: Vector of battery charge (kwh) for each time step of year. 
- `generator_operational_availability::Vector{<:Real}`: Operational Availability of backup generators.
- `generator_failure_to_start::Vector{<:Real}`: Probability of generator Failure to Start and support load. 
- `generator_mean_time_to_failure::Vector{<:Real}`: Average number of time steps between failures. 1/MTTF (failure to run probability). 
- `num_generators::Vector{Int}`: number of generators in microgrid.
- `generator_size_kw::Vector{<:Real}`: size of generator.
- `battery_size_kwh::Vector{<:Real}`: energy capacity of battery system.
- `battery_size_kw::Vector{<:Real}`: battery system inverter size.
- `num_battery_bins::Int`: number of battery bins. 
- `max_outage_duration::Int`: maximum outage duration in time steps (time step is generally hourly but could be other values such as 15 minutes).
- `battery_charge_efficiency::Real`: battery_charge_efficiency = increase_in_soc_kwh / grid_input_kwh 
- `battery_discharge_efficiency::Real`: battery_discharge_efficiency = battery_discharge / battery_reduction_in_soc
- `marginal_survival::Bool`: indicates whether results are probability of survival in given outage time step or probability of surviving up to and including time step.

# Examples
Given MTTF = 0.2, the chance of no generators failing in 0.64 in time step 1, 0.4096 in time step 2, and 0.262144 in time step 3
Chance of 2 generators failing is 0.04 in time step 1, 0.1296 by time step 2, and 0.238144 by time step 3   
```repl-julia
julia> net_critical_loads_kw = [1,2,2,1]; battery_starting_soc_kwh = [1,1,1,1];  max_outage_duration = 3;
julia> num_generators = 2; generator_size_kw = 1; generator_operational_availability = 1; failure_to_start = 0.0; MTTF = 0.2;
julia> num_battery_bins = 3; battery_size_kwh = 2; battery_size_kw = 1;  battery_charge_efficiency = 1; battery_discharge_efficiency = 1;

julia> survival_with_battery(net_critical_loads_kw=net_critical_loads_kw, battery_starting_soc_kwh=battery_starting_soc_kwh, 
                            generator_operational_availability=generator_operational_availability, generator_failure_to_start=failure_to_start, 
                            generator_mean_time_to_failure=MTTF, num_generators=num_generators, generator_size_kw=generator_size_kw, 
                            battery_size_kwh=battery_size_kwh, battery_size_kw = battery_size_kw, num_battery_bins=num_battery_bins, 
                            max_outage_duration=max_outage_duration, battery_charge_efficiency=battery_charge_efficiency, 
                            battery_discharge_efficiency=battery_discharge_efficiency, marginal_survival = true)
4×3 Matrix{Float64}:
1.0   0.8704  0.557056
0.96  0.6144  0.77824
0.96  0.896   0.8192
1.0   0.96    0.761856

julia> survival_with_battery(net_critical_loads_kw=net_critical_loads_kw, battery_starting_soc_kwh=battery_starting_soc_kwh, 
                            generator_operational_availability=generator_operational_availability, generator_failure_to_start=failure_to_start, 
                            generator_mean_time_to_failure=MTTF, num_generators=num_generators, generator_size_kw=generator_size_kw, 
                            battery_size_kwh=battery_size_kwh, battery_size_kw = battery_size_kw, num_battery_bins=num_battery_bins, 
                            max_outage_duration=max_outage_duration, battery_charge_efficiency=battery_charge_efficiency, 
                            battery_discharge_efficiency=battery_discharge_efficiency, marginal_survival = false)
4×3 Matrix{Float64}:
1.0   0.8704  0.557056
0.96  0.6144  0.57344
0.96  0.896   0.8192
1.0   0.96    0.761856
```
"""
function survival_with_battery(;
    net_critical_loads_kw::Vector, 
    battery_starting_soc_kwh::Vector, 
    generator_operational_availability::Vector{<:Real}, 
    generator_failure_to_start::Vector{<:Real},
    generator_mean_time_to_failure::Vector{<:Real},
    num_generators::Vector{Int},
    generator_size_kw::Vector{<:Real}, 
    battery_size_kwh::Real, 
    battery_size_kw::Real, 
    num_battery_bins::Int, 
    max_outage_duration::Int, 
    battery_charge_efficiency::Real,
    battery_discharge_efficiency::Real,
    marginal_survival::Bool = false,
    time_steps_per_hour::Real = 1)::Matrix{Float64} 

    t_max = length(net_critical_loads_kw)
    
    #bin size is battery storage divided by num bins-1 because zero is also a bin
    bin_size = battery_size_kwh / (num_battery_bins-1)
     
    #bin initial battery 
    starting_battery_bins = bin_battery_charge(battery_starting_soc_kwh, num_battery_bins, battery_size_kwh)
    #For easier indice reading
    M = num_battery_bins
    N = prod(num_generators .+ 1)
    #Initialize survival probability matrix
    survival_probability_matrix = zeros(t_max, max_outage_duration) 
    #initialize vectors and matrices
    generator_markov_matrix = markov_matrix(num_generators, 1 ./ generator_mean_time_to_failure) 
    generator_production = generator_output(num_generators, generator_size_kw)
    maximum_generation = get_maximum_generation(battery_size_kw, generator_size_kw, bin_size, num_battery_bins, num_generators, battery_discharge_efficiency)
    starting_gens = starting_probabilities(num_generators, generator_operational_availability, generator_failure_to_start) 

    Threads.@threads for t = 1:t_max
        survival_probability_matrix[t, :] = survival_with_battery_single_start_time(t, 
        net_critical_loads_kw, battery_size_kw, max_outage_duration, battery_charge_efficiency,
        battery_discharge_efficiency, M, N, starting_gens, generator_production,
        generator_markov_matrix, maximum_generation, t_max, starting_battery_bins, bin_size, marginal_survival, time_steps_per_hour)
    end
    return survival_probability_matrix
end


"""
survival_with_battery_single_start_time(t::Int, net_critical_loads_kw::Vector, 
    generator_size_kw::Vector{<:Real}, 
    max_outage_duration::Int, battery_charge_efficiency::Real, battery_discharge_efficiency::Real, M::Int, N::Int,
    starting_gens::Matrix{Float64}, generator_production::Vector{Float64}, generator_markov_matrix::Matrix{Float64},
    maximum_generation::Matrix{Float64}, t_max::Int, starting_battery_bins::Vector{Int}, bin_size::Real, marginal_survival::Bool, time_steps_per_hour::Real)::Vector{Float64}

Return a vector of probability of survival with for all outage durations given outages start time t. 
    Function is for internal loop of survival_with_battery
"""
function survival_with_battery_single_start_time(
    t::Int, 
    net_critical_loads_kw::Vector, 
    battery_size_kw::Real, 
    max_outage_duration::Int, 
    battery_charge_efficiency::Real,
    battery_discharge_efficiency::Real,
    M::Int,
    N::Int,
    starting_gens::Matrix{Float64},
    generator_production::Vector{Float64},
    generator_markov_matrix::Matrix{Float64},
    maximum_generation::Matrix{Float64},
    t_max::Int,
    starting_battery_bins::Vector{Int},
    bin_size::Real,
    marginal_survival::Bool, 
    time_steps_per_hour::Real)::Vector{Float64}

    gen_battery_prob_matrix_array = [zeros(M, N), zeros(M, N)]
    gen_battery_prob_matrix_array[1][starting_battery_bins[t], :] = starting_gens
    gen_battery_prob_matrix_array[2][starting_battery_bins[t], :] = starting_gens
    return_survival_chance_vector = zeros(max_outage_duration)
    survival = ones(M, N)

    for d in 1:max_outage_duration 
        h = mod(t + d - 2, t_max) + 1 #determines index accounting for looping around year
        
        update_survival!(survival, maximum_generation, net_critical_loads_kw[h])
        
        #Update probabilities to account for generator failures
        #This is a more memory efficient way of implementing gen_battery_prob_matrix *= generator_markov_matrix
        gen_matrix_counter_start = ((d-1) % 2) + 1 
        gen_matrix_counter_end = (d % 2) + 1 
        mul!(gen_battery_prob_matrix_array[gen_matrix_counter_end], gen_battery_prob_matrix_array[gen_matrix_counter_start], generator_markov_matrix)

        if marginal_survival == false
            # @timeit to "survival chance" gen_battery_prob_matrix_array[gen_matrix_counter_end] = gen_battery_prob_matrix_array[gen_matrix_counter_end] .* survival 
            prob_matrix_update!(gen_battery_prob_matrix_array[gen_matrix_counter_end], survival) 
            return_survival_chance_vector[d] = sum(gen_battery_prob_matrix_array[gen_matrix_counter_end])
        else
            return_survival_chance_vector[d] = survival_chance_mult(gen_battery_prob_matrix_array[gen_matrix_counter_end], survival)
        end

        #Update generation battery probability matrix to account for battery shifting
        shift_gen_battery_prob_matrix!(
            gen_battery_prob_matrix_array[gen_matrix_counter_end], 
            battery_bin_shift(
                (generator_production .- net_critical_loads_kw[h]) / time_steps_per_hour, 
                bin_size, 
                battery_size_kw, 
                battery_charge_efficiency, 
                battery_discharge_efficiency
            )
        )
    end
    return return_survival_chance_vector
end

"""
    backup_reliability_reopt_inputs(;d::Dict, p::REoptInputs, r::Dict)::Dict

Return a dictionary of inputs required for backup reliability calculations. 

# Arguments
-d::Dict: REopt results dictionary.
-p::REoptInputs: REopt inputs struct.  
-r::Dict: Dictionary of inputs for reliability calculations. If r not included then uses all defaults. values read from dictionary:
    -generator_operational_availability::Union{Real, Vector{<:Real}} = 0.995    Fraction of year generators not down for maintenance
    -generator_failure_to_start::Union{Real, Vector{<:Real}} = 0.0094           Chance of generator starting given outage
    -generator_mean_time_to_failure::Union{Real, Vector{<:Real}} = 1100         Average number of time steps between a generator's failures. 1/(failure to run probability). 
    -num_generators::Union{Int, Vector{Int}} = 1                                                    Number of generators. 
    -generator_size_kw::Union{Real, Vector{<:Real}} = 0.0                       Backup generator capacity. 
    -num_battery_bins::Int                                                      Number of bins for discretely modeling battery state of charge
    -max_outage_duration::Int = 96                                              Maximum outage time step modeled
    -microgrid_only::Bool = false                                               Boolean to specify if only microgrid upgraded technologies run during grid outage
    -battery_minimum_soc_fraction::Real = 0.0                                   The minimum battery state of charge (represented as a fraction) allowed during outages.
    -fuel_limit:Union{Real, Vector{<:Real}} = 1e9                               Amount of fuel available, either by generator type or per generator, depending on fuel_limit_is_per_generator. Change generator_fuel_burn_rate_per_kwh for different fuel efficiencies. Fuel units should be consistent with generator_fuel_intercept_per_hr and generator_fuel_burn_rate_per_kwh.
    -generator_fuel_intercept_per_hr::Union{Real, Vector{<:Real}} = 0.0         Amount of fuel burned each time step while idling. Fuel units should be consistent with fuel_limit and generator_fuel_burn_rate_per_kwh.
    -fuel_limit_is_per_generator::Union{Bool, Vector{Bool}} = false             Boolean to determine whether fuel limit is given per generator or per generator type
    -generator_fuel_burn_rate_per_kwh::Union{Real, Vector{<:Real}} = 0.076      Amount of fuel used per kWh generated. Fuel units should be consistent with fuel_limit and generator_fuel_intercept_per_hr.
    -battery_operational_availability::Real = 0.97                              Likelihood battery will be available at start of outage       
    -pv_operational_availability::Real = 0.98                                   Likelihood PV will be available at start of outage
    -wind_operational_availability::Real = 0.97                                 Likelihood Wind will be available at start of outage
"""
function backup_reliability_reopt_inputs(;d::Dict, p::REoptInputs, r::Dict = Dict())::Dict

    r2 = dictkeys_tosymbols(r)
    zero_array = zeros(length(p.time_steps))
    r2[:critical_loads_kw] = p.s.electric_load.critical_loads_kw

    r2[:time_steps_per_hour] = 1 / p.hours_per_time_step
    microgrid_only = get(r, "microgrid_only", false)

    if haskey(d, "PV") && 
        (
            !microgrid_only ||
            !haskey(d, "Outages") ||
            get(d["Outages"], "pv_microgrid_size_kw", 0) > 0
        )
        #TODO: handle possibility of multiple PVs
        pv_kw_ac_time_series = (
            get(d["PV"], "electric_to_storage_series_kw", zero_array)
            + get(d["PV"], "electric_curtailed_series_kw", zero_array)
            + get(d["PV"], "electric_to_load_series_kw", zero_array)
            + get(d["PV"], "electric_to_grid_series_kw", zero_array)
        )
        r2[:pv_kw_ac_time_series] = pv_kw_ac_time_series .* (
                get(
                    get(d, "Outages", Dict()), 
                    "pv_microgrid_size_kw", 
                    get(d["PV"], "size_kw", 0.0)
                ) / get(d["PV"], "size_kw", 1.0)
            )
    end
    if haskey(d, "Wind") && 
        (
            !microgrid_only ||
            !haskey(d, "Outages") ||
            get(d["Outages"], "wind_microgrid_size_kw", 0) > 0
        )
        wind_kw_ac_time_series = (
            get(d["Wind"], "electric_to_storage_series_kw", zero_array)
            + get(d["Wind"], "electric_curtailed_series_kw", zero_array)
            + get(d["Wind"], "electric_to_load_series_kw", zero_array)
            + get(d["Wind"], "electric_to_grid_series_kw", zero_array)
        )
        r2[:wind_kw_ac_time_series] = wind_kw_ac_time_series .* (
            get(
                get(d, "Outages", Dict()), 
                "wind_microgrid_size_kw", 
                get(d["Wind"], "size_kw", 0.0)
            ) / get(d["Wind"], "size_kw", 1.0)
        )
    end
    if haskey(d, "ElectricStorage") && (
        !microgrid_only ||
        !haskey(d, "Outages") ||
        Bool(get(d["Outages"], "electric_storage_microgrid_upgraded", false))
    )
        r2[:battery_charge_efficiency] = p.s.storage.attr["ElectricStorage"].charge_efficiency
        r2[:battery_discharge_efficiency] = p.s.storage.attr["ElectricStorage"].discharge_efficiency
        r2[:battery_size_kw] = get(d["ElectricStorage"], "size_kw", 0)

        #ERP tool uses effective battery size so need to subtract minimum SOC
        battery_size_kwh = get(d["ElectricStorage"], "size_kwh", 0)
        

        init_soc = get(d["ElectricStorage"], "soc_series_fraction", [])
        battery_starting_soc_kwh = init_soc .* battery_size_kwh
        
        battery_minimum_soc_kwh = battery_size_kwh * get(r2, :battery_minimum_soc_fraction, 0)
        r2[:battery_size_kwh] = battery_size_kwh - battery_minimum_soc_kwh
        r2[:battery_starting_soc_kwh] = battery_starting_soc_kwh .- battery_minimum_soc_kwh
        if minimum(r2[:battery_starting_soc_kwh]) < 0
            @warn("Some battery starting states of charge are less than the provided minimum state of charge.")
        end
    end

    if haskey(r2, :generator_size_kw)
        @warn("Input generator_size_kw provided. Generator and CHP from REopt optimization results/inputs will be ignored.")
        num_gen_types = length(get!(r2, :num_generators, [1]*length(get(r2, :generator_size_kw, [nothing]))))
        if length(get(r2, :generator_size_kw, [nothing])) != num_gen_types
            throw(@error("Input num_generators must be the same length as generator_size_kw."))
        end
        get!(r2, :fuel_limit, [1e9 for _ in 1:num_gen_types])
        get!(r2, :generator_fuel_intercept_per_hr, [0.0 for _ in 1:num_gen_types])
        get!(r2, :generator_fuel_burn_rate_per_kwh, [0.076 for _ in 1:num_gen_types]) 
    else
        if haskey(d, "Generator") && haskey(d, "CHP")
            # Can't determine which user inputs correspond to diesel vs prime. 
            # This issue will go away when nested structure of ERP inputs that 
            # we switched to in the API is extended to REopt.jl.
            throw(@error("Simulating scenarios using backup_reliability(d::Dict, p::REoptInputs, r::Dict) when the REopt results Dict d includes Generator and CHP is not yet supported. Use backup_reliability(r::Dict) instead."))
        end
        diesel_kw = (
                haskey(d, "Generator") && 
                (
                    !microgrid_only ||
                    !haskey(d, "Outages") ||
                    get(d["Outages"], "generator_microgrid_size_kw", 0) > 0
                )
            ) ? 
            get(
                get(d, "Outages", Dict()), 
                "generator_microgrid_size_kw", 
                get(d["Generator"], "size_kw", 0.0)
            ) : 
            0.0
        prime_kw = (
                haskey(d, "CHP") && 
                (
                    !microgrid_only ||
                    !haskey(d, "Outages") ||
                    get(d["Outages"], "chp_microgrid_size_kw", 0) > 0
                )
            ) ? 
            get(
                get(d, "Outages", Dict()), 
                "chp_microgrid_size_kw", 
                get(d["CHP"], "size_kw", 0.0)
            ) : 
            0.0
        if length(get!(r2, :num_generators, [1])) != 1
            throw(@error("Input num_generators must have a length of 1 to match the number of generator types in the scenario."))
        end
        r2[:generator_size_kw] = replace!([diesel_kw + prime_kw] ./ r2[:num_generators], Inf => 0) # at least one gen kw will be 0 because of error thrown above
        if diesel_kw > 0
            fuel_slope, fuel_intercept = fuel_slope_and_intercept(
                electric_efficiency_full_load=p.s.generator.electric_efficiency_full_load, 
                electric_efficiency_half_load=p.s.generator.electric_efficiency_half_load,
                fuel_higher_heating_value_kwh_per_unit=p.s.generator.fuel_higher_heating_value_kwh_per_gal
	        )
            r2[:generator_fuel_burn_rate_per_kwh] = [fuel_slope]
            r2[:generator_fuel_intercept_per_hr] = [fuel_intercept]
            r2[:fuel_limit] = [p.s.generator.fuel_avail_gal]
        end
        if prime_kw > 0
            fuel_slope, fuel_intercept = fuel_slope_and_intercept(
                electric_efficiency_full_load=p.s.chp.electric_efficiency_full_load, 
                electric_efficiency_half_load=p.s.chp.electric_efficiency_half_load,
                fuel_higher_heating_value_kwh_per_unit=1
	        )
            r2[:generator_fuel_burn_rate_per_kwh] = [fuel_slope]
            r2[:generator_fuel_intercept_per_hr] = [fuel_intercept]
            r2[:fuel_limit] = [1e9]
        end
    end
    return r2
end

"""
    backup_reliability_inputs(;r::Dict)::Dict

Return a dictionary of inputs required for backup reliability calculations. 
***NOTE*** PV production only added if battery storage is also available to manage variability

# Arguments
- `r::Dict`: Dictionary of inputs for reliability calculations.
    inputs of r:
    -critical_loads_kw::Array                                                   Critical loads per time step. (Required input)
    -microgrid_only::Bool = false                                               Boolean to specify if only microgrid upgraded technologies run during grid outage 
    -chp_size_kw::Real                                                          CHP capacity. 
    -pv_size_kw::Real                                                           Size of PV System
    -pv_production_factor_series::Array                                         PV production factor per time step (required if pv_size_kw in dictionary)
    -pv_migrogrid_upgraded::Bool = false                                        If false then PV isn't used during outage if microgrid_only = TRUE (defaults to false)
    -wind_size_kw::Real                                                         Size of Wind System
    -wind_production_factor_series::Array                                       Wind production factor per time step (required if wind_size_kw in dictionary)
    -wind_migrogrid_upgraded::Bool = false                                      If false then Wind isn't used during outage if microgrid_only = TRUE (defaults to false)
    -battery_operational_availability::Real = 0.97                              Likelihood battery will be available at start of outage       
    -pv_operational_availability::Real = 0.98                                   Likelihood PV will be available at start of outage
    -wind_operational_availability::Real = 0.97                                 Likelihood Wind will be available at start of outage
    -battery_size_kwh::Real                                                     Battery energy storage capacity
    -battery_size_kw::Real                                                      Battery power capacity
    -battery_charge_efficiency::Real                                            Battery charge efficiency
    -battery_discharge_efficiency::Real                                         Battery discharge efficiency
    -battery_starting_soc_series_fraction                                       Battery state of charge in each time step (if not input then defaults to battery size)
    -battery_minimum_soc_fraction = 0.0                                         The minimum battery state of charge (represented as a fraction) allowed during outages.
    -generator_operational_availability::Union{Real, Vector{<:Real}} = 0.995    Likelihood generator being available in given time step
    -generator_failure_to_start::Union{Real, Vector{<:Real}} = 0.0094           Chance of generator starting given outage
    -generator_mean_time_to_failure::Union{Real, Vector{<:Real}} = 1100         Average number of time steps between a generator's failures. 1/(failure to run probability). 
    -num_generators::Union{Int, Vector{Int}} = 1                                Number of generators. 
    -generator_size_kw::Union{Real, Vector{<:Real}} = 0.0                       Backup generator capacity.
    -num_battery_bins::Int                                                      Number of bins for discretely modeling battery state of charge
    -max_outage_duration::Int = 96                                              Maximum outage duration modeled
    -fuel_limit:Union{Real, Vector{<:Real}} = 1e9                               Amount of fuel available, either by generator type or per generator, depending on fuel_limit_is_per_generator. Change generator_fuel_burn_rate_per_kwh for different fuel efficiencies. Fuel units should be consistent with generator_fuel_intercept_per_hr and generator_fuel_burn_rate_per_kwh.
    -generator_fuel_intercept_per_hr::Union{Real, Vector{<:Real}} = 0.0         Amount of fuel burned each time step while idling. Fuel units should be consistent with fuel_limit and generator_fuel_burn_rate_per_kwh.
    -fuel_limit_is_per_generator::Union{Real, Vector{<:Real}} = false           Boolean to determine whether fuel limit is given per generator or per generator type
    -generator_fuel_burn_rate_per_kwh::Union{Real, Vector{<:Real}} = 0.076      Amount of fuel used per kWh generated. Fuel units should be consistent with fuel_limit and generator_fuel_intercept_per_hr.
    
#Examples
```repl-julia
julia> r = Dict("critical_loads_kw" => [1,2,1,1], "generator_operational_availability" => 1, "generator_failure_to_start" => 0.0,
                "generator_mean_time_to_failure" => 5, "num_generators" => 2, "generator_size_kw" => 1, 
                "max_outage_duration" => 3, "battery_size_kw" =>2, "battery_size_kwh" => 4)
julia>    backup_reliability_inputs(r = r)
Dict{Any, Any} with 11 entries:
  :num_generators                       => 2
  :battery_starting_soc_kwh             => [4.0, 4.0, 4.0, 4.0]
  :max_outage_duration                  => 3
  :generator_size_kw                    => 1
  :generator_failure_to_start           => 0.0
  :battery_size_kwh                     => 4
  :battery_size_kw                      => 2
  :net_critical_loads_kw                => Real[1.0, 2.0, 1.0, 1.0]
  :generator_mean_time_to_failure       => 5
  :generator_operational_availability   => 1
  :critical_loads_kw                    => Real[1.0, 2.0, 1.0, 1.0]
```
"""
function backup_reliability_inputs(;r::Dict)::Dict

    invalid_args = String[]
    r2 = dictkeys_tosymbols(r)

    if haskey(r2, :generator_size_kw)
        num_gen_types = length(r2[:generator_size_kw])
        get!(r2, :fuel_limit, [1e9 for _ in 1:num_gen_types])
        get!(r2, :generator_fuel_intercept_per_hr, [0.0 for _ in 1:num_gen_types])
        get!(r2, :generator_fuel_burn_rate_per_kwh, [0.076 for _ in 1:num_gen_types]) 
    end

    microgrid_only = get(r2, :microgrid_only, false)

    wind_size_kw = get(r2, :wind_size_kw, 0.0) 
    if wind_size_kw > 0
        if haskey(r2, :wind_production_factor_series)
            if length(r2[:wind_production_factor_series]) != length(r2[:critical_loads_kw])
                push!(invalid_args, "The lengths of wind_production_factor_series and critical_loads_kw do not match.")
            end
            if !microgrid_only || Bool(get(r2, :wind_migrogrid_upgraded, false))
                r2[:wind_kw_ac_time_series] = wind_size_kw .* r2[:wind_production_factor_series]
            end
        else
            push!(invalid_args, "Non-zero wind_size_kw is included in inputs but no wind_production_factor_series is provided.")
        end
    end

    pv_size_kw = get(r2, :pv_size_kw, 0.0) 
    if pv_size_kw > 0
        if haskey(r2, :pv_production_factor_series)
            if length(r2[:pv_production_factor_series]) != length(r2[:critical_loads_kw])
                push!(invalid_args, "The lengths of pv_production_factor_series and critical_loads_kw do not match.")
            end
            if !microgrid_only || Bool(get(r2, :pv_migrogrid_upgraded, false))
                r2[:pv_kw_ac_time_series] = pv_size_kw .* r2[:pv_production_factor_series]
            end
        else
            push!(invalid_args, "Non-zero pv_size_kw is included in inputs but no pv_production_factor_series is provided.")
        end
    end

    if haskey(r2, :battery_size_kw)
        if !microgrid_only || Bool(get(r2, :storage_microgrid_upgraded, false))
            #check if minimum state of charge added. If so, then change battery size to effective size, and reduce starting SOC accordingly
            if haskey(r2, :battery_starting_soc_series_fraction) 
                init_soc = r2[:battery_starting_soc_series_fraction]
            else
                @warn("No battery soc series provided to reliability inputs. Assuming battery fully charged at start of outage.")
                init_soc = ones(length(r2[:critical_loads_kw]))
            end
            r2[:battery_starting_soc_kwh] = init_soc .* r2[:battery_size_kwh]
            
            if haskey(r2, :battery_minimum_soc_fraction) 
                battery_minimum_soc_kwh = r2[:battery_size_kwh] * r2[:battery_minimum_soc_fraction]
                r2[:battery_size_kwh] -= battery_minimum_soc_kwh
                if minimum(r2[:battery_starting_soc_kwh]) < battery_minimum_soc_kwh
                    @warn("Some battery starting states of charge are less than the provided minimum state of charge.")
                end
                r2[:battery_starting_soc_kwh] .-= battery_minimum_soc_kwh
            end
            
            if !haskey(r2, :battery_size_kwh)
                push!(invalid_args, "Battery kW provided to reliability inputs but no kWh provided.")
            end
        end
    end

    if length(invalid_args) > 0
        error("Invalid argument values: $(invalid_args)")
    end

    return r2
end

"""
    backup_reliability_single_run(; critical_loads_kw::Vector, generator_operational_availability::Vector{<:Real} = [0.995], generator_failure_to_start::Vector{<:Real} = [0.0094], 
        generator_mean_time_to_failure::Vector{<:Real} = [1100], num_generators::Vector{Int} = [1], generator_size_kw::Vector{<:Real} = [0.0], num_battery_bins::Int = 101, max_outage_duration::Int = 96,
        battery_size_kw::Real = 0.0, battery_size_kwh::Real = 0.0, battery_charge_efficiency::Real = 0.948, battery_discharge_efficiency::Real = 0.948, time_steps_per_hour::Real = 1)::Matrix

Return an array of backup reliability calculations. Inputs can be unpacked from backup_reliability_inputs() dictionary
# Arguments
-net_critical_loads_kw::Vector                     Vector of net critical loads                     
-battery_starting_soc_kwh::Vector   = []           Battery kWh state of charge time series during normal grid-connected usage
-generator_operational_availability::Vector{<:Real}    = [0.995]         Fraction of year generators not down for maintenance
-generator_failure_to_start::Vector{<:Real}            = [0.0094]        Chance of generator starting given outage
-generator_mean_time_to_failure::Vector{<:Real}        = [1100]          Average number of time steps between a generator's failures. 1/(failure to run probability). 
-num_generators::Vector{Int}                            = [1]             Number of generators
-generator_size_kw::Vector{<:Real}                     = [0.0]           Backup generator capacity
-num_battery_bins::Int              = num_battery_bins_default(battery_size_kw,battery_size_kwh)     Number of bins for discretely modeling battery state of charge
-max_outage_duration::Int           = 96           Maximum outage duration modeled
-battery_size_kw::Real              = 0.0          Battery kW of power capacity
-battery_size_kwh::Real             = 0.0          Battery kWh of energy capacity
-battery_charge_efficiency::Real    = 0.948        Efficiency of charging battery
-battery_discharge_efficiency::Real = 0.948        Efficiency of discharging battery
-time_steps_per_hour::Real          = 1            Used to determine amount battery gets shifted.
```
"""
function backup_reliability_single_run(; 
    net_critical_loads_kw::Vector, 
    battery_starting_soc_kwh::Vector = [],
    generator_operational_availability::Vector{<:Real} = [0.995], 
    generator_failure_to_start::Vector{<:Real} = [0.0094], 
    generator_mean_time_to_failure::Vector{<:Real} = [1100], 
    num_generators::Vector{Int} = [1], 
    generator_size_kw::Vector{<:Real} = [0.0], 
    max_outage_duration::Int = 96,
    battery_size_kw::Real = 0.0,
    battery_size_kwh::Real = 0.0,
    num_battery_bins::Int = num_battery_bins_default(battery_size_kw,battery_size_kwh),
    battery_charge_efficiency::Real = 0.948, 
    battery_discharge_efficiency::Real = 0.948,
    time_steps_per_hour::Real = 1,
    kwargs...)::Matrix
     
    #No reliability calculations if no outage duration
    if max_outage_duration == 0
        return []
    
    elseif battery_size_kw < 0.1
        return survival_gen_only(
                net_critical_loads_kw=net_critical_loads_kw,
                generator_operational_availability=generator_operational_availability, 
                generator_failure_to_start=generator_failure_to_start, 
                generator_mean_time_to_failure=generator_mean_time_to_failure, 
                num_generators=num_generators, 
                generator_size_kw=generator_size_kw, 
                max_outage_duration=max_outage_duration, 
                marginal_survival = false)

    else
        return survival_with_battery(
                net_critical_loads_kw=net_critical_loads_kw,
                battery_starting_soc_kwh=battery_starting_soc_kwh, 
                generator_operational_availability=generator_operational_availability, 
                generator_failure_to_start=generator_failure_to_start, 
                generator_mean_time_to_failure=generator_mean_time_to_failure,
                num_generators=num_generators,
                generator_size_kw=generator_size_kw, 
                battery_size_kw=battery_size_kw,
                battery_size_kwh=battery_size_kwh,
                num_battery_bins=num_battery_bins,
                max_outage_duration=max_outage_duration, 
                battery_charge_efficiency=battery_charge_efficiency,
                battery_discharge_efficiency=battery_discharge_efficiency,
                marginal_survival = false,
                time_steps_per_hour = time_steps_per_hour
            )

    end
end

"""
fuel_use(; net_critical_loads_kw::Vector, num_generators::Vector{Int} = [1], generator_size_kw::Vector{<:Real} = [0.0],
            fuel_limit::Vector{<:Real} = [1e9], generator_fuel_intercept_per_hr::Vector{<:Real} = [0.0],
            fuel_limit_is_per_generator::Vector{Bool} = [false], generator_fuel_burn_rate_per_kwh::Vector{<:Real} = [0.076],
            max_outage_duration::Int = 96, battery_starting_soc_kwh::Vector = [], battery_size_kw::Real = 0.0, battery_size_kwh::Real = 0.0,
            battery_charge_efficiency::Real = 0.948, battery_discharge_efficiency::Real = 0.948, time_steps_per_hour::Int = 1, kwargs...)::Matrix{Int}

# Returns
-A matrix of fuel survival, with rows corresponding to start times and columns to duration.
-The total fuel used, if no components fail.

# Arguments
-net_critical_loads_kw::Vector                                              vector of net critical loads
-num_generators::Vector{Int} = [1],                               number of backup generators of each type
-generator_size_kw::Vector{<:Real} = [0.0],                      capacity of each generator type
-fuel_limit:Vector{<:Real} = [1e9]                               Amount of fuel available, either by generator type or per generator, depending on fuel_limit_is_per_generator. Change generator_fuel_burn_rate_per_kwh for different fuel efficiencies. Fuel units should be consistent with generator_fuel_intercept_per_hr and generator_fuel_burn_rate_per_kwh.
-generator_fuel_intercept_per_hr::Vector{<:Real} = [0.0]        Amount of fuel burned each time step while idling. Fuel units should be consistent with fuel_limit and generator_fuel_burn_rate_per_kwh.
-fuel_limit_is_per_generator::Vector{Bool} = [false]             Boolean to determine whether fuel limit is given per generator or per generator type
-generator_fuel_burn_rate_per_kwh::Vector{<:Real} = [0.076]      Amount of fuel used per kWh generated. Fuel units should be consistent with fuel_limit and generator_fuel_intercept_per_hr.
-max_outage_duration::Int = 96,                                             maximum outage duration
-battery_starting_soc_kwh::Vector = [],                                     battery time series of starting charge
-battery_size_kw::Real = 0.0,                                               inverter capacity of battery
-battery_size_kwh::Real = 0.0,                                              energy capacity of battery
-battery_charge_efficiency::Real = 0.948,                                   battery charging efficiency
-battery_discharge_efficiency::Real = 0.948,                                battery discharge efficiency
-time_steps_per_hour::Real = 1,                                             number of time steps per hour

```
"""
function fuel_use(;    
    net_critical_loads_kw::Vector, 
    num_generators::Vector{Int} = [1], 
    generator_size_kw::Vector{<:Real} = [0.0],
    fuel_limit::Vector{<:Real} = [1e9],
    generator_fuel_intercept_per_hr::Vector{<:Real} = [0.0],
    fuel_limit_is_per_generator::Vector{Bool} = [false],
    generator_fuel_burn_rate_per_kwh::Vector{<:Real} = [0.076],
    max_outage_duration::Int = 96,
    battery_starting_soc_kwh::Vector = [],
    battery_size_kw::Real = 0.0,
    battery_size_kwh::Real = 0.0,
    battery_charge_efficiency::Real = 0.948, 
    battery_discharge_efficiency::Real = 0.948,
    time_steps_per_hour::Real = 1,
    kwargs...
    )::Tuple{Matrix{Int}, Matrix{Float64}}

    fuel_limit = convert.(Float64, fuel_limit)
    if isa(fuel_limit_is_per_generator, Bool)
        if fuel_limit_is_per_generator
            fuel_limit *= num_generators
        end
    else
        for i in eachindex(fuel_limit_is_per_generator)
            if fuel_limit_is_per_generator[i]
                fuel_limit[i] *= num_generators[i]
            end
        end
    end

    generator_fuel_intercept_per_hr = generator_fuel_intercept_per_hr .* num_generators
    # Sort based on ratio of fuel available to fuel burn
    total_generator_capacity_kw = num_generators .* generator_size_kw
    fuel_order = sortperm(fuel_limit ./ (total_generator_capacity_kw .* generator_fuel_burn_rate_per_kwh .+ generator_fuel_intercept_per_hr))
    generator_fuel_burn_rate_per_kwh = generator_fuel_burn_rate_per_kwh[fuel_order] 
    generator_fuel_intercept_per_hr = generator_fuel_intercept_per_hr[fuel_order]
    total_generator_capacity_kw = total_generator_capacity_kw[fuel_order]

    t_max = length(net_critical_loads_kw)
    survival_matrix = zeros(t_max, max_outage_duration) 
    fuel_used = zeros(t_max, length(fuel_limit))

    battery_included = battery_size_kw > 0

    for t in 1:t_max
        fuel_remaining = copy(fuel_limit)

        if battery_included 
            battery_soc_kwh = battery_starting_soc_kwh[t]
        end

        for d in 1:max_outage_duration
            h = mod(t + d - 2, t_max) + 1 #determines index accounting for looping around year
            load_kw = net_critical_loads_kw[h]
            
            if (load_kw < 0) && battery_included && (battery_soc_kwh < battery_size_kwh)  # load is met
                battery_soc_kwh += minimum([
                    battery_size_kwh - battery_soc_kwh,     # room available
                    battery_size_kw / time_steps_per_hour * battery_charge_efficiency,  # inverter capacity
                    -load_kw / time_steps_per_hour * battery_charge_efficiency  # excess energy
                ])
            else  # check if we can meet load with generator then storage
                for i in eachindex(fuel_remaining)
                    remaining_gen = sum(total_generator_capacity_kw[i:end])
                    
                    if remaining_gen == 0
                        generation = 0
                    else
                        generation = minimum([
                            total_generator_capacity_kw[i],  #generator capacity
                            load_kw * total_generator_capacity_kw[i] / remaining_gen, #generator type share of load (spits between remaining generators)
                            maximum([0, (fuel_remaining[i] * time_steps_per_hour - generator_fuel_intercept_per_hr[i]) / generator_fuel_burn_rate_per_kwh[i]]) #fuel remaining
                        ])
                    end

                    fuel_remaining[i] = maximum([0, fuel_remaining[i] - (generation * generator_fuel_burn_rate_per_kwh[i] + generator_fuel_intercept_per_hr[i]) / time_steps_per_hour])  
                    load_kw -= generation
                end

                if battery_included
                    battery_dispatch = minimum([
                            load_kw, 
                            battery_soc_kwh * time_steps_per_hour * battery_discharge_efficiency, 
                            battery_size_kw
                        ])
                    load_kw -= battery_dispatch
                    battery_soc_kwh -= battery_dispatch  / (time_steps_per_hour * battery_discharge_efficiency)
                end
            end
            if (d > 1 && survival_matrix[t, d-1] == 0) || round(load_kw, digits=5) > 0  # failed to meet load in this time step or any previous
                survival_matrix[t, d] = 0
            else
                survival_matrix[t, d] = 1
            end
        end
        fuel_used[t,:] = fuel_limit - fuel_remaining
    end

    return survival_matrix, fuel_used
end

"""
    return_backup_reliability(; critical_loads_kw::Vector, battery_operational_availability::Real = 0.97,
            pv_operational_availability::Real = 0.98, wind_operational_availability::Real = 0.97,
            pv_kw_ac_time_series::Vector = [], wind_kw_ac_time_series::Vector = [],
            pv_can_dispatch_without_battery::Bool = false, wind_can_dispatch_without_battery::Bool= false, 
            battery_size_kw::Real = 0.0, battery_size_kwh::Real = 0.0, kwargs...)
Return an array of backup reliability calculations, accounting for operational availability of PV and battery. 
# Arguments
-critical_loads_kw::Vector                          Vector of critical loads
-battery_operational_availability::Real = 0.97      Likelihood battery will be available at start of outage       
-pv_operational_availability::Real      = 0.98      Likelihood PV will be available at start of outage
-wind_operational_availability::Real    = 0.97      Likelihood Wind will be available at start of outage
-pv_kw_ac_time_series::Vector = []                  timeseries of PV dispatch
-wind_kw_ac_time_series::Vector = []                timeseries of Wind dispatch
-pv_can_dispatch_without_battery::Bool  = false     Boolian determining whether net load subtracts PV if battery is unavailable.
-wind_can_dispatch_without_battery::Bool= false     Boolian determining whether net load subtracts Wind if battery is unavailable.
-battery_size_kw::Real                  = 0.0       Battery kW of power capacity
-battery_size_kwh::Real                 = 0.0       Battery kWh of energy capacity
-kwargs::Dict                                       Dictionary of additional inputs.  
```
"""

function return_backup_reliability(;
    critical_loads_kw::Vector, 
    battery_operational_availability::Real = 0.97,
    pv_operational_availability::Real = 0.98,
    pv_can_dispatch_without_battery::Bool = false,
    wind_operational_availability::Real = 0.97,
    wind_can_dispatch_without_battery::Bool = false,
    battery_size_kw::Real = 0.0,
    battery_size_kwh::Real = 0.0,
    kwargs...)

    
    net_critical_loads_pv = critical_loads_kw
    net_critical_loads_wind = critical_loads_kw
    net_critical_loads_pv_wind = critical_loads_kw
    if haskey(kwargs, :pv_kw_ac_time_series)
        pv_included = true
        net_critical_loads_pv -= kwargs[:pv_kw_ac_time_series]
        net_critical_loads_pv_wind -= kwargs[:pv_kw_ac_time_series]
    else
        pv_included = false
    end
    if haskey(kwargs, :wind_kw_ac_time_series)
        wind_included = true
        net_critical_loads_wind -= kwargs[:wind_kw_ac_time_series]
        net_critical_loads_pv_wind -= kwargs[:wind_kw_ac_time_series]
    else
        wind_included = false
    end
    
    system_characteristics = Dict(
        "gen" => Dict(
            "probability" => (pv_included && pv_can_dispatch_without_battery ? 1 - pv_operational_availability : 1) *
                            (wind_included && wind_can_dispatch_without_battery ? 1 - wind_operational_availability : 1) *
                            (battery_size_kwh > 0 ? 1 - battery_operational_availability : 1),
            "net_critical_loads_kw" => critical_loads_kw,
            "battery_size_kw" => 0,
            "battery_size_kwh" => 0),
        "gen_pv_battery" => Dict(
            "probability" => pv_included * pv_operational_availability *
                            (wind_included ? 1 - wind_operational_availability : 1) *
                            (battery_size_kwh > 0) * battery_operational_availability,
            "net_critical_loads_kw" => net_critical_loads_pv,
            "battery_size_kw" => battery_size_kw,
            "battery_size_kwh" => battery_size_kwh),
        "gen_battery" => Dict(
            "probability" => (pv_included ? 1 - pv_operational_availability : 1) *
                            (wind_included ? 1 - wind_operational_availability : 1) *
                            (battery_size_kwh > 0) * battery_operational_availability,
            "net_critical_loads_kw" => critical_loads_kw,
            "battery_size_kw" => battery_size_kw,
            "battery_size_kwh" => battery_size_kwh),
        "gen_pv" => Dict(
            "probability" => (pv_included && pv_can_dispatch_without_battery) * pv_operational_availability *
                            (wind_included && wind_can_dispatch_without_battery ? 1 - wind_operational_availability : 1) *
                            (battery_size_kwh > 0 ? 1 - battery_operational_availability : 1),
            "net_critical_loads_kw" => net_critical_loads_pv,
            "battery_size_kw" => 0,
            "battery_size_kwh" => 0),
        "gen_wind" => Dict(
            "probability" => (pv_included && pv_can_dispatch_without_battery ? 1 - pv_operational_availability : 1) *
                            (wind_included && wind_can_dispatch_without_battery) * wind_operational_availability *
                            (battery_size_kwh > 0 ? 1 - battery_operational_availability : 1),
            "net_critical_loads_kw" => net_critical_loads_wind,
            "battery_size_kw" => 0,
            "battery_size_kwh" => 0),
        "gen_pv_battery_wind" => Dict(
            "probability" => pv_included * pv_operational_availability *
                            wind_included * wind_operational_availability *
                            (battery_size_kwh > 0) * battery_operational_availability,
            "net_critical_loads_kw" => net_critical_loads_pv_wind,
            "battery_size_kw" => battery_size_kw,
            "battery_size_kwh" => battery_size_kwh),
        "gen_battery_wind" => Dict(
            "probability" => (pv_included ? 1 - pv_operational_availability : 1) *
                            wind_included * wind_operational_availability *
                            (battery_size_kwh > 0) * battery_operational_availability,
            "net_critical_loads_kw" => net_critical_loads_wind,
            "battery_size_kw" => battery_size_kw,
            "battery_size_kwh" => battery_size_kwh),
        "gen_pv_wind" => Dict(
            "probability" => (pv_included && pv_can_dispatch_without_battery) * pv_operational_availability *
                            (wind_included && wind_can_dispatch_without_battery) * wind_operational_availability *
                            (battery_size_kwh > 0 ? 1 - battery_operational_availability : 1),
            "net_critical_loads_kw" => net_critical_loads_pv_wind,
            "battery_size_kw" => 0,
            "battery_size_kwh" => 0)
    )
    
    results_no_fuel_limit = []
    for (description, system) in system_characteristics
        if system["probability"] != 0
            run_survival_probs = backup_reliability_single_run(;
                net_critical_loads_kw = system["net_critical_loads_kw"],
                battery_size_kw = system["battery_size_kw"],
                battery_size_kwh = system["battery_size_kwh"],
                kwargs...)
            #If no results then add results, else append to them
            if length(results_no_fuel_limit) == 0
                #survival probs weighted by probability
                results_no_fuel_limit = run_survival_probs .* system["probability"]
            else
                results_no_fuel_limit += run_survival_probs .* system["probability"]
            end
        end
    end

    fuel_survival, fuel_used = fuel_use(; net_critical_loads_kw = net_critical_loads_pv_wind, battery_size_kw=battery_size_kw, battery_size_kwh=battery_size_kwh, kwargs...)
    return results_no_fuel_limit, fuel_survival, fuel_used
end

"""
process_reliability_results(cumulative_results::Matrix, fuel_survival::Matrix, fuel_used::Matrix)::Dict

Return dictionary of processed backup reliability results.

# Arguments
- `cumulative_results::Matrix`: cumulative survival probabilities matrix from function return_backup_reliability. 
- `fuel_survival::Matrix`: fuel survival probabilities matrix from function return_backup_reliability.
- `fuel_used::Vector`: quantity of fuels used in outage of max duration for each start time.
"""
function process_reliability_results(cumulative_results::Matrix, fuel_survival::Matrix, fuel_used::Matrix)::Dict
    cumulative_duration_means = round.(vec(mean(cumulative_results, dims = 1)), digits=6)
    cumulative_duration_mins = round.(vec(minimum(cumulative_results, dims = 1)), digits=6)
    cumulative_final_resilience = round.(cumulative_results[:, end], digits=6)
    fuel_duration_means = round.(vec(mean(fuel_survival, dims = 1)), digits =6)
    fuel_final_survival = round.(fuel_survival[:, end], digits=6)

    total_cumulative_duration_means = round.(vec(mean(cumulative_results .* fuel_survival, dims = 1)), digits=6)
    total_cumulative_duration_mins = round.(vec(minimum(cumulative_results .* fuel_survival, dims = 1)), digits=6)
    total_cumulative_final_resilience = round.(cumulative_results[:,end] .* fuel_survival[:,end], digits=6)

    total_cumulative_final_resilience_mean = round(mean(total_cumulative_final_resilience), digits=6)
    time_steps_per_hour = length(total_cumulative_final_resilience)/8760
    if time_steps_per_hour < 1
        calc_monthly_quartiles = false
    else
        calc_monthly_quartiles = true
        total_cumulative_final_resilience_monthly = zeros(12,5)
        ts_by_month = get_monthly_time_steps(2022; time_steps_per_hour=time_steps_per_hour)
        for mth in 1:12
            t0 = Int(ts_by_month[mth][1])
            tf = Int(ts_by_month[mth][end])
            total_cumulative_final_resilience_monthly[mth,:] = quantile(total_cumulative_final_resilience[t0:tf], (0:4)/4)
        end
    end
    return Dict(
        "unlimited_fuel_mean_cumulative_survival_by_duration" => cumulative_duration_means,
        "unlimited_fuel_min_cumulative_survival_by_duration" => cumulative_duration_mins,
        "unlimited_fuel_cumulative_survival_final_time_step" => cumulative_final_resilience,

        "mean_fuel_survival_by_duration" => fuel_duration_means,
        "fuel_survival_final_time_step" => fuel_final_survival,

        "mean_cumulative_survival_by_duration" => total_cumulative_duration_means,
        "min_cumulative_survival_by_duration" => total_cumulative_duration_mins,
        "cumulative_survival_final_time_step" => total_cumulative_final_resilience,

        "mean_cumulative_survival_final_time_step" => total_cumulative_final_resilience_mean,
        
        "monthly_min_cumulative_survival_final_time_step" => calc_monthly_quartiles ? total_cumulative_final_resilience_monthly[:,1] : [],
        "monthly_lower_quartile_cumulative_survival_final_time_step" => calc_monthly_quartiles ? total_cumulative_final_resilience_monthly[:,2] : [],
        "monthly_median_cumulative_survival_final_time_step" => calc_monthly_quartiles ? total_cumulative_final_resilience_monthly[:,3] : [],
        "monthly_upper_quartile_cumulative_survival_final_time_step" => calc_monthly_quartiles ? total_cumulative_final_resilience_monthly[:,4] : [],
        "monthly_max_cumulative_survival_final_time_step" => calc_monthly_quartiles ? total_cumulative_final_resilience_monthly[:,5] : []
    )
end


"""
	backup_reliability(d::Dict, p::REoptInputs, r::Dict)

Return dictionary of backup reliability results.

# Arguments
- `d::Dict`: REopt results dictionary. Subhourly time steps are not yet supported.
- `p::REoptInputs`: REopt Inputs Struct.
- `r::Dict`: Dictionary of inputs for reliability calculations. If r not included then uses all defaults. 
Possible keys in r:
    -generator_operational_availability::Real = 0.995       Fraction of year generators not down for maintenance
    -generator_failure_to_start::Real = 0.0094              Chance of generator starting given outage
    -generator_mean_time_to_failure::Real = 1100            Average number of time steps between a generator's failures. 1/(failure to run probability). 
    -num_generators::Int = 1                                Number of generators.
    -generator_size_kw::Real = 0.0                          Backup generator capacity. 
    -num_battery_bins::Int = depends on battery sizing      Number of bins for discretely modeling battery state of charge
    -battery_operational_availability::Real = 0.97          Likelihood battery will be available at start of outage       
    -pv_operational_availability::Real = 0.98               Likelihood PV will be available at start of outage
    -wind_operational_availability::Real = 0.97             Likelihood Wind will be available at start of outage
    -max_outage_duration::Int = 96                          Maximum outage duration modeled
    -microgrid_only::Bool = false                           Determines how generator, PV, and battery act during islanded mode

"""
function backup_reliability(d::Dict, p::REoptInputs, r::Dict)
    reliability_inputs = backup_reliability_reopt_inputs(d=d, p=p, r=r)
    cumulative_results, fuel_survival, fuel_used = return_backup_reliability(; reliability_inputs... )
    process_reliability_results(cumulative_results, fuel_survival, fuel_used)
end


"""
	backup_reliability(r::Dict)

Return dictionary of backup reliability results.

# Arguments
- `r::Dict`: Dictionary of inputs for reliability calculations. If r not included then uses all defaults. 
Possible keys in r:
-critical_loads_kw::Array                               Critical loads per time step. Must be hourly and have length of 8760. (Required input)
-microgrid_only::Bool                                   Boolean to check if only microgrid runs during grid outage (defaults to false)
-chp_size_kw::Real                                      CHP capacity. 
-pv_size_kw::Real                                       Size of PV System
-pv_production_factor_series::Array                     PV production factor per time step. Must be hourly and have length of 8760. (Required if pv_size_kw in dictionary)
-pv_migrogrid_upgraded::Bool                            If true then PV runs during outage if microgrid_only = TRUE (defaults to false)
-battery_size_kw::Real                                  Battery capacity. If no battery installed then PV disconnects from system during outage
-battery_size_kwh::Real                                 Battery energy storage capacity
-battery_charge_efficiency::Real                        Battery charge efficiency
-battery_discharge_efficiency::Real                     Battery discharge efficiency
-battery_starting_soc_series_fraction::Array            Battery percent state of charge time series during normal grid-connected usage. Must be hourly and have length of 8760.
-generator_failure_to_start::Real = 0.0094              Chance of generator starting given outage
-generator_mean_time_to_failure::Real = 1100            Average number of time steps between a generator's failures. 1/(failure to run probability). 
-num_generators::Int = 1                                Number of generators. 
-generator_size_kw::Real = 0.0                          Backup generator capacity. 
-num_battery_bins::Int = num_battery_bins_default(r[:battery_size_kw],r[:battery_size_kwh])     Number of bins for discretely modeling battery state of charge
-max_outage_duration::Int = 96                          Maximum outage duration modeled

"""
function backup_reliability(r::Dict)
    reliability_inputs = backup_reliability_inputs(r=r)
	cumulative_results, fuel_survival, fuel_used = return_backup_reliability(; reliability_inputs... )
	process_reliability_results(cumulative_results, fuel_survival, fuel_used)
end


function num_battery_bins_default(size_kw::Real, size_kwh::Real)::Int
    if size_kw == 0
        return 1
    else
        duration = size_kwh / size_kw
        return round(Int, duration * 20)
    end
end