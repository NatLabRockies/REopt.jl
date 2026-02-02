# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
Captures high-level inputs affecting the optimization.

`Settings` is an optional REopt input with the following keys and default values:
```julia
    time_steps_per_hour::Int = 1 # corresponds to the time steps per hour for user-provided time series (e.g., `ElectricLoad.loads_kw` and `DomesticHotWaterLoad.fuel_loads_mmbtu_per_hour`) 
    add_soc_incentive::Bool = true # when true, an incentive is added to the model's objective function to keep the ElectricStorage SOC high
    off_grid_flag::Bool = false # true if modeling an off-grid system, not connected to bulk power system
    include_climate_in_objective::Bool = false # true if climate costs of emissions should be included in the model's objective function
    include_health_in_objective::Bool = false # true if health costs of emissions should be included in the model's objective function
    solver_name::String = "HiGHS" # solver used to obtain a solution to model instance. available options: ["HiGHS", "Cbc", "CPLEX", "Xpress"]
```
"""
Base.@kwdef struct Settings
    time_steps_per_hour::Int = 1 # corresponds to the time steps per hour for user-provided time series (e.g., `ElectricLoad.loads_kw` and `DomesticHotWaterLoad.fuel_loads_mmbtu_per_hour`) 
    add_soc_incentive::Bool = true # when true, an incentive is added to the model's objective function to keep the ElectricStorage SOC high
    off_grid_flag::Bool = false # true if modeling an off-grid system, not connected to bulk power system
    include_climate_in_objective::Bool = false # true if climate costs of emissions should be included in the model's objective function
    include_health_in_objective::Bool = false # true if health costs of emissions should be included in the model's objective function
    solver_name::String = "HiGHS" # solver used to obtain a solution to model instance. available options: ["HiGHS", "Cbc", "CPLEX", "Xpress"]
    include_export_cost_series_in_results::Bool = false # set to true to add electricity export compensation rate timeseries under electric tariff results.
end
