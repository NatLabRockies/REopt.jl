# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.

function add_water_power_constraints(m,p)
	@info "Adding constraints for existing water_power"
		
	if p.s.water_power.computation_type == "quadratic_partially_discretized"	
		@info "Adding quadratic_partially_discretized constraint type for the water_power power output: model with with a discretized water_power efficiency"
		
		@variable(m, reservoir_head[ts in p.time_steps] >= 0)
		@variable(m, turbine_efficiency[t in p.techs.water_power_turbines, ts in p.time_steps] >= 0)
		@variable(m, efficiency_reservoir_head_product[t in p.techs.water_power_turbines, ts in p.time_steps] >= 0)

		turbine_techs = p.techs.water_power_turbines
		
		for t in 1:Int(length(Hydro_techs))
			@constraint(m, [ts in p.time_steps],
				m[:dvRatedProduction][Hydro_techs[t],ts] == 9810*0.001 * m[:dvWaterOutFlow][Hydro_techs[t],ts] * (m[:efficiency_reservoir_head_product][Hydro_techs[t],ts] - (t/1000) ) # the (t/1000) term establishes priority of turbine usage by having a slight efficiency difference for each turbine
						)
		end

		@constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] >= 0)
		@constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] <= 1000) # TODO: enter the maximum reservoir head as an input into the model
		@constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] == (p.s.water_power.coefficient_e_reservoir_head* m[:dvWaterVolume][ts]) + p.s.water_power.coefficient_f_reservoir_head )
		
		# represent the product of the reservoir head and turbine efficiency as a separate variable (Gurobi can only multiply two variables together)
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:efficiency_reservoir_head_product][t, ts] <= 500) # TODO, switch this to a more intentional value
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:efficiency_reservoir_head_product][t, ts] ==  m[:reservoir_head][ts] * m[:turbine_efficiency][t, ts])
		
		# Descritization of the efficiency, based on the water flow range
		efficiency_bins = collect(1:p.s.water_power.number_of_efficiency_bins) 
		waterflow_increments = (p.s.water_power.maximum_water_output_cubic_meter_per_second_per_turbine - p.s.water_power.minimum_water_output_cubic_meter_per_second_per_turbine) / p.s.water_power.number_of_efficiency_bins #[0, 15, 30, 75]
		
		# Generate a vector of the water flow bin limits
		water_flow_bin_limits = zeros(1 + p.s.water_power.number_of_efficiency_bins)
		water_flow_bin_limits[1] = p.s.water_power.minimum_water_output_cubic_meter_per_second_per_turbine
		for i in efficiency_bins
			water_flow_bin_limits[1+i] = round(p.s.water_power.minimum_water_output_cubic_meter_per_second_per_turbine + (i * waterflow_increments), digits=3)
		end
		
		#redefine the last bin limit as the max water flow through a turbine
		water_flow_bin_limits[1 + p.s.water_power.number_of_efficiency_bins] = p.s.water_power.maximum_water_output_cubic_meter_per_second_per_turbine
		
		# Print some data to double check the computations:
		print("\n Efficiency bins are:")
		print(efficiency_bins)
		print("\n The waterflow bin limits are:")
		print(water_flow_bin_limits)
		print("\n The hydro techs are: ")
		print(Hydro_techs)

		# Compute the average turbine efficiency for each water flow bin:
		descritized_efficiency = zeros(p.s.water_power.number_of_efficiency_bins)
		for i in efficiency_bins
			# compute the efficiency at the beginning and end of the bin 
			x1 = (p.s.water_power.coefficient_a_efficiency * water_flow_bin_limits[i] * water_flow_bin_limits[i]) + (p.s.water_power.coefficient_b_efficiency * water_flow_bin_limits[i]) + p.s.water_power.coefficient_c_efficiency
			x2 = (p.s.water_power.coefficient_a_efficiency * water_flow_bin_limits[i+1] * water_flow_bin_limits[i+1]) + (p.s.water_power.coefficient_b_efficiency * water_flow_bin_limits[i+1]) + p.s.water_power.coefficient_c_efficiency
			# compute the average and store it in the discretized_efficiency vector
			descritized_efficiency[i] = (x1 + x2)/2
		end
		
		# define a binary variable for the turbine efficiencies
		@variable(m, waterflow_range_binary[ts in p.time_steps, t in p.techs.water_power_turbines, i in efficiency_bins], Bin)
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:turbine_efficiency][t, ts] <= 1.0) # the maximum efficiency fraction is 100%
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:turbine_efficiency][t, ts] == sum(m[:waterflow_range_binary][ts,t,i]*descritized_efficiency[i] for i in efficiency_bins))                  #(p.s.water_power.coefficient_a_efficiency* m[:dvWaterOutFlow][t,ts]) + p.s.water_power.coefficient_b_efficiency )
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:dvWaterOutFlow][t,ts] <= sum(m[:waterflow_range_binary][ts,t,i] * water_flow_bin_limits[i+1] for i in efficiency_bins) )
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:dvWaterOutFlow][t,ts] >= sum(m[:waterflow_range_binary][ts,t,i] * water_flow_bin_limits[i] for i in efficiency_bins) )
		
		# only have one binary active at a time
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], sum(m[:waterflow_range_binary][ts,t,i] for i in efficiency_bins) <= 1)

	elseif p.s.water_power.computation_type == "fixed_efficiency_linearized_reservoir_head"
		@info "Adding water_power power output constraint using a fixed efficiency and linearized reservoir head"
		# TODO: make an option that is like this, but linearized using discretization

        @variable(m, reservoir_head[ts in p.time_steps] >= 0)

		Hydro_techs = p.techs.water_power_turbines
		for t in 1:Int(length(Hydro_techs))
        @constraint(m, [ts in p.time_steps],
            m[:dvRatedProduction][Hydro_techs[t],ts] == 9810*0.001 * m[:dvWaterOutFlow][Hydro_techs[t],ts] * m[:reservoir_head][ts] * (p.s.water_power.fixed_turbine_efficiency- (t/1000) )
        )
		end

        @constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] >= 0)
        @constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] <= 1000) # TODO: enter the maximum reservoir head as an input into the model
        @constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] == (p.s.water_power.coefficient_e_reservoir_head* m[:dvWaterVolume][ts]) + p.s.water_power.coefficient_f_reservoir_head )


	elseif p.s.water_power.computation_type == "average_power_conversion"
		# This is a simplified constraint that uses an average conversion for water flow and kW output
		@info "Adding water_power power output constraint using the average power conversion"

		Hydro_techs = p.techs.water_power_turbines
		for t in 1:Int(length(Hydro_techs))
			@constraint(m, [ts in p.time_steps],
					m[:dvRatedProduction][Hydro_techs[t],ts] == m[:dvWaterOutFlow][Hydro_techs[t],ts] * (1/p.s.water_power.average_cubic_meters_per_second_per_kw)* (1- (t/1000))  # convert to kW/time step, for instance: m3/15min  * kwh/m3 * (0.25 hrs/1hr); the "1 - (t/1000)" is for turbine prioritization
						)
		end
	
	elseif p.s.water_power.computation_type == "quadratic_unsimplified" # This equation has not been tested directly
		@info "Adding quadratic1 constraint for the water_power power output"
		@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines],
		m[:dvRatedProduction][t,ts] == 9810*0.001 * m[:dvWaterOutFlow][t,ts] *
											(p.s.water_power.coefficient_a_efficiency*((m[:dvWaterOutFlow][t,ts]*m[:dvWaterOutFlow][t,ts])) + (p.s.water_power.coefficient_b_efficiency* m[:dvWaterOutFlow][t,ts]) + p.s.water_power.coefficient_c_efficiency ) *
											(p.s.water_power.coefficient_d_reservoir_head*((m[:dvWaterVolume][ts]*m[:dvWaterVolume][ts])) + (p.s.water_power.coefficient_e_reservoir_head* m[:dvWaterVolume][ts]) + p.s.water_power.coefficient_f_reservoir_head )
					)
	
	#elseif p.s.water_power.computation_type == "linearized_constraints"
		#TODO: add version with completely linearized constraints

	else 
		throw(@error("Invalid input for the computation_type field"))
	end

	print("*********The p.techs.elec are: $(p.techs.elec)")

	# Total water volume is between the max and min levels
	@constraint(m, [ts in p.time_steps],
		m[:dvWaterVolume][ts] <= p.s.water_power.cubic_meter_maximum
				)
	@constraint(m, [ts in p.time_steps],
		p.s.water_power.cubic_meter_minimum <= m[:dvWaterVolume][ts] 
				)
	
	# Water flow rate from all turbines combined is above the required minimum water flow
	@constraint(m, [ts in p.time_steps], # t in p.techs.water_power_turbines],
		 sum(m[:dvWaterOutFlow][t, ts] for t in p.techs.water_power_turbines) + m[:dvSpillwayWaterFlow][ts] >= p.s.water_power.minimum_water_output_cubic_meter_per_second_total_of_all_turbines   # m[:dvWaterOutFlow][t, ts]
				)
	
	# Each turbine must meet the minimum water flow requirement of an individual turbine, if it is on
	@constraint(m, [t in p.techs.water_power_turbines, ts in p.time_steps], 
			m[:dvWaterOutFlow][t, ts] >=  m[:binTurbineActive][t,ts]*p.s.water_power.minimum_water_output_cubic_meter_per_second_per_turbine    #p.s.water_power.existing_kw_per_turbine / (p.s.water_power.efficiency_kwh_per_cubicmeter * p.hours_per_time_step)
				)
	
	# Upstream Reservoir: The total water volume changes based on the water flow rates
	final_time_step = Int(p.s.settings.time_steps_per_hour * 8760)
	time_steps_without_first_time_step = p.time_steps[2:final_time_step]
		
	@variable(m, dvWaterVolumeChange[ts in time_steps_without_first_time_step] >= -100000 )
	
	@constraint(m, [ts in time_steps_without_first_time_step], 
					m[:dvWaterVolumeChange][ts] == p.s.water_power.water_inflow_cubic_meter_per_second[ts] - m[:dvSpillwayWaterFlow][ts] - sum(m[:dvWaterOutFlow][t,ts] for t in p.techs.water_power_turbines) + sum(m[:dvPumpedWaterFlow][t,ts] for t in p.techs.water_power_pumps)
				)
	
	@constraint(m, [ts in time_steps_without_first_time_step], 
					m[:dvWaterVolume][ts] == 
					m[:dvWaterVolume][ts-1]  
					+ ((3600/p.s.settings.time_steps_per_hour) * m[:dvWaterVolumeChange][ts])   # The (3600/p.s.settings.time_steps_per_hour) converts from m^3 per second, to m^3 per timestep
				)
	
	@constraint(m, m[:dvWaterVolume][1] == p.s.water_power.initial_reservoir_volume) 
		
	# Upstream Reservoir: Total water volume must be the same in the beginning and the end
	@constraint(m, m[:dvWaterVolume][1] == m[:dvWaterVolume][maximum(p.time_steps)])
	
	# Define the power rating for each turbine
	@variable(m, turbine_power_rating[t in p.techs.water_power_turbines] >= 0)

	# If the existing power ratings are defined, limit the power rating to the existing kw
	if p.s.water_power.existing_kw_per_turbine != nothing
		@constraint(m, [t in p.techs.water_power_turbines], m[:turbine_power_rating][t] == p.s.water_power.existing_kw_per_turbine)
	else
		@constraint(m, [t in p.techs.water_power_turbines], m[:turbine_power_rating][t] >= p.s.water_power.min_kw_turbine)
		@constraint(m, [t in p.techs.water_power_turbines], m[:turbine_power_rating][t] <= p.s.water_power.max_kw_turbine)
	end
	
	# Limit power output from the water_power turbines:
	@constraint(m, [ts in p.time_steps, t in p.techs.water_power_turbines], m[:dvRatedProduction][t,ts] <= m[:binTurbineActive][t,ts]* m[:turbine_power_rating][t])
	
	# Limit the water flow through the spillway, if a value was input
	if !isnothing(p.s.water_power.spillway_maximum_cubic_meter_per_second)
		@constraint(m, [ts in p.time_steps], m[:dvSpillwayWaterFlow][ts] <= p.s.water_power.spillway_maximum_cubic_meter_per_second)
	end 

	# Model a downstream reservoir
	if p.s.water_power.model_downstream_reservoir == true
		print("\n Adding downstream reservoir variables and constraints")
		
		final_time_step = Int(p.s.settings.time_steps_per_hour * 8760)
		time_steps_without_first_time_step = p.time_steps[2:final_time_step]

		@variable(m, dvDownstreamReservoirNetWaterFlow[ts in time_steps_without_first_time_step] >= -100000 )
		
		@constraint(m, [ts in time_steps_without_first_time_step], 
						m[:dvDownstreamReservoirNetWaterFlow][ts] == m[:dvSpillwayWaterFlow][ts] + sum(m[:dvWaterOutFlow][t,ts] for t in p.techs.water_power_turbines) - sum(m[:dvPumpedWaterFlow][t,ts] for t in p.techs.water_power_pumps) - m[:dvDownstreamReservoirWaterOutflow][ts]
					)
		
		# Downstream Reservoir: The total water volume changes based on the water flow rates
		@constraint(m, [ts in time_steps_without_first_time_step], m[:dvDownstreamReservoirWaterVolume][ts] == m[:dvDownstreamReservoirWaterVolume][ts-1] + ((3600/p.s.settings.time_steps_per_hour)* (m[:dvDownstreamReservoirNetWaterFlow][ts]))
		)
		
		@constraint(m, m[:dvDownstreamReservoirWaterVolume][1] == p.s.water_power.initial_downstream_reservoir_water_volume) 

		# Downstream Reservoir: Total water volume must be the same in the beginning and the end
		@constraint(m, m[:dvDownstreamReservoirWaterVolume][1] == m[:dvDownstreamReservoirWaterVolume][maximum(p.time_steps)])

		# Downstream Reservoir: Minimum and maximum water volumes
		@constraint(m, [ts in p.time_steps], m[:dvDownstreamReservoirWaterVolume][ts] >= p.s.water_power.minimum_downstream_reservoir_volume_cubic_meters)
		@constraint(m, [ts in p.time_steps], m[:dvDownstreamReservoirWaterVolume][ts] <= p.s.water_power.maximum_downstream_reservoir_volume_cubic_meters)

		# Downstream Reservoir outflow: minimum and maximum flow rates
		@constraint(m, [ts in p.time_steps], 
						m[:dvDownstreamReservoirWaterOutflow][ts] >= p.s.water_power.minimum_outflow_from_downstream_reservoir_cubic_meter_per_second 
			   		)
					
		@constraint(m, [ts in p.time_steps], 
					   m[:dvDownstreamReservoirWaterOutflow][ts] <= p.s.water_power.maximum_outflow_from_downstream_reservoir_cubic_meter_per_second
					)
					
		# Ensure that the turbines aren't on when the pumping is happening
			# binTurbineOrPump is 1 when the turbines are on; binTurbineOrPump is 0 when the pumps are operating
		@constraint(m, [ts in p.time_steps], sum(m[:binTurbineActive][t,ts] for t in p.techs.water_power_turbines) <= p.s.water_power.number_of_turbines * m[:binTurbineOrPump][ts] )
		
		@constraint(m, [ts in p.time_steps], sum(m[:binPumpingWaterActive][t,ts] for t in p.techs.water_power_pumps) <= p.s.water_power.number_of_pumps * (1 - m[:binTurbineOrPump][ts]))
		
		# Each pump must meet the minimum water flow requirement, if it is on
		@constraint(m, [t in p.techs.water_power_pumps, ts in p.time_steps], 
						m[:dvPumpedWaterFlow][t, ts] >= m[:binPumpingWaterActive][t,ts]*p.s.water_power.minimum_water_output_cubic_meter_per_second_per_turbine    # TODO: change input value to "minimum water flow cubic meter per second per turbine"
							)
		
		# Define the power rating for each pump
		@variable(m, pump_power_rating[t in p.techs.water_power_pumps] >= 0)
		
		# Pump size constraints
		if are_pumps_reversible && (p.s.water_power.existing_kw_per_pump == nothing)
			@constraint(m, [t in p.techs.water_power_pumps], m[:pump_power_rating][t] == p.s.water_power.pump_kw_to_turbine_kw_ratio_for_reversible_pumps *  m[:turbine_power_rating][t])
		elseif p.s.water_power.existing_kw_per_pump != nothing
			@constraint(m, [t in p.techs.water_power_pumps], m[:pump_power_rating][t] == p.s.water_power.existing_kw_per_pump)
		else
			@constraint(m, [t in p.techs.water_power_pumps], m[:pump_power_rating][t] >= p.s.water_power.min_kw_pump)
			@constraint(m, [t in p.techs.water_power_pumps], m[:pump_power_rating][t] <= p.s.water_power.max_kw_pump)
		end

		# The electric power input into each pump must be below the pump's electric power rating
		@constraint(m, [t in p.techs.water_power_pumps, ts in p.time_steps], 
						m[:dvPumpPowerInput][t, ts] <= m[:binPumpingWaterActive][t,ts] * m[:pump_power_rating][t]
					)
					
		if p.s.water_power.computation_type == "average_power_conversion"
			
			# Conversion between pumped water flow rate and power input into the pump
			@constraint(m, [t in p.techs.water_power_pumps, ts in p.time_steps], 
						m[:dvPumpedWaterFlow][t, ts] == m[:dvPumpPowerInput][t, ts] * p.s.water_power.water_pump_average_cubic_meters_per_second_per_kw )

		else
			throw(@error("A downstream reservoir is only compatible with average_power_conversion at the moment"))
		end
		
	else
		# If pumped water is not allowed, then binAnyTurbineActive is always 1 (meaning that the turbines can always operate)
			# This constraint shouldn't be needed
		#@constraint(m, [ts in p.time_steps], binAnyTurbineActive[ts] == 1)
		
		@info("Preventing use of the water pump variables because there is no downstream reservoir")
		for t in p.techs.water_power_pumps
			for ts in p.time_steps
				fix(m[:dvPumpedWaterFlow][t, ts], 0.0, force=true)
				fix(m[:dvPumpPowerInput][t, ts], 0.0, force=true)
			end
		end				
	end

	# Create an array of binary variable names for turbine or turbine and pumps
	dvs = []
	if p.s.water_power.model_downstream_reservoir
		dvs = ["binTurbineActive","binPumpingWaterActive"]
	else
		dvs = ["binTurbineActive"]
	end


	# Define the minimum operating time (in time steps) for the water_power turbine
	if p.s.water_power.minimum_operating_time_steps_individual_turbine > 1
		print("\n Adding minimum operating time constraint \n")
		@variable(m, indicator_min_operating_time[t in p.techs.water_power_turbines, ts in p.time_steps, dv in dvs], Bin)
		for dv in dvs
			for t in p.techs.water_power_turbines, ts in 1:Int(length(p.time_steps)- p.s.water_power.minimum_operating_time_steps_individual_turbine - 1 )
				@constraint(m, m[:indicator_min_operating_time][t, ts, dv] =>  { sum(m[Symbol(dv)][t,ts+i] for i in 1:p.s.water_power.minimum_operating_time_steps_individual_turbine) >= p.s.water_power.minimum_operating_time_steps_individual_turbine} ) 
				@constraint(m, !m[:indicator_min_operating_time][t, ts, dv] => { m[Symbol(dv)][t,ts+1] - m[Symbol(dv)][t,ts] <= 0  } )
			end
		end
	end
	
	# Define the minimum operating time for the maximum water flow (in time steps) for a water_power turbine
	if p.s.water_power.minimum_operating_time_steps_at_local_maximum_turbine_output > 1
		print("\n Adding a constraint for the minimum operating time at a local maximum water flow \n")
		@variable(m, indicator_turn_down[t in p.techs.water_power_turbines, ts in p.time_steps, dv in dvs], Bin)	
		for dv in dvs
			if dv == "binTurbineActive"
				variable = Symbol("dvWaterOutFlow")
			elseif dv == "binPumpingWaterActive"
				variable = Symbol("dvPumpedWaterFlow")
			else
				throw(@error("Error in applying the local maximum operating time constraint"))
			end
			for t in p.techs.water_power_turbines, ts in (2 + p.s.water_power.minimum_operating_time_steps_at_local_maximum_turbine_output):Int(length(p.time_steps))
				for i in 1:p.s.water_power.minimum_operating_time_steps_at_local_maximum_turbine_output
					@constraint(m, m[:indicator_turn_down][t, ts, dv] => {m[variable][t, ts-i] == m[variable][t,ts-i-1]})
				end
				@constraint(m, !m[:indicator_turn_down][t, ts, dv] => { m[variable][t,ts] >= m[variable][t,ts-1]  })
			end
		end
	end

	if p.s.water_power.minimum_turbine_off_time_steps > 1
		print("\n Adding minimum off duration for the turbines \n")
		@variable(m, indicator_turbine_turn_off[t in p.techs.water_power_turbines, ts in p.time_steps], Bin)
		for t in p.techs.water_power_turbines, ts in 1:Int(length(p.time_steps)- p.s.water_power.minimum_turbine_off_time_steps - 1 )
			@constraint(m, m[:indicator_turbine_turn_off][t, ts] =>  { sum(m[:binTurbineActive][t,ts+i] for i in 1:p.s.water_power.minimum_turbine_off_time_steps) <= 0 } ) 
			@constraint(m, !m[:indicator_turbine_turn_off][t, ts] => { m[:binTurbineActive][t,ts+1] - m[:binTurbineActive][t,ts] >= 0  } )
		end
	end
	
	# TODO: remove this constraint, which prevents a spike in the spillway use during the first time step
	@constraint(m, [ts in p.time_steps], m[:dvSpillwayWaterFlow][1] == 0)

end

