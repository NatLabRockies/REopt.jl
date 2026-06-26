# Design Concepts for the REopt Module
At a high level each REopt model consists of four major components:
1. The [Scenario](@ref) as defined by the user's inputs and default values.
2. The [REoptInputs](@ref), which convert the `Scenario` into the necessary values for the REopt mathematical program.
3. The REopt Model (built [here](https://github.com/NatLabRockies/REopt/blob/master/src/core/reopt.jl)), which includes all the constraints and the objective function that are built using the [REoptInputs](@ref)
4. And the [results](https://github.com/NatLabRockies/REopt/blob/master/src/results/results.jl), which are returned to the user and derived from the optimal solution of the REopt Model.

The REopt Model is built via the [build_reopt!](@ref) method. However, the [run_reopt](@ref) method includes `build_reopt!` within it so typically a user does not need to directly call `build_reopt!` (unless they wish to modify the model before solving it, eg. by adding a constraint).

[run_reopt](@ref) is the main interface for users.

## Technology size constraints

### Upper size limits
The `max_kw` input value for any technology is considered to be the maximum _additional_ capacity that may be installed beyond the `existing_kw`. Note also that the `Site` space constraints (`roof_squarefeet` and `land_acres`) for `PV` technologies can be less than the provided `max_kw` value.

### Lower size limits
The `min_kw` input value for any technology sets the lower bound on the capacity. If `min_kw` is non-zero then the model will be forced to choose at least that system size. The `min_kw` value is set equal to the `existing_kw` value in the Business As Usual scenario.

# Business As Usual Scenario
In order to calculate the Net Present Value of the optimal solution, as well as other baseline metrics, one can optionally run the Business As Usual (BAU) scenario. When an array of `JuMP.Model`s is provided to `run_reopt` the BAU scenario is also run. For example:
```julia
m1 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
m2 = Model(optimizer_with_attributes(Xpress.Optimizer, "OUTPUTLOG" => 0))
results = run_reopt([m1,m2], "./scenarios/pv_storage.json")
```

The BAU scenario is created by modifying the [REoptInputs](@ref) (created from the user's [Scenario](@ref)). In the BAU scenario we have the following assumptions:
- Each existing technology has zero capital cost, but does have operations and maintenance costs.
- The [ElectricTariff](@ref), [Financial](@ref), [Site](@ref), [ElectricLoad](@ref), and [ElectricUtility](@ref) inputs are the same as the optimal case.
- The `min_kw` and `max_kw` values are set to the `existing_kw` value.