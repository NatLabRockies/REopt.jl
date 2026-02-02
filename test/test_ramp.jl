# using Revise
# using REopt
# using JSON
# using DelimitedFiles
# using PlotlyJS
# using Dates
# using Test
# using JuMP
# using HiGHS
# using DotEnv
# DotEnv.load!()

# Notes to test for Off-Grid DC powered by Nuclear + Storage
# 
# DONE: CHP electric only with ramp rate limit, no outage but force battery size to avoid utility serving the high ramp times
# Boiler + SteamTurbine (+ HighTempThermalStorage?)
# Add CHP and/or Boiler+ST to off-grid with SR requirements for nuclear
# Generator and Battery currently have unlimited SR **supply**
# PV has SR requirement - use that as proxy for nuclear and/or geothermal?
# Focus on analysis needs for project, but eventually consider GenericGenerator (+Heat?) with needed attributes


# Create a 15-minute interval load profile from hourly with sine wave sub-hourly variations
function upsample_load_variation(hourly_load; intra_hour_variation=0.2)
    # Create 15-minute load profile with sine wave sub-hourly variations
    fifteen_min_loads = Float64[]
    for (hour_idx, hourly_load) in enumerate(hourly_load)
        # Create 4 sub-hourly values per hour with sine wave variation
        # Base load with ±10% sine wave variation within each hour
        for quarter_hour in 1:4
            # Intra-hour phase angle for this quarter hour (0, π/2, π, 3π/2)
            intra_hour_phase = (quarter_hour - 1) * π / 2
            # Sine wave variation: ±20% of hourly load
            variation = intra_hour_variation * sin(intra_hour_phase + 2π * hour_idx / 24)  # Daily cycle component
            sub_hourly_load = hourly_load * (1.0 + variation)
            push!(fifteen_min_loads, max(0.0, sub_hourly_load))  # Ensure non-negative
        end
    end

    return fifteen_min_loads
end


###############   Nuclear as CHP with ramp rate and battery to support   ###################

# scenario = 1 # "Specify CHP+battery sizes 15-min load with variation, no outages"
# scenario = 2 # "Least-cost sizes CHP+battery for year long outage hourly load from CRB"
# scenario = 3 # "Force CHP/Nuclear to peak load size, but still size battery for ramp rate limit"
scenario = 3
# Load scenario with CHP (electric only) cost and performance params similar to nuclear
input_data = JSON.parsefile("./scenarios/nuclear_battery.json")

# New ramp rate input/constraint (fraction of capacity per hour)
input_data["CHP"]["ramp_rate_fraction_per_hour"] = 0.1

if scenario == 1
    # Create 15-minute load profile from hourly with sine wave intra-hour variation
    sim_input = Dict(
        "load_type" => "electric",
        "doe_reference_name" => "Hospital",
        "annual_kwh" => 4.0e6,
        "latitude" => input_data["Site"]["latitude"],
        "longitude" => input_data["Site"]["longitude"],
        "year" => 2023)
    hourly_loads_kw = simulated_load(sim_input)["loads_kw"]
    fifteen_min_loads = upsample_load_variation(hourly_loads_kw; intra_hour_variation=0.05)
    input_data["Settings"] = Dict("time_steps_per_hour" => 4)
    input_data["ElectricLoad"] = Dict("loads_kw" => fifteen_min_loads, "year" => 2023)

    # You can adjust the fixed size here if desired
    fixed_chp_size_kw = 800.0
    input_data["CHP"]["min_kw"] = fixed_chp_size_kw
    input_data["CHP"]["max_kw"] = fixed_chp_size_kw

    # See if REopt sizes battery to support nuclear ramp rate limitation
    input_data["ElectricStorage"] = Dict(
        "min_kw" => 800.0,
        "min_kwh" => 800.0,
        "max_kw" => 800.0,
        "max_kwh" => 800.0
    )
elseif scenario == 2 || scenario == 3
    # Year-long outage scenario from CHP test scenarios
    input_data["ElectricLoad"] = Dict("doe_reference_name" => "Hospital", "annual_kwh" => 4.0e6)
    input_data["ElectricLoad"]["critical_load_fraction"] = 1.0
    input_data["ElectricUtility"] = Dict("outage_start_time_step" => 1, 
                                        "outage_end_time_step" => 8760)
    input_data["ElectricStorage"] = Dict()
    if scenario == 3
        # Force CHP to peak load size, but still size battery for ramp rate limit
        # Estimate peak load from annual energy assuming capacity factor
        estimated_peak_load_kw = 740.0  # Assuming 50% capacity factor
        input_data["CHP"]["min_kw"] = estimated_peak_load_kw
        input_data["CHP"]["max_kw"] = estimated_peak_load_kw
    end
end

# This was somehow being set to 0 in dictkeys_tosymbols in utils.py which was causing an error,
# but function was updated to avoid this
# input_data["Settings"]["off_grid_flag"] = false

# Create scenario and inputs
s = Scenario(input_data)
inputs = REoptInputs(s)
ts_per_hour = s.settings.time_steps_per_hour

# Run optimization with single model (no BAU comparison needed for fixed sizing)
m = Model(optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.01, "output_flag" => false, "log_to_console" => false))
results = run_reopt(m, inputs)

# Print key results
println("\n===== Nuclear as CHP with ramp rate and battery to support  =====")
println("\nCHP Results:")
println("CHP Size (kW): ", results["CHP"]["size_kw"])
println("Annual CHP Production (kWh): ", round(results["CHP"]["annual_electric_production_kwh"], digits=0))
println("CHP to Load (kWh): ", round(sum(results["CHP"]["electric_to_load_series_kw"])/ts_per_hour, digits=0))
println("CHP to Battery (kWh): ", round(sum(results["CHP"]["electric_to_storage_series_kw"])/ts_per_hour, digits=0))
println("CHP to Grid (kWh): ", round(sum(results["CHP"]["electric_to_grid_series_kw"])/ts_per_hour, digits=0))
println("CHP Curtailed (kWh): ", round(sum(results["CHP"]["electric_curtailed_series_kw"])/ts_per_hour, digits=0))
println("\nBattery Results:")
println("Battery Energy Size (kWh): ", results["ElectricStorage"]["size_kwh"])
println("Battery Power Size (kW): ", results["ElectricStorage"]["size_kw"])
println("Battery to Load (kWh): ", round(sum(results["ElectricStorage"]["storage_to_load_series_kw"])/ts_per_hour, digits=0))
println("\nGrid Results:")
println("Utility to Load (kWh): ", round(sum(results["ElectricUtility"]["annual_energy_supplied_kwh"]), digits=0))
# println("\nFinancial Results:")
# println("NPV (\$): ", round(results["Financial"]["npv"], digits=0))
# println("Simple Payback (years): ", round(results["Financial"]["simple_payback_years"], digits=2))
println("==========================================\n")

# Create stacked area chart showing how CHP and battery serve the load
load_series = results["ElectricLoad"]["load_series_kw"]
chp_to_load = results["CHP"]["electric_to_load_series_kw"]
batt_to_load = results["ElectricStorage"]["storage_to_load_series_kw"]
grid_to_load = results["ElectricUtility"]["electric_to_load_series_kw"]

# Create time steps array (in hours for x-axis)
time_hours = collect(1:length(load_series)) ./ ts_per_hour

# Create stacked area chart
plt = plot(
    [
        scatter(
            x=time_hours, 
            y=grid_to_load, 
            mode="lines", 
            name="Grid to Load",
            fill="tozeroy",
            line=attr(width=0.5, color="rgb(128,128,128)"),
            fillcolor="rgba(128,128,128,0.5)"
        ),
        scatter(
            x=time_hours, 
            y=grid_to_load .+ chp_to_load, 
            mode="lines", 
            name="CHP to Load",
            fill="tonexty",
            line=attr(width=0.5, color="rgb(255,128,0)"),
            fillcolor="rgba(255,128,0,0.6)"
        ),
        scatter(
            x=time_hours, 
            y=grid_to_load .+ chp_to_load .+ batt_to_load, 
            mode="lines", 
            name="Battery to Load",
            fill="tonexty",
            line=attr(width=0.5, color="rgb(0,128,255)"),
            fillcolor="rgba(0,128,255,0.6)"
        ),
        scatter(
            x=time_hours, 
            y=load_series, 
            mode="lines", 
            name="Total Load",
            line=attr(width=2, color="rgb(0,0,0)", dash="dot")
        )
    ],
    Layout(
        title="Electric Load Service Breakdown - CHP with Ramp Rate and Battery Support",
        xaxis=attr(title="Time (hours)", range=[0, 8760]),
        yaxis=attr(title="Power (kW)"),
        showlegend=true,
        hovermode="x unified",
        legend=attr(x=1.02, y=1, xanchor="left", yanchor="top")
    )
)
display(plt)