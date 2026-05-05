# [Methods](@id reopt-methods)
The primary method for using REopt is the `run_reopt` method. In the simplest there are two required inputs to `run_reopt`: a `JuMP.Model` with an optimizer and the path to a JSON file to define the `Scenario`. Other methods for `run_reopt` are enumerated below. Other methods such as `build_reopt!` are also described to allow users to build custom REopt models. For example, after using `build_reopt!` a user could add constraints or change the objective function using `JuMP` commands.

## run_reopt
```@docs
run_reopt
```

## build_reopt!
```@docs
build_reopt!
```

## simulate_outages
```@docs
simulate_outages
```

## backup_reliability
```@docs
backup_reliability
```