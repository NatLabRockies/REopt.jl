# Adding a Technology
REopt can be used in many ways, but its primary use is to evaluate the techno-economic feasibility of energy generation and storage technologies. In this section we describe how one might add a new technology to the REopt model for evaluation. At a high level the steps are:
1. Define the mathematical model for how the technology will interact with the other technologies, which includes:
    - defining appropriate decision variables (the technology's capacity for example)
    - defining model constraints (operational constraints for example)
2. Define the inputs and default values necessary to model the technology in the mathematical model
3. Map the input values to the sets and coefficients needed in the mathematical model
4. Create an adapter function to output the desired results from the mathematical model
5. Test the new technology
6. Document the new inputs and outputs functions
All steps are not necessarily executed in this order and in fact most likely must be done in concert. For example, in order to define a model constraint one must define the input parameters. Also, it is good practice to think of how you will test the new technology from the very beginning of the design process and incrementally test your additions to the model as well as make sure that no existing tests fail due to your modifications to REopt.

## 1. Mathematical Model
Each technology will have unique decision variables and constraints. However, there are some decision variables that apply to many technologies. We will use the `PV` technology to demonstrate some variables and constraints that are shared among all generation technologies and some that are unique to `PV`.

First, the `PV` technology can meet electrical demand and thus is part of the `techs.elec`. By including the `PV` technology in the set of `techs.elec` we can take advantage of existing model constraints such as the electrical load balance:
```julia
@constraint(m, [ts in p.time_steps_with_grid],
    sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.elec) 
    + sum( m[Symbol("dvDischargeFromStorage"*_n)][b,ts] for b in p.s.storage.types.elec ) 
    + sum(m[Symbol("dvGridPurchase"*_n)][ts, tier] for tier in 1:p.s.electric_tariff.n_energy_tiers) 
    ==
    sum( sum(m[Symbol("dvProductionToStorage"*_n)][b, t, ts] for b in p.s.storage.types.elec) 
    + m[Symbol("dvCurtail"*_n)][t, ts] for t in p.techs.elec)
    + sum(m[Symbol("dvGridToStorage"*_n)][b, ts] for b in p.s.storage.types.elec)
    + p.s.electric_load.loads_kw[ts]
)
```
!!! note
    Throughout the REopt code `p` is used as the variable name for the concrete instance of `REoptInputs`. The `p` is a legacy name from when the `REoptInputs` was called a **p**arameter structure.
    Also, `m` is used throughout the code for the JuMP Model and `p.s` is the `Scenario` structure.

From the load balance constraint we can see that the `PV` technology (and each `techs.elec`) includes input parameters for the `production_factor` and `levelization_factor`, and that the `PV` technology has the decision variables `dvRatedProduction` and `dvCurtail`.

!!! note
    All decision variables in the model start with `dv` and use camel case naming after `dv`. Also, in order to take advantage of dynamic variable names for multinode models we use the `Symbol` notation (e.g. `m[Symbol("dvProductionToStorage"*_n)`) to define and access variables in the model.

The `p.techs` data structure is defined as follows:
### Techs
```@docs
REopt.Techs
REopt.Techs(s::Scenario)
REopt.Techs(p::REoptInputs, s::BAUScenario)
```

From the [Techs](@ref) definition we can see that there are already a lot of different energy generation technology categories in REopt. Adding a new technology to the model could be as simple as adding the appropriate inputs to `REoptInputs` (described in the next section) and using the `Techs` structure to define which variables and constraints apply to the new technology.

The `PV` technology is also part of a unique set of `Techs`, namely the `techs.pv` (there can be multiple `PV` technologies in a single model as we will see soon). An example of a constraint applied over `techs.pv` is:
```julia
@constraint(m, [loc in p.pvlocations],
    sum(m[Symbol("dvSize"*_n)][t] * p.pv_to_location[t][loc] for t in p.techs.pv) <= p.maxsize_pv_locations[loc]
)
```
Here we can see that the `dvSize` for each `techs.pv` is constrained based on the location of each `PV` technology. This constraint allows us to uniquely limit the `PV` capacity for roof mounted systems vs. ground mounted systems based on the available space at a site. We also see some additional inputs for the `PV` technology, such as the `pvlocations` and `maxsize_pv_locations`. Creating these input values is described in the next two sections.

## 2. User Inputs
Any new technology should have a `technologyname.jl` file in the `src/core` directory. For example, in the `src/core/pv.jl` file we have a data structure and constructor for defining default values and creating the `PV` structure that is attached to the [Scenario](@ref). Once the new technology's data structure is defined it must be added to the `Scenario` structure (see `src/core/scenario.jl`). 

When adding a new technology to REopt one must decide on how a user of the REopt will define the technology. Continuing with the `PV` example we saw that we need to define the `production_factor` for the `PV` technology in every time step. The `production_factor` varies from zero to one and defines the availability of the technology. For `PV` we have a default method for creating the `production_factor` as well as allow the user to provide their own `production_factor`.

We let the user define the `production_factor` by providing the `PV`s `production_factor_series` input in their JSON file or dictionary when creating their [Scenario](@ref). If the user does not provide a value for `production_factor_series` then we use the PVWatts API to get a `production_factor` based on the `Site.latitude` and `Site.longitude`. The [PV](@ref) inputs structure also allows the user to change the arguments that are passed to PVWatts.


## 3. REopt Inputs
The [REoptInputs](@ref) constructor is the work-horse for defining all the mathematical model parameters. It converts the user's [Scenario](@ref) into a format that is necessary for adding the model decision variables and constraints.

A major part of the [REoptInputs](@ref) constructor is creating arrays that are indexed on sets of strings (defined in [Techs](@ref)) that allow us to define constraints all applicable technologies. Continuing with the `PV` example, the electrical load balance constraint includes:
```julia
sum(p.production_factor[t, ts] * p.levelization_factor[t] * m[Symbol("dvRatedProduction"*_n)][t,ts] for t in p.techs.elec) 
```
which implies that we need to define a `production_factor` for all `techs.elec` in every time step `ts`. To create the `production_factor` array the [REoptInputs](@ref) constructor first creates an empty array like so:
```julia
production_factor = DenseAxisArray{Float64}(undef, techs.all, 1:length(s.electric_load.loads_kw))
```
and then passes that array to technology specific functions that add their production factors to the `production_factor` array. For example, for `PV` within the `setup_pv_inputs` method we have:
```julia
for pv in s.pvs
    production_factor[pv.name, :] = get_production_factor(pv, s.site.latitude, s.site.longitude)
    ...
end
```
The completed `production_factor` array is then attached to the `REoptInputs` structure so that it can be used as needed to create the mathematical model.

## 4. Results
After adding a new technology to the REopt mathematical model and getting the new inputs set up you can create some results from the optimized model. Some or all of your new results can also be used in a test for the new technology.

All of the results methods are defined in `src/results`, with `src/results/results.jl` containing the main method for creating results. The results are returned to the user as a dictionary. If a user is not modeling your new technology then there is no reason to create any new results. Therefore, in `reopt_results` we have:
```julia
if !isempty(p.techs.pv)
    add_pv_results(m, p, d; _n)
end
```
which uses the model `m` and the `REoptInputs` `p` to add results to the dictionary `d`.
!!! note
    The `_n` argument is used in many places in REopt to optionally modeled multinode scenarios. The default value for `_n` is an empty string. When modeling multiple nodes the `n` in the `_n` string is set to the `Site.node` value, which is an integer. For example, if the `Site.node` is `3` then `_n = "_3"`.

## 5. Testing the new technology
Adding a new test is not necessarily the last step in adding a technology to the REopt model. In fact, it is best to use a simple test to test your code as you add the new technolgy and then adapt the test as you add more capability to the code. For example, once you have created you new technology's input interface you can test just creating a `Scenario` with the new technology by passing the path to a JSON file that contains the minimum required inputs for a Scenario and your new technology. This might look like:
```julia
@testset "My new technology" begin
    s = Scenario("path/to/mynewtech.json")
end
```
The next testing step might be checking the `REoptInputs` additions for your new technolgy:
```julia
@testset "My new technology" begin
    s = Scenario("path/to/mynewtech.json")
    p = REoptInputs(s)
end
```
Once you have all of your new inputs set up you can test the model creation with:
```julia
@testset "My new technology" begin
    m = Model(Cbc.Optimizer)
    build_reopt!(m, "path/to/mynewtech.json")
end
```
Finally, you can test the full work-flow with something like:
```julia
@testset "My new technology" begin
    m = Model(Cbc.Optimizer)
    results = run_reopt(m, "path/to/mynewtech.json")
    @test results["mynewtech"]["some_result"] ≈ 78.9 atol=0.1
end
```

## 6. Documenting
See [Documenting the Code](@ref)
