# REopt Inputs
Inputs to the `run_reopt` function can be provided in one of four formats:
1. a file path (string) to a JSON file,
2. a `Dict`, 
3. using the `Scenario` struct, or
4. using the `REoptInputs` struct

Any one of these types can be passed to the [run_reopt](@ref) method as shown in [Examples](@ref).

The first option is perhaps the most straightforward. For example, the minimum requirements for a JSON scenario file would look like:
```javascript
{
    "Site": {
        "longitude": -118.1164613,
        "latitude": 34.5794343
    },
    "ElectricLoad": {
        "doe_reference_name": "MidriseApartment",
        "annual_kwh": 1000000.0
    },
    "ElectricTariff": {
        "urdb_label": "5ed6c1a15457a3367add15ae"
    }
}
```
The order of the keys does not matter. Note that this scenario does not include any energy generation technologies and therefore the results can be used as a baseline for comparison to scenarios that result in cost-optimal generation technologies (alternatively, a user could include a [BAUScenario](@ref) as shown in [Examples](@ref)).

To add PV to the analysis simply add a PV key with an empty dictionary (to use default values):
```javascript
{
    "Site": {
        "longitude": -118.1164613,
        "latitude": 34.5794343
    },
    "ElectricLoad": {
        "doe_reference_name": "MidriseApartment",
        "annual_kwh": 1000000.0
    },
    "ElectricTariff": {
        "urdb_label": "5ed6c1a15457a3367add15ae"
    },
    "PV": {}
}
```
This scenario will consider the option to purchase a solar PV system to reduce energy costs, and if solar PV can reduce the energy costs then REopt will provide the optimal PV capacity (assuming perfect foresight!). See [PV](@ref) for all available input keys and default values for `PV`. To override a default value, simply specify a value for a given key. For example, the site under consideration might have some existing PV capacity to account for, which can be done by setting the `existing_kw` key to the appropriate value.

## Scenario
The `Scenario` struct captures all of the possible user input keys (see [REopt Inputs](@ref) for potential input formats). A Scenario struct will be automatically created if a `Dict` or file path are supplied to the [run_reopt](@ref) method. Alternatively, a user can create a `Scenario` struct and supply this to [run_reopt](@ref). 
```@docs
Scenario
```

## BAUScenario
The Business-as-usual (BAU) inputs are automatically created based on the `BAUScenario` struct when a user supplies two `JuMP.Model`s to `run_reopt()` (as shown in [Examples](@ref)). The outputs of the BAU scenario are used to calculate comparative results such as the `Financial` net present value (`npv`).
```@docs
REopt.BAUInputs
```

## Settings
```@docs
REopt.Settings
```

## Site
```@docs
REopt.Site
```

## ElectricLoad
```@docs
REopt.ElectricLoad
```

## ElectricTariff
```@docs
REopt.ElectricTariff()
```

## Financial
```@docs
REopt.Financial
```

## ElectricUtility
```@docs
REopt.ElectricUtility
```

## PV
```@docs
REopt.PV
```

## Wind
```@docs
REopt.Wind
```

## ElectricStorage
```@docs
REopt.ElectricStorageDefaults
REopt.Degradation
```

## Generator
```@docs
REopt.Generator
```

## ExistingBoiler
```@docs
REopt.ExistingBoiler
```

## CHP
```@docs
REopt.CHP
```

## AbsorptionChiller
```@docs
REopt.AbsorptionChiller
```

## Boiler
```@docs
REopt.Boiler
```

## HotThermalStorage
```@docs
REopt.HotThermalStorageDefaults
```

## HighTempThermalStorage
```@docs
REopt.HighTempThermalStorageDefaults
```

## ColdThermalStorage
```@docs
REopt.ColdThermalStorageDefaults
```

## HeatingLoad
```@docs
REopt.HeatingLoad()
```

## CoolingLoad
```@docs
REopt.CoolingLoad
```

## FlexibleHVAC
```@docs
REopt.FlexibleHVAC
```

## ExistingChiller
```@docs
REopt.ExistingChiller
```

## GHP
```@docs
REopt.GHP
```

## SteamTurbine
```@docs
REopt.SteamTurbine
```

## ElectricHeater
```@docs
REopt.ElectricHeater
```

## ASHP
```@docs
REopt.ASHP
```

## CST
```@docs
REopt.CST
```