# [Inputs](@id mpc-inputs)
The input structure for MPC models is very similar to the structure for [REopt Inputs](@ref reopt-inputs). The primary differences are 

1. The [MPCElectricTariff](@ref) requires specifying individual rate components (and does not parse URDB rates like [ElectricTariff](@ref)).

2. The capacities of any provided DER must be provided

3. The load profile for each time step must be provided

Just like [REopt Inputs](@ref reopt-inputs), inputs to `run_mpc` can be provided in one of three formats:
1. a file path (string) to a JSON file,
2. a `Dict`, or
3. using the `MPCInputs` struct

The accepted keys for the JSON file or `Dict` are:
- ElectricLoad
- ElectricTariff
- PV
- ElectricStorage
- Financial
- Generator
- ElectricUtility
- Settings


The simplest scenario does not have any dispatch optimization and is essentially a cost "calculator":
```javascript
{
    "ElectricLoad": {
        "loads_kw": [10.0, 11.0, 12.0]
    },
    "ElectricTariff": {
        "energy_rates": [0.1, 0.2, 0.3]
    }
}
```
!!! note
    The `ElectricLoad.loads_kw` can have an arbitrary length, but its length must be the same lengths as many other inputs such as the `MPCElectricTariff.energy_rates` and the `PV.production_factor_series`.

!!! note
    Net metering or net billing (wholesale) can be applied in MPC in the same manner they are applied in a typical REopt run. To utilize net metering in MPC, set `ElectricUtility.net_metering_limit_kw` > 0, and specify which MPC techs can_net_meter. Note that under net metering, REopt MPC will not export more than grid consumption within the defined horizon (rather than within a year, as in src/core). Note also that MPC will choose between the NEM and WHL bins for each horizon iteration.

Here is a more complex `MPCScenario`, which is used in [Examples](@ref mpc-examples):
```javascript
{
    "PV": {
        "size_kw": 150,
        "production_factor_series": [
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.05,
            0.10,
            0.15,
            0.30,
            0.6,
            0.5,
            0.3,
            0.02,
            0.01,
            0.005,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0
        ],
        "can_net_meter": false
    },
    "ElectricStorage": {
        "size_kw": 30.0,
        "size_kwh": 60.0,
        "can_grid_charge": true
    },
    "ElectricLoad": {
        "loads_kw": [
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100,
            100
        ]
    },
    "ElectricTariff": {
        "energy_rates": [
            0.1,
            0.1,
            0.1,
            0.1,
            0.1,
            0.1,
            0.15,
            0.15,
            0.15,
            0.15,
            0.15,
            0.15,
            0.15,
            0.2,
            0.2,
            0.2,
            0.3,
            0.2,
            0.2,
            0.2,
            0.1,
            0.1,
            0.1,
            0.1
        ],
        "monthly_demand_rates": [10.0],
        "monthly_previous_peak_demands": [98.0],
        "tou_demand_rates": [0.0, 15.0],
        "tou_demand_time_steps": [
            [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], 
            [16, 17, 18, 19, 20, 21, 22, 23, 24]
        ],
        "tou_previous_peak_demands": [98.0, 97.0],
        "wholesale_rate": [0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 
            0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]
    },
    "ElectricUtility" : {
        "net_metering_limit_kw": 0.0
    }
}
```

# MPC Input Structures
Note that the keys of the input `Dict` or JSON file do not need the `MPC` prefix. 

## MPCElectricTariff
```@docs
REopt.MPCElectricTariff(d::Dict)
```

## MPCElectricLoad
```@docs
REopt.MPCElectricLoad
```

## MPCElectricStorage
```@docs
REopt.MPCElectricStorage
```

## MPCFinancial
```@docs
REopt.MPCFinancial
```

## MPCPV
```@docs
REopt.MPCPV
```

## MPCGenerator
```@docs
REopt.MPCGenerator
```

## MPCSettings
The MPCSettings is the same as the [Settings](@ref).


## MPCLimits
```@docs
REopt.MPCLimits
```