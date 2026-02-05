# Independent Thermal CHP Implementation

## Overview

This update adds the capability for CHP (Combined Heat and Power) systems to produce thermal energy independently of electric production. This enhancement enables modeling of technologies like nuclear or geothermal systems where thermal energy can be produced separately and more efficiently than when coupled to electric generation.

### Key Capability

Previously, CHP thermal production was **coupled** to electric production - thermal output was proportional to electric output based on efficiency curves. Now, with `can_produce_thermal_independently = true`, the CHP can:

- Produce thermal energy without producing electricity
- Produce electricity (which consumes thermal capacity from the source)
- Produce both thermal and electric simultaneously
- Size electric capacity and thermal capacity independently

**Important Physics for Nuclear/Geothermal:**
- `size_thermal_kw` = thermal source capacity (reactor thermal power, wellfield output)
- `size_kw` = electric generation equipment capacity (turbine/generator)
- Total thermal from source = thermal to loads + thermal converted to electricity
- Thermal for electricity = electric production / electric_efficiency
- Constraint: thermal_to_loads + thermal_for_electric ≤ thermal_source_capacity

## Files Modified

### 1. Core CHP Definition: `src/core/chp.jl`

**Added Fields to CHP Struct:**

```julia
can_produce_thermal_independently::Bool = false  # Enable independent thermal production
min_thermal_kw::Float64 = 0.0                   # Minimum thermal capacity constraint
max_thermal_kw::Float64 = NaN                   # Maximum thermal capacity constraint
```

**Docstring Updated:** Added documentation for the three new parameters with usage notes.

### 2. CHP Constraints: `src/constraints/chp_constraints.jl`

**New Functions Added:**

- `add_chp_independent_thermal_production_constraints(m, p; _n="")`
  - Models thermal source capacity (reactor, wellfield) that serves both loads and electric production
  - Constrains: thermal_to_loads + thermal_for_electric_conversion ≤ thermal_source_capacity
  - Where: thermal_for_electric = electric_production / electric_efficiency
  - Enforces thermal capacity bounds (min/max)

- `add_chp_independent_fuel_burn_constraints(m, p; _n="")`
  - Calculates fuel consumption based on total thermal from source
  - Fuel = (thermal_to_loads + thermal_for_electric) / thermal_efficiency_of_source
  - Properly represents nuclear/geothermal physics where fuel produces thermal first
  - Thermal is then either used directly or converted to electricity

**Modified Functions:**

- `add_chp_constraints(m, p; _n="")`
  - Creates `dvThermalSize` decision variable when in independent mode
  - Conditionally applies either independent or coupled constraints based on `can_produce_thermal_independently` flag

### 3. CHP Results: `src/results/chp.jl`

**Added Result Fields:**

- `size_thermal_kw`: Thermal capacity size [kW] (only included when `can_produce_thermal_independently=true`)
- `annual_thermal_production_from_source_mmbtu`: Total thermal produced from the source, including thermal consumed for electric production [MMBtu] (only included when `can_produce_thermal_independently=true`)

**Important Distinction:**
- `annual_thermal_production_mmbtu`: Thermal energy delivered to heating loads (for all CHP modes)
- `annual_thermal_production_from_source_mmbtu`: Total thermal from the source = thermal to loads + thermal consumed to produce electricity (independent mode only)

**Calculation:**
```julia
annual_thermal_production_from_source_mmbtu = annual_fuel_consumption_mmbtu × thermal_efficiency_full_load
```

This matches the physics where the thermal source capacity must serve both direct thermal loads and provide thermal for electric conversion.

**Modified Function:**

- `add_chp_results()`: Conditionally adds thermal capacity and total thermal from source to results dictionary

### 4. Test Files

**New Scenario:** `test/scenarios/chp_independent_thermal.json`
- Hospital building with electric and thermal loads
- CHP configured with independent thermal production
- High thermal efficiency (0.80) vs. electric efficiency (0.35)

**New Test Code:** `test/test_temp.jl` (lines 38+)
- Comprehensive test with fuel accounting verification
- Assertions to validate correct operation

## Usage

### Input JSON Structure

```json
{
  "CHP": {
    "fuel_cost_per_mmbtu": 10.0,
    "can_produce_thermal_independently": true,
    
    "max_kw": 1000,
    "min_kw": 0,
    "electric_efficiency_full_load": 0.35,
    "electric_efficiency_half_load": 0.35,
    
    "max_thermal_kw": 5000,
    "min_thermal_kw": 0,
    "thermal_efficiency_full_load": 0.80,
    "thermal_efficiency_half_load": 0.80,
    
    "installed_cost_per_kw": 2000.0,
    "om_cost_per_kw": 100.0,
    "om_cost_per_kwh": 0.01,
    "min_turn_down_fraction": 0.5
  }
}
```

### Results Structure

When `can_produce_thermal_independently = true`, results include:

```json
{
  "CHP": {
    "size_kw": 1000.0,
    "size_thermal_kw": 5000.0,
    "annual_electric_production_kwh": 3500000.0,
    "annual_thermal_production_mmbtu": 15000.0,
    "annual_thermal_production_from_source_mmbtu": 25000.0,
    "annual_fuel_consumption_mmbtu": 31250.0,
    ...
  }
}
```

**Result Field Explanations:**

- `size_kw`: Electric generation equipment capacity (turbine/generator) [kW]
- `size_thermal_kw`: Thermal source capacity (reactor, wellfield) [kW]
- `annual_electric_production_kwh`: Electricity produced [kWh]
- `annual_thermal_production_mmbtu`: Thermal energy delivered to heating loads [MMBtu]
- `annual_thermal_production_from_source_mmbtu`: **Total thermal from source** = thermal to loads + thermal consumed for electric production [MMBtu]
- `annual_fuel_consumption_mmbtu`: Total fuel consumed [MMBtu]

**Comparing with Boiler + SteamTurbine:**
- CHP `annual_thermal_production_from_source_mmbtu` ≈ Boiler `annual_thermal_production_mmbtu` (both include thermal for electric)
- CHP `annual_thermal_production_mmbtu` ≈ (Boiler thermal to loads) + (thermal to storage) (excludes thermal to steam turbine)

## Important Notes

### ⚠️ Cost Limitations

**Current Implementation:**

- `installed_cost_per_kw` applies **only to ELECTRIC capacity**
- `om_cost_per_kw` applies **only to ELECTRIC capacity**
- There are NO separate cost parameters for thermal capacity

**Implications:**

For technologies where thermal and electric capacities have significantly different costs, the current cost structure may not accurately represent total capital and O&M costs. The optimization will size thermal capacity based on:
- Thermal load requirements
- Fuel costs
- Value of thermal energy
- BUT NOT on incremental thermal capacity costs

### Prime Mover Defaults

**Do NOT use `prime_mover` parameter for independent thermal CHP.** The traditional prime_mover-based defaults (reciprocating engine, combustion turbine, fuel cell, micro turbine) are designed for coupled thermal-electric operation and do not apply well to independent thermal systems.

**Instead, explicitly specify:**
- All efficiency parameters
- All sizing bounds
- All cost parameters

### Efficiency Definitions

**Traditional CHP:** 
- `electric_efficiency_full_load` = electric output / fuel input at full load
- `thermal_efficiency_full_load` = thermal output / fuel input at full electric load

**Independent Thermal CHP (Nuclear/Geothermal):** 
- `thermal_efficiency_full_load` = thermal source output / fuel (or primary energy) input
- `electric_efficiency_full_load` = electric output / thermal input to power cycle
- These combine: overall fuel→electric efficiency = thermal_eff × electric_eff

**Example:**
- Nuclear reactor: thermal_eff = 0.33 (fuel→thermal), electric_eff = 0.35 (thermal→electric)
- Overall fuel→electric = 0.33 × 0.35 = 0.116 (11.6%)
- But reactor can deliver thermal at 33% fuel efficiency for direct heating
- This represents: ~1 unit fuel → 0.33 units thermal → (0.116 units electric OR 0.33 units process heat)

## Future Improvements

### 1. Separate Thermal Capacity Costs (High Priority)

Add new parameters:

```julia
installed_cost_per_kw_thermal::Float64  # Capital cost per kW of thermal capacity [$/kW-thermal]
tech_sizes_for_thermal_cost_curve::Vector{Float64}  # Support cost curves for thermal
om_cost_per_kw_thermal::Float64  # Fixed O&M per kW of thermal capacity [$/kW-thermal/year]
om_cost_per_kwh_thermal::Float64  # Variable O&M per kWh of thermal production [$/kWh-thermal]
```

**Impact:** Would enable accurate cost representation for technologies where thermal and electric capacities have different cost structures (e.g., nuclear reactor core vs. steam turbine generator vs. process heat exchangers).

### 2. Enhanced Cost Curves

Support multi-dimensional cost curves that account for:
- Electric capacity size
- Thermal capacity size  
- Ratio of thermal to electric capacity

### 3. Default Parameter Sets

Create default parameter libraries for common independent thermal technologies:
- Nuclear (small modular reactors)
- Geothermal (direct use + binary cycle)
- Solar thermal with backup electric
- Industrial waste heat recovery with power generation

### 4. Thermal Capacity Turn-Down

Add `min_thermal_turn_down_fraction` parameter separate from electric turn-down, since thermal and electric may have different operational constraints.

### 5. Separate Unavailability

Allow independent unavailability schedules for electric vs. thermal systems:
```julia
unavailability_periods_electric::Vector{Dict}
unavailability_periods_thermal::Vector{Dict}
```
chp_independent_thermal.jl")
```

The test includes two sections:

### 1. Independent Thermal CHP Test
Verifies:
- Thermal capacity is sized separately from electric
- `size_thermal_kw` and `annual_thermal_production_from_source_mmbtu` appear in results
- Fuel accounting is accurate for independent operation
- Physics verification: fuel → thermal source → (loads + electric)

### 2. Boiler + SteamTurbine Comparison Test
Compares equivalent modeling approaches:
- Independent Thermal CHP vs. Boiler + SteamTurbine
- Verifies similar total thermal production, electric production, and fuel consumption
- Uses `annual_thermal_production_from_source_mmbtu` for apples-to-apples comparison
## Testing

Run the test with:

```julia
cd("c:/Users/wbecker/.julia/dev/REopt/test")
include("test_temp.jl")
```

The test verifies:
- Thermal capacity is sized separately from electric
- `size_thermal_kw` appears in results
- Fuel accounting is accurate for independent operation
- Thermal production occurs as expected

## Backward Compatibility

✅ **Fully backward compatible**

- Default value: `can_produce_thermal_independently = false`
- Existing CHP models continue to work with coupled thermal-electric operation
- No changes required to existing input files
- Results structure unchanged for traditional CHP (no `size_thermal_kw` field added)

## Technical Details

### Decision Variables

**Traditional Mode:**
- `dvSize[t]` - Electric capacity [kW]

**Independent Mode:**
- `dvSize[t]` - Electric capacity [kW]
- `dvThermalSize[t]` - Thermal capacity [kW] (NEW)

### Constraint Logic

**Fuel Consumption:**

Traditional:
```
Fuel = f(Electric_Production, coupled_thermal_efficiency)
```

Independent (Corrected Physics):
```
Total_Thermal_From_Source = Thermal_To_Loads + Electric_Production / Electric_Efficiency
Fuel = Total_Thermal_From_Source / Thermal_Efficiency_Of_Source + Supplementary_Firing
```

**Thermal Production:**

Traditional:
```
Thermal ≤ g(Electric_Production, thermal_electric_ratio)
```

Independent (Properly Coupled):
```
Thermal_To_Loads + Electric_Production / Electric_Efficiency ≤ Thermal_Source_Capacity
Electric_Production ≤ Electric_Equipment_Capacity
```

**Example Scenario:**
- Thermal source capacity = 1000 kW (reactor/wellfield)
- Electric equipment capacity = 300 kW (turbine/generator)
- Electric efficiency = 0.30 (thermal→electric conversion)

Possible operations:
1. **Max Direct Thermal:** 1000 kW thermal to loads, 0 kW electric
2. **Max Electric:** 300 kW electric (consumes 1000 kW thermal), 0 kW to loads
3. **Balanced:** 150 kW electric (consumes 500 kW thermal), 500 kW thermal to loads
4. **Can't do:** 300 kW electric + 500 kW thermal (would need 1500 kW source capacity)

### Load Compatibility

All existing load compatibility constraints remain active:
- `can_serve_dhw`
- `can_serve_space_heating`
- `can_serve_process_heat`
- `can_supply_steam_turbine`

These apply identically in both traditional and independent modes.

## Questions or Issues?

For questions about this implementation, contact the development team or open an issue on the REopt.jl GitHub repository.

---

## Appendix: Independent Thermal CHP vs. Boiler + Steam Turbine

### When to Use Each Modeling Approach

Both modeling approaches can represent systems that produce thermal and electric energy, but they have different strengths:

### Independent Thermal CHP (This Implementation)

**Use When:**
- Modeling a **single integrated technology** (nuclear reactor, geothermal plant, fuel cell system)
- The physical system has one fuel input and can independently choose thermal vs. electric output
- Direct thermal production is more efficient than electric-then-thermal pathway
- You want **simpler input structure and operational modeling**
- Capital costs are primarily for the core technology (reactor, wellfield, etc.)

**Advantages:**
1. **Physically Accurate for Integrated Systems** - Matches technologies where thermal and electric come from the same core asset
2. **Simpler Inputs** - One technology definition instead of two
3. **Direct Thermal Efficiency** - Can produce thermal at high efficiency without intermediate electric conversion
4. **Single Investment Decision** - One size optimization, one on/off decision per timestep
5. **Clear Cost Attribution** - All costs tied to one system
6. **Flexible Operation** - Can operate in thermal-only, electric-only, or combined modes

**Example Technologies:**
- Nuclear reactors (can produce process heat or electricity from same core)
- Geothermal systems (direct use heat + binary cycle electric)
- Large fuel cells (can extract thermal before or after electric generation)
- Advanced industrial CHP where thermal is a primary product, not just waste heat recovery

**Limitations:**
- Currently only electric capacity costs are modeled (see Future Improvements)
- May not capture nuances of steam systems (pressure, quality)
- Less suitable when thermal and electric systems are physically separable

### Boiler + Steam Turbine (Existing Capability)

**Use When:**
- Modeling **two distinct physical assets** (boiler + turbine generator)
- You have or could have a boiler without a steam turbine (separable investment)
- Steam distribution system serves multiple purposes
- You need to model **steam pressure/quality** or **extraction vs. condensing** turbines
- Thermal is the primary need, electric is opportunistic from excess steam

**Advantages:**
1. **Matches Industrial Reality** - Most industrial CHP is actually boiler + steam turbine
2. **Separate Investment Decisions** - Can optimize adding steam turbine to existing boiler
3. **Steam System Representation** - Better captures steam distribution, pressure drops, quality
4. **Backpressure Turbine Modeling** - Can extract steam at intermediate pressure for process loads
5. **Established Technology Performance** - Well-known efficiency curves and operational characteristics
6. **Flexibility in Steam Allocation** - Steam can serve: loads, storage, turbine, or combinations
7. **Separate Sizing** - Boiler and turbine sized independently based on thermal vs. electric needs

**Example Technologies:**
- Industrial facilities with existing steam boilers adding cogeneration
- Large campus district energy systems with central plants
- Chemical processing plants with steam networks
- Pulp and paper mills, refineries, food processing facilities

**Limitations:**
- More complex input structure (two technologies)
- Two separate on/off decisions per timestep (increased computational complexity)
- May not represent technologies where thermal and electric are intrinsically coupled
- Requires understanding of steam turbine types (backpressure vs. condensing vs. extraction)

### Key Modeling Differences

| Aspect | Independent Thermal CHP | Boiler + Steam Turbine |
|--------|------------------------|------------------------|
| **Physical Representation** | Single integrated asset | Two separate assets |
| **Fuel Consumption** | Fuel → (Thermal OR Electric OR Both) | Fuel → Boiler → Thermal → (Load OR Turbine → Electric) |
| **Thermal Efficiency** | Direct: Thermal/Fuel | Boiler efficiency only |
| **Electric Efficiency** | Direct: Electric/Fuel | Thermal → Electric conversion |
| **Investment Decision** | One size variable | Two size variables |
| **Operational Complexity** | One binary on/off | Two binary on/offs (if binaries used) |
| **Steam Distribution** | Not explicitly modeled | Can model distribution to multiple endpoints |
| **Cost Structure** | Single CapEx + O&M | Separate CapEx + O&M for each |

### Hybrid Approach Considerations

**Can you model the same physical system both ways?**

Sometimes, yes. For example:

**Nuclear Plant with Process Heat Extraction:**
- **As Independent Thermal CHP:** Nuclear reactor produces thermal (process heat) or electric or both
- **As Boiler + Steam Turbine:** Nuclear "boiler" produces steam; steam turbine extracts electric; remaining steam serves thermal load

**The choice depends on:**
1. **What investment decisions do you want to optimize?** 
   - If sizing reactor core vs. adding turbine capacity → Separate is better
   - If sizing integrated system as one unit → Independent is better

2. **What operational flexibility exists?**
   - If steam can bypass turbine entirely → Both work
   - If thermal requires electric generation first → Separate is more accurate

3. **What costs are most significant?**
   - If reactor/core is 90% of cost → Independent is simpler
   - If turbine is major separate cost → Separate is more accurate

4. **Input data availability:**
   - Steam turbine performance curves available → Separate is easier
   - Only know integrated system performance → Independent is easier

### Recommendation

For **geothermal, nuclear, or advanced fuel cell systems** where:
- The technology is inherently integrated
- Direct thermal production doesn't require electric generation
- You're sizing the core system as one unit

→ **Use Independent Thermal CHP**

For **industrial cogeneration** where:
- You have an existing or separately-sizable boiler
- Steam distribution is important
- You're evaluating adding power generation to steam systems

→ **Use Boiler + Steam Turbine**

### Future Enhancement: Unified Framework?

A potential future enhancement could unify these approaches by:
1. Adding thermal capacity costs to Independent Thermal CHP (already identified as needed)
2. Adding more flexible coupling options (e.g., `thermal_electric_coupling_factor`)
3. Allowing steam turbine to optionally produce thermal independently of incoming steam
4. Creating a generalized "thermal-electric technology" framework that encompasses both

This would give users maximum modeling flexibility while maintaining physical accuracy.

---

**Implementation Date:** December 28, 2025  
**Branch:** ouu  
**Status:** Complete, needs testing with production scenarios
