# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    BAUInputs(p::REoptInputs)

The`BAUInputs` (REoptInputs for the Business As Usual scenario) are created based on the `BAUScenario`, which is in turn created based on the optimized-case `Scenario`.

The following assumptions are made for the BAU Inputs: 
* `PV` and `Generator` `min_kw` and `max_kw` set to the `existing_kw` values
* `ExistingBoiler` and `ExistingChiller`  # TODO
* All other generation and storage tech sizes set to zero 
* Capital costs are assumed to be zero for existing `PV` and `Generator`
* O&M costs and all other tech inputs are assumed to be the same for existing `PV` and `Generator` as those specified for the optimized case
* Outage assumptions for deterministic vs stochastic # TODO 
"""
function BAUInputs(p::REoptInputs)
    bau_scenario = BAUScenario(p.s)
    techs = Techs(p, bau_scenario)

    boiler_efficiency = Dict{String, Float64}()
    fuel_cost_per_kwh = Dict{String, AbstractArray}()

    # REoptInputs indexed on techs.all:
    max_sizes = Dict(t => 0.0 for t in techs.all)
    min_sizes = Dict(t => 0.0 for t in techs.all)
    existing_sizes = Dict(t => 0.0 for t in techs.all)
    cap_cost_slope = Dict{String, Any}()
    om_cost_per_kw = Dict(t => 0.0 for t in techs.all)
    thermal_cop = Dict{String, Float64}()
    heating_cop = Dict{String, Array{Float64,1}}()
    cooling_cop = Dict{String, Array{Float64,1}}()
    heating_cf = Dict{String, Array{Float64,1}}() 
    cooling_cf = Dict{String, Array{Float64,1}}() 
    avoided_capex_by_ashp_present_value = Dict(t => 0.0 for t in techs.all)
    production_factor = DenseAxisArray{Float64}(undef, techs.all, p.time_steps)
    tech_renewable_energy_fraction = Dict(t => 0.0 for t in union(techs.fuel_burning, techs.elec))
    # !!! note: tech_emissions_factors are in lb / kWh of fuel burned (gets multiplied by kWh of fuel burned, not kWh electricity consumption, ergo the use of the HHV instead of fuel slope)
    tech_emissions_factors_CO2 = Dict(t => 0.0 for t in techs.all)
    tech_emissions_factors_NOx = Dict(t => 0.0 for t in techs.all)
    tech_emissions_factors_SO2 = Dict(t => 0.0 for t in techs.all)
    tech_emissions_factors_PM25 = Dict(t => 0.0 for t in techs.all)

    # export related inputs
    techs_by_exportbin = Dict{Symbol, AbstractArray}(k => [] for k in p.s.electric_tariff.export_bins)
    export_bins_by_tech = Dict{String, Array{Symbol, 1}}()

    # REoptInputs indexed on techs.segmented
    n_segs_by_tech = Dict{String, Int}()
    seg_min_size = Dict{String, Dict{Int, Real}}()
    seg_max_size = Dict{String, Dict{Int, Real}}()
    seg_yint = Dict{String, Dict{Int, Real}}()

    # PV specific arrays
    pv_to_location = Dict(t => Dict{Symbol, Int}() for t in techs.pv)

    levelization_factor = Dict(t => 1.0 for t in techs.all)

    for pvname in techs.pv  # copy the optimal scenario inputs for existing PV systems
        production_factor[pvname, :] = p.production_factor[pvname, :]
        pv_to_location[pvname] = p.pv_to_location[pvname]
        existing_sizes[pvname] = p.existing_sizes[pvname]
        min_sizes[pvname] = p.existing_sizes[pvname]
        max_sizes[pvname] = p.existing_sizes[pvname]
        om_cost_per_kw[pvname] = p.om_cost_per_kw[pvname]
        levelization_factor[pvname] = p.levelization_factor[pvname]
        cap_cost_slope[pvname] = 0.0
        tech_renewable_energy_fraction[pvname] = 1.0
        if pvname in p.techs.pbi
            push!(techs.pbi, pvname)
        end
        pv = get_pv_by_name(pvname, p.s.pvs)
        fillin_techs_by_exportbin(techs_by_exportbin, pv, pvname)
        if !pv.can_curtail
            push!(techs.no_curtail, pvname)
        end
    end

    if "Generator" in techs.all
        max_sizes["Generator"] = p.s.generator.existing_kw
        min_sizes["Generator"] = p.s.generator.existing_kw
        existing_sizes["Generator"] = p.s.generator.existing_kw
        cap_cost_slope["Generator"] = 0.0
        om_cost_per_kw["Generator"] = p.s.generator.om_cost_per_kw
        production_factor["Generator", :] = p.production_factor["Generator", :]
        tech_renewable_energy_fraction["Generator"] = p.s.generator.fuel_renewable_energy_fraction
        fillin_techs_by_exportbin(techs_by_exportbin, p.s.generator, "Generator")
        if "Generator" in p.techs.pbi
            push!(techs.pbi, "Generator")
        end
        if !p.s.generator.can_curtail
            push!(techs.no_curtail, "Generator")
        end
        fuel_cost_per_kwh["Generator"] = p.fuel_cost_per_kwh["Generator"]        
    end

    if "ExistingBoiler" in techs.all
        setup_existing_boiler_inputs(bau_scenario, max_sizes, min_sizes, existing_sizes, cap_cost_slope, boiler_efficiency,
            tech_renewable_energy_fraction, tech_emissions_factors_CO2, tech_emissions_factors_NOx, tech_emissions_factors_SO2, tech_emissions_factors_PM25, fuel_cost_per_kwh,
            heating_cf)
    end

    cooling_cop["ExistingChiller"] = ones(length(p.time_steps))
    if "ExistingChiller" in techs.all
        setup_existing_chiller_inputs(bau_scenario, max_sizes, min_sizes, existing_sizes, cap_cost_slope, cooling_cop, cooling_cf)
    end

    # Assign null GHP parameters for REoptInputs
    ghp_options, require_ghp_purchase, ghp_heating_thermal_load_served_kw, 
        ghp_cooling_thermal_load_served_kw, space_heating_thermal_load_reduction_with_ghp_kw, 
        cooling_thermal_load_reduction_with_ghp_kw, ghp_electric_consumption_kw, 
        ghp_installed_cost, ghp_om_cost_year_one, avoided_capex_by_ghp_present_value,
        ghx_useful_life_years, ghx_residual_value = setup_ghp_inputs(bau_scenario, p.time_steps, p.time_steps_without_grid)    

    # filling export_bins_by_tech MUST be done after techs_by_exportbin has been filled in
    for t in techs.elec
        export_bins_by_tech[t] = [bin for (bin, ts) in techs_by_exportbin if t in ts]
    end

    t0, tf = p.s.electric_utility.outage_start_time_step, p.s.electric_utility.outage_end_time_step
    if tf > t0 && t0 > 0
        original_crit_lds = copy(p.s.electric_load.critical_loads_kw)
        generator_fuel_use_gal = update_bau_outage_outputs(bau_scenario, original_crit_lds, t0, tf, production_factor)

        if bau_scenario.outage_outputs.bau_critical_load_met_time_steps > 0  
        # include critical load in bau load for the time that it can be met
            bau_scenario.electric_load.critical_loads_kw[
                t0 : t0 + bau_scenario.outage_outputs.bau_critical_load_met_time_steps
                ] = original_crit_lds[t0 : t0 + bau_scenario.outage_outputs.bau_critical_load_met_time_steps]
        end
    else
        generator_fuel_use_gal = 0.0
    end
    setup_bau_emissions_inputs(p, bau_scenario, generator_fuel_use_gal)

    heating_loads = Vector{String}()
    heating_loads_kw = Dict{String, Array{Real,1}}()
    absorption_chillers_using_heating_load = Dict{String,Array{String,1}}()
    if !isnothing(p.s.dhw_load)
        push!(heating_loads, "DomesticHotWater")
        heating_loads_kw["DomesticHotWater"] = p.s.dhw_load.loads_kw
        absorption_chillers_using_heating_load["DomesticHotWater"] = Vector{String}()
    end
    if !isnothing(p.s.space_heating_load)
        push!(heating_loads, "SpaceHeating")
        heating_loads_kw["SpaceHeating"] = p.s.space_heating_load.loads_kw
        absorption_chillers_using_heating_load["SpaceHeating"] = Vector{String}()
    elseif !isnothing(p.s.flexible_hvac) && !isnothing(p.s.existing_boiler)
        push!(heating_loads, "SpaceHeating")  #add blank space heating load to add dvHeatingProduction for existing boiler
    end
    if !isnothing(p.s.process_heat_load)
        push!(heating_loads, "ProcessHeat")
        heating_loads_kw["ProcessHeat"] = p.s.process_heat_load.loads_kw
        absorption_chillers_using_heating_load["ProcessHeat"] = Vector{String}()
    end

    if sum(heating_loads_kw["SpaceHeating"]) > 0.0 && isempty(techs.can_serve_space_heating) 
        throw(@error("SpaceHeating load is nonzero and no techs can serve the load."))
    end
    if sum(heating_loads_kw["DomesticHotWater"]) > 0.0 && isempty(techs.can_serve_dhw) 
        throw(@error("DomesticHotWater load is nonzero and no techs can serve the load."))
    end
    if sum(heating_loads_kw["ProcessHeat"]) > 0.0 && isempty(techs.can_serve_process_heat) 
        throw(@error("ProcessHeat load is nonzero and no techs can serve the load."))
    end


    heating_loads_served_by_tes = Dict{String,Array{String,1}}()
    unavailability = get_unavailability_by_tech(p.s, techs, p.time_steps)

    # Production factors: use optimal scenarios for existing techs, deterministic for others
    production_factor_by_scenario = Dict{Int, Dict{String, Vector{Float64}}}(
        s => Dict{String, Vector{Float64}}(
            t => if haskey(p.production_factor_by_scenario[s], t)
                # Use optimal scenario production for existing PV/Generator
                Float64.(copy(p.production_factor_by_scenario[s][t]))
            else
                # Deterministic for techs not in optimal (shouldn't happen in BAU)
                Float64.([production_factor[t, ts] for ts in p.time_steps])
            end
            for t in techs.all
        )
        for s in 1:p.n_scenarios
    )

    REoptInputs(
        bau_scenario,
        techs,
        min_sizes,
        max_sizes,
        existing_sizes,
        cap_cost_slope,
        om_cost_per_kw,
        thermal_cop,
        p.time_steps,
        p.time_steps_with_grid,
        p.time_steps_without_grid,
        p.hours_per_time_step,
        p.months,
        production_factor,
        levelization_factor,
        p.value_of_lost_load_per_kwh,
        p.pwf_e,
        p.pwf_om,
        p.pwf_fuel,
        p.pwf_emissions_cost,
        p.pwf_grid_emissions,
        p.pwf_offtaker,
        p.pwf_owner,
        p.third_party_factor,
        p.pvlocations,
        p.maxsize_pv_locations,
        pv_to_location,
        p.ratchets,
        techs_by_exportbin,
        export_bins_by_tech,
        n_segs_by_tech,
        seg_min_size,
        seg_max_size,
        seg_yint,
        p.pbi_pwf, # Same pbi dict as optimal case
        p.pbi_max_benefit, 
        p.pbi_max_kw, 
        p.pbi_benefit_per_kwh,
        boiler_efficiency,
        fuel_cost_per_kwh,
        ghp_options,
        require_ghp_purchase,
        ghp_heating_thermal_load_served_kw,
        ghp_cooling_thermal_load_served_kw,
        space_heating_thermal_load_reduction_with_ghp_kw,
        cooling_thermal_load_reduction_with_ghp_kw,
        ghp_electric_consumption_kw,
        ghp_installed_cost,
        ghp_om_cost_year_one,
        avoided_capex_by_ghp_present_value,
        ghx_useful_life_years,
        ghx_residual_value,
        tech_renewable_energy_fraction, 
        tech_emissions_factors_CO2, 
        tech_emissions_factors_NOx, 
        tech_emissions_factors_SO2, 
        tech_emissions_factors_PM25,
        p.techs_operating_reserve_req_fraction,
        heating_cop,
        cooling_cop,
        heating_cf,
        cooling_cf,
        heating_loads,
        heating_loads_kw,
        heating_loads_served_by_tes,
        unavailability,
        absorption_chillers_using_heating_load,
        avoided_capex_by_ashp_present_value,
        p.n_scenarios,
        p.scenario_probabilities,
        p.loads_kw_by_scenario,
        production_factor_by_scenario
    )
end

"""
    setup_bau_emissions_inputs(p::REoptInputs, s_bau::BAUScenario, generator_fuel_use_gal::Real)

Pre-processing of the BAU emissions to use in determining emissions reductions in the optimal case
Include BAU grid emissions, existing backup generator emissions, boiler emissions
Update the `bau_(grid_)emissions_` values in s.site and s_bau.site

!!! note
    If existing generation does not sustain a simulated deterministic outage, the BAU load and 
    therefore emissions are 0 during unsurvived outage hours
!!! note
    When a single outage is modeled (using outage_start_time_step), emissions calculations 
    account for operations during this outage (e.g., the critical load is used during 
    time_steps_without_grid). On the contrary, when multiple outages are modeled (using 
    outage_start_time_steps), renewable electricity calculations reflect normal operations, 
    and do not account for expected operations during modeled outages (time_steps_without_grid is empty)
"""
function setup_bau_emissions_inputs(p::REoptInputs, s_bau::BAUScenario, generator_fuel_use_gal::Real)
    
    bau_emissions_lb_CO2_per_year = 0

    ## Grid emissions

    # This function is called after ajust_load_profile() (makes load_kw native if not already) 
    # so need to calculate net version of loads_kw by removing existing PV to get load served by the grid.
    # TODO: Should load_profile have loads_kw and loads_kw_net fields, instead of updating loads_kw? Would be easier 
    # to keep track of what version you're using, don't have to make sure whether it's before or after the adjustment.
    # Must account for levelization factor to align with how PV is modeled in REopt:
    # Because we only model one year, we multiply the "year 1" PV production by a levelization_factor
    # that accounts for the PV capacity degradation over the analysis_years. In other words, by
    # multiplying the pv production_factor by the levelization_factor we are modeling the average pv production.
    bau_grid_to_load = copy(s_bau.electric_load.loads_kw)
    bau_grid_to_load_critical = copy(s_bau.electric_load.critical_loads_kw)
    for pv in p.s.pvs if pv.existing_kw > 0
        bau_grid_to_load .-= p.levelization_factor[pv.name] * pv.existing_kw * p.production_factor[pv.name, :].data
        bau_grid_to_load_critical .-= p.levelization_factor[pv.name] * pv.existing_kw * p.production_factor[pv.name, :].data
    end end

    #No grid emissions, or pv exporting to grid, during an outage
    if p.s.electric_utility.outage_start_time_step != 0 && p.s.electric_utility.outage_end_time_step != 0
        for i in range(p.s.electric_utility.outage_start_time_step, stop=p.s.electric_utility.outage_end_time_step)
            bau_grid_to_load[i] = 0
        end
    end

    #If no net emissions accounting, no credit for RE grid exports:
    if !p.s.site.include_exported_elec_emissions_in_total
        bau_grid_to_load = [max(i,0) for i in bau_grid_to_load]
    end

    bau_grid_emissions_lb_CO2_per_year = sum(p.s.electric_utility.emissions_factor_series_lb_CO2_per_kwh .* bau_grid_to_load) * p.hours_per_time_step
    bau_emissions_lb_CO2_per_year += bau_grid_emissions_lb_CO2_per_year

    ## Generator emissions (during outages)
    if "Generator" in p.techs.all
        bau_emissions_lb_CO2_per_year += generator_fuel_use_gal * p.s.generator.emissions_factor_lb_CO2_per_gal
    end

    ## Boiler emissions
    if "ExistingBoiler" in p.techs.all
        for heat_type in ["space_heating", "dhw", "process_heat"]
            # Divide by existing_boiler.efficiency because annual_mmbtu is thermal, so convert to fuel
            bau_emissions_lb_CO2_per_year += getproperty(p.s,Symbol("$(heat_type)_load")).annual_mmbtu / 
                                                p.s.existing_boiler.efficiency * 
                                                p.s.existing_boiler.emissions_factor_lb_CO2_per_mmbtu
        end
    end

    p.s.site.bau_emissions_lb_CO2_per_year = bau_emissions_lb_CO2_per_year
    p.s.site.bau_grid_emissions_lb_CO2_per_year = bau_grid_emissions_lb_CO2_per_year
    s_bau.site.bau_emissions_lb_CO2_per_year = bau_emissions_lb_CO2_per_year
    s_bau.site.bau_grid_emissions_lb_CO2_per_year = bau_grid_emissions_lb_CO2_per_year
end


"""
    update_bau_outage_outputs(s::BAUScenario, crit_load, t0, tf, production_factors)

Update the `bau_critical_load_met` and `bau_critical_load_met_time_steps` values.

return: Float for the gallons of fuel used trying to meet critical load

"""
function update_bau_outage_outputs(s::BAUScenario, crit_load, t0, tf, production_factors)

    pv_kw_series = Float64[]  # actual output (not normalized)

    if any(pv.existing_kw > 0 for pv in s.pvs)  # fill in pv_kw_series
        for pv in s.pvs
            if pv.existing_kw > 0
                if length(pv_kw_series) == 0  # first non-zero existing_kw
                    pv_kw_series = pv.existing_kw * production_factors[pv.name, t0:tf]
                else
                    pv_kw_series += pv.existing_kw * production_factors[pv.name, t0:tf]
                end
            end
        end
    end

    s.outage_outputs.bau_critical_load_met, s.outage_outputs.bau_critical_load_met_time_steps, generator_fuel_use_gal = 
        bau_outage_check(crit_load[t0:tf], pv_kw_series, s.generator, s.settings.time_steps_per_hour)
    return generator_fuel_use_gal
end


"""
    bau_outage_check(critical_loads_kw::AbstractArray, pv_kw_series::AbstractArray, gen::Generator, 
        time_steps_per_hour::Int)

Determine if existing generator and/or PV can meet critical load and for how long.
    
return: (Bool, Int, Float) boolean for if the entire critical load is met, Int for number of time steps the existing 
    generator and PV can meet the critical load, and Float for the gallons of fuel used trying to meet critical load
"""
function bau_outage_check(critical_loads_kw::AbstractArray, pv_kw_series::AbstractArray, gen::Generator, 
    time_steps_per_hour::Int)
    
    generator_fuel_use_gal = 0.0 

    fuel_gal = copy(gen.fuel_avail_gal)
    if gen.existing_kw == 0 && length(pv_kw_series) == 0
        return false, 0, generator_fuel_use_gal
    end

    if gen.existing_kw > 0
        if length(pv_kw_series) == 0
            pv_kw_series = zeros(length(critical_loads_kw))
        end
        fuel_slope_gal_per_kwhe, fuel_intercept_gal_per_hr = fuel_slope_and_intercept(
            electric_efficiency_full_load=gen.electric_efficiency_full_load, 
            electric_efficiency_half_load=gen.electric_efficiency_half_load,
            fuel_higher_heating_value_kwh_per_unit=gen.fuel_higher_heating_value_kwh_per_gal
        )
            for (i, (load, pv)) in enumerate(zip(critical_loads_kw, pv_kw_series))
            unmet = load - pv
            if unmet > 0
                fuel_kwh = (fuel_gal - fuel_intercept_gal_per_hr) / fuel_slope_gal_per_kwhe
                gen_avail = minimum([fuel_kwh, gen.existing_kw * (1.0 / time_steps_per_hour)])
                # output = the greater of either the unmet load or available generation based on fuel and the min loading
                gen_output = maximum([minimum([unmet, gen_avail]), gen.min_turn_down_fraction * gen.existing_kw])
                fuel_needed = fuel_intercept_gal_per_hr + fuel_slope_gal_per_kwhe * gen_output
                fuel_gal -= fuel_needed
                generator_fuel_use_gal += fuel_needed # previous logic: max(min(fuel_needed,fuel_gal), 0)

                # if the generator cannot meet the full load, still assume it runs during the outage
                if gen_output < unmet
                    return false, i-1, generator_fuel_use_gal
                end
            end
        end

    else  # gen.existing_kw = 0 and pv.existing_kw > 0
        for (i, (load, pv)) in enumerate(zip(critical_loads_kw, pv_kw_series))
            unmet = load - pv
            if unmet > 0
                return false, i-1, generator_fuel_use_gal
            end
        end
    end

    return true, length(critical_loads_kw), generator_fuel_use_gal
end