# REopt®, Copyright (c) Alliance for Energy Innovation, LLC. See also https://github.com/NatLabRockies/REopt.jl/blob/master/LICENSE.
"""
    Techs(p::REoptInputs, s::BAUScenario)

Create a `Techs` struct for the BAUInputs
"""
function Techs(p::REoptInputs, s::BAUScenario)
    pvtechs = String[pv.name for pv in s.pvs]

    all_techs = copy(pvtechs)
    elec = copy(pvtechs)
    techs_no_turndown = copy(pvtechs)
    techs_no_curtail = String[]
    segmented_techs = String[]
    gentechs = String[]
    pbi_techs = String[]
    heating_techs = String[]
    cooling_techs = String[]
    boiler_techs = String[]
    chp_techs = String[]
    requiring_oper_res = String[]  
    providing_oper_res = String[]
    electric_chillers = String[]
    absorption_chillers = String[]
    steam_turbines = String[]
    techs_can_supply_steam_turbine = String[]
    electric_heaters = String[]
    techs_can_serve_space_heating = String[]
    techs_can_serve_dhw = String[]
    techs_can_serve_process_heat = String[]
    ghp_techs = String[]
    ashp_techs = String[]
    ashp_wh_techs = String[]

    if p.s.generator.existing_kw > 0
        push!(all_techs, "Generator")
        push!(gentechs, "Generator")
        push!(elec, "Generator")
    end

    if !isnothing(s.existing_boiler)
        push!(all_techs, "ExistingBoiler")
        push!(heating_techs, "ExistingBoiler")
        push!(boiler_techs, "ExistingBoiler")
        if s.existing_boiler.can_serve_space_heating
            push!(techs_can_serve_space_heating, "ExistingBoiler")
        end
        if s.existing_boiler.can_serve_dhw
            push!(techs_can_serve_dhw, "ExistingBoiler")
        end       
        if s.existing_boiler.can_serve_process_heat
            push!(techs_can_serve_process_heat, "ExistingBoiler")
        end  
    end

    if !isnothing(s.existing_chiller)
        push!(all_techs, "ExistingChiller")
        push!(electric_chillers, "ExistingChiller")
    end

    cooling_techs = union(electric_chillers, absorption_chillers)
    fuel_burning_techs = union(gentechs, boiler_techs, chp_techs)
    thermal_techs = union(heating_techs, boiler_techs, cooling_techs)

    Techs(
        all_techs,
        elec,
        pvtechs,
        gentechs,
        pbi_techs,
        techs_no_curtail,
        techs_no_turndown,
        segmented_techs,
        heating_techs,
        cooling_techs,
        boiler_techs,
        fuel_burning_techs,
        thermal_techs,
        chp_techs,
        requiring_oper_res,
        providing_oper_res,
        electric_chillers,
        absorption_chillers,
        steam_turbines,
        techs_can_supply_steam_turbine,
        electric_heaters,
        techs_can_serve_space_heating,
        techs_can_serve_dhw,
        techs_can_serve_process_heat,
        ghp_techs,
        ashp_techs,
        ashp_wh_techs
    )
end


"""
    Techs(s::Scenario) 

Create a `Techs` struct for the REoptInputs.
"""
function Techs(s::Scenario)
    #TODO: refactor code duplicated in Tech(s::MPCScenario)
    pvtechs = String[pv.name for pv in s.pvs]
    if length(Base.Set(pvtechs)) != length(pvtechs)
        throw(@error("PV names must be unique, got $(pvtechs)"))
    end

    all_techs = copy(pvtechs)
    elec = copy(pvtechs)
    techs_no_turndown = copy(pvtechs)
    gentechs = String[]
    pbi_techs = String[]
    techs_no_curtail = String[]
    segmented_techs = String[]
    heating_techs = String[]
    cooling_techs = String[]
    boiler_techs = String[]
    chp_techs = String[]
    requiring_oper_res = String[] 
    providing_oper_res = String[]
    electric_chillers = String[]
    absorption_chillers = String[]
    steam_turbines = String[]
    techs_can_supply_steam_turbine = String[]
    electric_heaters = String[]   
    techs_can_serve_space_heating = String[]
    techs_can_serve_dhw = String[] 
    techs_can_serve_process_heat = String[]
    ghp_techs = String[]
    ashp_techs = String[]
    ashp_wh_techs = String[]

    if s.wind.max_kw > 0
        push!(all_techs, "Wind")
        push!(elec, "Wind")
        append!(techs_no_turndown, ["Wind"])
        if s.settings.off_grid_flag
            push!(requiring_oper_res, "Wind")
            push!(providing_oper_res, "Wind")
        end
    end

    if s.generator.existing_kw + s.generator.max_kw > 0
        push!(all_techs, "Generator")
        push!(gentechs, "Generator")
        push!(elec, "Generator")
        if s.settings.off_grid_flag
            push!(providing_oper_res, "Generator")
        end
    end

    if !isnothing(s.existing_boiler)
        push!(all_techs, "ExistingBoiler")
        push!(heating_techs, "ExistingBoiler")
        push!(boiler_techs, "ExistingBoiler")
        if s.existing_boiler.can_supply_steam_turbine
            push!(techs_can_supply_steam_turbine, "ExistingBoiler")
        end   
        if s.existing_boiler.can_serve_space_heating
            push!(techs_can_serve_space_heating, "ExistingBoiler")
        end
        if s.existing_boiler.can_serve_dhw
            push!(techs_can_serve_dhw, "ExistingBoiler")
        end       
        if s.existing_boiler.can_serve_process_heat
            push!(techs_can_serve_process_heat, "ExistingBoiler")
        end   
    end

    if !isnothing(s.boiler)
        push!(all_techs, "Boiler")
        push!(heating_techs, "Boiler")
        push!(boiler_techs, "Boiler")
        if s.boiler.can_supply_steam_turbine
            push!(techs_can_supply_steam_turbine, "Boiler")
        end        
        if s.boiler.can_serve_space_heating
            push!(techs_can_serve_space_heating, "Boiler")
        end
        if s.boiler.can_serve_dhw
            push!(techs_can_serve_dhw, "Boiler")
        end
        if s.boiler.can_serve_process_heat
            push!(techs_can_serve_process_heat, "Boiler")
        end
    end
    
    if !isnothing(s.chp)
        push!(all_techs, "CHP")
        push!(elec, "CHP")
        push!(chp_techs, "CHP")
        if s.chp.can_supply_steam_turbine
            push!(techs_can_supply_steam_turbine, "CHP")
        end
        if s.chp.can_serve_space_heating
            push!(techs_can_serve_space_heating, "CHP")
        end
        if s.chp.can_serve_dhw
            push!(techs_can_serve_dhw, "CHP")
        end
        if s.chp.can_serve_process_heat
            push!(techs_can_serve_process_heat, "CHP")
        end
        if s.settings.off_grid_flag
            if s.chp.operating_reserve_required_fraction > 0.0
                push!(requiring_oper_res, "CHP")
            else
                push!(providing_oper_res, "CHP")
            end
        end
    end

    if !isempty(s.ghp_option_list) && !isnothing(s.ghp_option_list[1])
        #push!(all_techs, "GHP")  #TODO: refactor GHP so that it's a part of all_techs, potentially adding in things like sizes for the binary options?
        push!(heating_techs, "GHP")
        push!(cooling_techs, "GHP")
        push!(ghp_techs, "GHP")
        if any((!isnothing(ghp) && ghp.can_supply_steam_turbine) for ghp in s.ghp_option_list)
            push!(techs_can_supply_steam_turbine, "GHP")
        end
        if any(ghp.can_serve_space_heating for ghp in s.ghp_option_list)
            push!(techs_can_serve_space_heating, "GHP")
        end
        if any(ghp.can_serve_dhw for ghp in s.ghp_option_list)
            push!(techs_can_serve_dhw, "GHP")
        end
        if any(ghp.can_serve_process_heat for ghp in s.ghp_option_list)
            push!(techs_can_serve_process_heat, "GHP")
        end
    end

    if !isnothing(s.existing_chiller)
        push!(all_techs, "ExistingChiller")
        push!(cooling_techs, "ExistingChiller")
        push!(electric_chillers, "ExistingChiller")
    end

    if !isnothing(s.absorption_chiller)
        push!(all_techs, "AbsorptionChiller")
        push!(cooling_techs, "AbsorptionChiller")
        push!(absorption_chillers, "AbsorptionChiller")
    end

    if !isnothing(s.steam_turbine)
        push!(all_techs, "SteamTurbine")
        push!(elec, "SteamTurbine")
        push!(heating_techs, "SteamTurbine")
        push!(steam_turbines, "SteamTurbine")
        if s.steam_turbine.can_serve_space_heating
            push!(techs_can_serve_space_heating, "SteamTurbine")
        end
        if s.steam_turbine.can_serve_dhw
            push!(techs_can_serve_dhw, "SteamTurbine")
        end
        if s.steam_turbine.can_serve_process_heat
            push!(techs_can_serve_process_heat, "SteamTurbine")
        end
    end    

    if !isnothing(s.electric_heater)
        push!(all_techs, "ElectricHeater")
        push!(heating_techs, "ElectricHeater")
        push!(electric_heaters, "ElectricHeater")
        if s.electric_heater.can_supply_steam_turbine
            push!(techs_can_supply_steam_turbine, "ElectricHeater")
        end
        if s.electric_heater.can_serve_space_heating
            push!(techs_can_serve_space_heating, "ElectricHeater")
        end
        if s.electric_heater.can_serve_dhw
            push!(techs_can_serve_dhw, "ElectricHeater")
        end
        if s.electric_heater.can_serve_process_heat
            push!(techs_can_serve_process_heat, "ElectricHeater")
        end
    end
    
    if !isnothing(s.cst)
        push!(all_techs, "CST")
        push!(heating_techs, "CST")
        push!(electric_heaters, "CST")
        if s.cst.can_supply_steam_turbine
            push!(techs_can_supply_steam_turbine, "CST")
        end
        if s.cst.can_serve_space_heating
            push!(techs_can_serve_space_heating, "CST")
        end
        if s.cst.can_serve_dhw
            push!(techs_can_serve_dhw, "CST")
        end
        if s.cst.can_serve_process_heat
            push!(techs_can_serve_process_heat, "CST")
        end
    end

    if !isnothing(s.ashp)
        push!(all_techs, "ASHPSpaceHeater")
        push!(heating_techs, "ASHPSpaceHeater")
        push!(electric_heaters, "ASHPSpaceHeater")
        push!(ashp_techs, "ASHPSpaceHeater")
        if s.ashp.can_supply_steam_turbine
            push!(techs_can_supply_steam_turbine, "ASHPSpaceHeater")
        end
        if s.ashp.can_serve_space_heating
            push!(techs_can_serve_space_heating, "ASHPSpaceHeater")
        end
        if s.ashp.can_serve_dhw
            push!(techs_can_serve_dhw, "ASHPSpaceHeater")
        end
        if s.ashp.can_serve_process_heat
            push!(techs_can_serve_process_heat, "ASHPSpaceHeater")
        end
        if s.ashp.can_serve_cooling
            push!(cooling_techs, "ASHPSpaceHeater")
        end
    end

    if !isnothing(s.ashp_wh)
        push!(all_techs, "ASHPWaterHeater")
        push!(heating_techs, "ASHPWaterHeater")
        push!(electric_heaters, "ASHPWaterHeater")
        push!(ashp_techs, "ASHPWaterHeater")
        push!(ashp_wh_techs, "ASHPWaterHeater")
        if s.ashp_wh.can_supply_steam_turbine
            push!(techs_can_supply_steam_turbine, "ASHPWaterHeater")
        end
        if s.ashp_wh.can_serve_space_heating
            push!(techs_can_serve_space_heating, "ASHPWaterHeater")
        end
        if s.ashp_wh.can_serve_dhw
            push!(techs_can_serve_dhw, "ASHPWaterHeater")
        end
        if s.ashp_wh.can_serve_process_heat
            push!(techs_can_serve_process_heat, "ASHPWaterHeater")
        end
        if s.ashp_wh.can_serve_cooling
            push!(cooling_techs, "ASHPWaterHeater")
        end
    end

    if s.settings.off_grid_flag
        append!(requiring_oper_res, pvtechs)
        append!(providing_oper_res, pvtechs)
    end

    if sum(s.dhw_load.loads_kw) == 0.0
        techs_can_serve_dhw = String[]
    end
    if sum(s.space_heating_load.loads_kw) == 0.0
        techs_can_serve_space_heating = String[]
    end
    if sum(s.process_heat_load.loads_kw) == 0.0
        techs_can_serve_process_heat = String[]
    end

    thermal_techs = union(heating_techs, boiler_techs, chp_techs, cooling_techs)
    fuel_burning_techs = union(gentechs, boiler_techs, chp_techs)

    # check for ability of new technologies to meet heating loads if retire_in_optimal
    if !isnothing(s.existing_boiler) && s.existing_boiler.retire_in_optimal
        if !isnothing(s.dhw_load) && s.dhw_load.annual_mmbtu > 0 && isempty(setdiff(techs_can_serve_dhw, "ExistingBoiler"))
            throw(@error("ExisitingBoiler.retire_in_optimal is true, but no other heating technologies can meet DomesticHotWater load."))
        end
        if !isnothing(s.space_heating_load) && s.space_heating_load.annual_mmbtu > 0 && isempty(setdiff(techs_can_serve_space_heating, "ExistingBoiler"))
            throw(@error("ExisitingBoiler.retire_in_optimal is true, but no other heating technologies can meet SpaceHeating load."))
        end
        if !isnothing(s.process_heat_load) && s.process_heat_load.annual_mmbtu > 0 && isempty(setdiff(techs_can_serve_process_heat, "ExistingBoiler"))
            throw(@error("ExisitingBoiler.retire_in_optimal is true, but no other heating technologies can meet ProcessHeat load."))
        end 
    end
    if !isnothing(s.existing_chiller) && s.existing_chiller.retire_in_optimal
        if !isnothing(s.cooling_load) && sum(s.cooling_load.loads_kw_thermal) > 0 && isempty(setdiff(cooling_techs, "ExistingChiller"))
            throw(@error("ExisitingChiller.retire_in_optimal is true, but no other technologies can meet cooling load."))
        end 
    end

    Techs(
        all_techs,
        elec,
        pvtechs,
        gentechs,
        pbi_techs,
        techs_no_curtail,
        techs_no_turndown,
        segmented_techs,
        heating_techs,
        cooling_techs,
        boiler_techs,
        fuel_burning_techs,
        thermal_techs,
        chp_techs,
        requiring_oper_res, 
        providing_oper_res, 
        electric_chillers,
        absorption_chillers,
        steam_turbines,
        techs_can_supply_steam_turbine,
        electric_heaters,
        techs_can_serve_space_heating,
        techs_can_serve_dhw,
        techs_can_serve_process_heat,
        ghp_techs,
        ashp_techs,
        ashp_wh_techs
    )
end


"""
    Techs(s::MPCScenario) 

Create a `Techs` struct for the MPCInputs
"""
function Techs(s::MPCScenario)
    pvtechs = String[pv.name for pv in s.pvs]
    if length(Base.Set(pvtechs)) != length(pvtechs)
        throw(@error("PV names must be unique, got $(pvtechs)"))
    end

    all_techs = copy(pvtechs)
    techs_no_turndown = copy(pvtechs)
    gentechs = String[]
    if s.generator.size_kw > 0
        push!(all_techs, "Generator")
        push!(gentechs, "Generator")
    end

    Techs(
        all_techs,
        all_techs,
        pvtechs,
        gentechs,
        String[],
        String[],
        techs_no_turndown,
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[],
        String[]
    )
end