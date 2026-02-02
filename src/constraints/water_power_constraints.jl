# REopt®, Copyright (c) Alliance for Sustainable Energy, LLC. See also https://github.com/NREL/REopt.jl/blob/master/LICENSE.

function add_existing_hydropower_constraints(m,p)
	@info "Adding constraints for existing hydropower"
		
	if p.s.existing_hydropower.computation_type == "quadratic_partially_discretized"	
		@info "Adding quadratic_partially_discretized constraint type for the hydropower power output: model with with a discretized hydropower efficiency"
		
		@variable(m, reservoir_head[ts in p.time_steps] >= 0)
		@variable(m, turbine_efficiency[t in p.techs.existing_hydropower, ts in p.time_steps] >= 0)
		@variable(m, efficiency_reservoir_head_product[t in p.techs.existing_hydropower, ts in p.time_steps] >= 0)

		Hydro_techs = p.techs.existing_hydropower
		
		for t in 1:Int(length(Hydro_techs))
			@constraint(m, [ts in p.time_steps],
				m[:dvRatedProduction][Hydro_techs[t],ts] == 9810*0.001 * m[:dvWaterOutFlow][Hydro_techs[t],ts] * (m[:efficiency_reservoir_head_product][Hydro_techs[t],ts] - (t/1000) ) # the (t/1000) term establishes priority of turbine usage by having a slight efficiency difference for each turbine
						)
		end

		@constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] >= 0)
		@constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] <= 1000) # TODO: enter the maximum reservoir head as an input into the model
		@constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] == (p.s.existing_hydropower.coefficient_e_reservoir_head* m[:dvWaterVolume][ts]) + p.s.existing_hydropower.coefficient_f_reservoir_head )
		
		# represent the product of the reservoir head and turbine efficiency as a separate variable (Gurobi can only multiply two variables together)
		@constraint(m, [ts in p.time_steps, t in p.techs.existing_hydropower], m[:efficiency_reservoir_head_product][t, ts] <= 500) # TODO, switch this to a more intentional value
		@constraint(m, [ts in p.time_steps, t in p.techs.existing_hydropower], m[:efficiency_reservoir_head_product][t, ts] ==  m[:reservoir_head][ts] * m[:turbine_efficiency][t, ts])
		
		# Descritization of the efficiency, based on the water flow range
		efficiency_bins = collect(1:p.s.existing_hydropower.number_of_efficiency_bins) 
		waterflow_increments = (p.s.existing_hydropower.maximum_water_output_cubic_meter_per_second_per_turbine - p.s.existing_hydropower.minimum_water_output_cubic_meter_per_second_per_turbine) / p.s.existing_hydropower.number_of_efficiency_bins #[0, 15, 30, 75]
		
		# Generate a vector of the water flow bin limits
		water_flow_bin_limits = zeros(1 + p.s.existing_hydropower.number_of_efficiency_bins)
		water_flow_bin_limits[1] = p.s.existing_hydropower.minimum_water_output_cubic_meter_per_second_per_turbine
		for i in efficiency_bins
			water_flow_bin_limits[1+i] = round(p.s.existing_hydropower.minimum_water_output_cubic_meter_per_second_per_turbine + (i * waterflow_increments), digits=3)
		end
		
		#redefine the last bin limit as the max water flow through a turbine
		water_flow_bin_limits[1 + p.s.existing_hydropower.number_of_efficiency_bins] = p.s.existing_hydropower.maximum_water_output_cubic_meter_per_second_per_turbine
		
		# Print some data to double check the computations:
		print("\n Efficiency bins are:")
		print(efficiency_bins)
		print("\n The waterflow bin limits are:")
		print(water_flow_bin_limits)
		print("\n The hydro techs are: ")
		print(Hydro_techs)

		# Compute the average turbine efficiency for each water flow bin:
		descritized_efficiency = zeros(p.s.existing_hydropower.number_of_efficiency_bins)
		for i in efficiency_bins
			# compute the efficiency at the beginning and end of the bin 
			x1 = (p.s.existing_hydropower.coefficient_a_efficiency * water_flow_bin_limits[i] * water_flow_bin_limits[i]) + (p.s.existing_hydropower.coefficient_b_efficiency * water_flow_bin_limits[i]) + p.s.existing_hydropower.coefficient_c_efficiency
			x2 = (p.s.existing_hydropower.coefficient_a_efficiency * water_flow_bin_limits[i+1] * water_flow_bin_limits[i+1]) + (p.s.existing_hydropower.coefficient_b_efficiency * water_flow_bin_limits[i+1]) + p.s.existing_hydropower.coefficient_c_efficiency
			# compute the average and store it in the discretized_efficiency vector
			descritized_efficiency[i] = (x1 + x2)/2
		end
		
		# define a binary variable for the turbine efficiencies
		@variable(m, waterflow_range_binary[ts in p.time_steps, t in p.techs.existing_hydropower, i in efficiency_bins], Bin)
		@constraint(m, [ts in p.time_steps, t in p.techs.existing_hydropower], m[:turbine_efficiency][t, ts] <= 1.0) # the maximum efficiency fraction is 100%
		@constraint(m, [ts in p.time_steps, t in p.techs.existing_hydropower], m[:turbine_efficiency][t, ts] == sum(m[:waterflow_range_binary][ts,t,i]*descritized_efficiency[i] for i in efficiency_bins))                  #(p.s.existing_hydropower.coefficient_a_efficiency* m[:dvWaterOutFlow][t,ts]) + p.s.existing_hydropower.coefficient_b_efficiency )
		@constraint(m, [ts in p.time_steps, t in p.techs.existing_hydropower], m[:dvWaterOutFlow][t,ts] <= sum(m[:waterflow_range_binary][ts,t,i] * water_flow_bin_limits[i+1] for i in efficiency_bins) )
		@constraint(m, [ts in p.time_steps, t in p.techs.existing_hydropower], m[:dvWaterOutFlow][t,ts] >= sum(m[:waterflow_range_binary][ts,t,i] * water_flow_bin_limits[i] for i in efficiency_bins) )
		
		# only have one binary active at a time
		@constraint(m, [ts in p.time_steps, t in p.techs.existing_hydropower], sum(m[:waterflow_range_binary][ts,t,i] for i in efficiency_bins) <= 1)

	elseif p.s.existing_hydropower.computation_type == "fixed_efficiency_linearized_reservoir_head"
		@info "Adding hydropower power output constraint using a fixed efficiency and linearized reservoir head"
		# TODO: make an option that is like this, but linearized using discretization

        @variable(m, reservoir_head[ts in p.time_steps] >= 0)

		Hydro_techs = p.techs.existing_hydropower
		for t in 1:Int(length(Hydro_techs))
        @constraint(m, [ts in p.time_steps],
            m[:dvRatedProduction][Hydro_techs[t],ts] == 9810*0.001 * m[:dvWaterOutFlow][Hydro_techs[t],ts] * m[:reservoir_head][ts] * (p.s.existing_hydropower.fixed_turbine_efficiency- (t/1000) )
        )
		end

        @constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] >= 0)
        @constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] <= 1000) # TODO: enter the maximum reservoir head as an input into the model
        @constraint(m, [ts in p.time_steps], m[:reservoir_head][ts] == (p.s.existing_hydropower.coefficient_e_reservoir_head* m[:dvWaterVolume][ts]) + p.s.existing_hydropower.coefficient_f_reservoir_head )


	elseif p.s.existing_hydropower.computation_type == "average_power_conversion"
		# This is a simplified constraint that uses an average conversion for water flow and kW output
		@info "Adding hydropower power output constraint using the average power conversion"

		Hydro_techs = p.techs.existing_hydropower
		for t in 1:Int(length(Hydro_techs))
			@constraint(m, [ts in p.time_steps],
					m[:dvRatedProduction][Hydro_techs[t],ts] == m[:dvWaterOutFlow][Hydro_techs[t],ts] * (1/p.s.existing_hydropower.average_cubic_meters_per_second_per_kw)* (1- (t/1000))  # convert to kW/time step, for instance: m3/15min  * kwh/m3 * (0.25 hrs/1hr); the "1 - (t/1000)" is for turbine prioritization
						)
		end
	
	elseif p.s.existing_hydropower.computation_type == "quadratic_unsimplified" # This equation has not been tested directly
		@info "Adding quadratic1 constraint for the hydropower power output"
		@constraint(m, [ts in p.time_steps, t in p.techs.existing_hydropower],
		m[:dvRatedProduction][t,ts] == 9810*0.001 * m[:dvWaterOutFlow][t,ts] *
											(p.s.existing_hydropower.coefficient_a_efficiency*((m[:dvWaterOutFlow][t,ts]*m[:dvWaterOutFlow][t,ts])) + (p.s.existing_hydropower.coefficient_b_efficiency* m[:dvWaterOutFlow][t,ts]) + p.s.existing_hydropower.coefficient_c_efficiency ) *
											(p.s.existing_hydropower.coefficient_d_reservoir_head*((m[:dvWaterVolume][ts]*m[:dvWaterVolume][ts])) + (p.s.existing_hydropower.coefficient_e_reservoir_head* m[:dvWaterVolume][ts]) + p.s.existing_hydropower.coefficient_f_reservoir_head )
					)
	
	#elseif p.s.existing_hydropower.computation_type == "linearized_constraints"
		#TODO: add version with completely linearized constraints

	else 
		throw(@error("Invalid input for the computation_type field"))
	end

	print("*********The p.techs.elec are: $(p.techs.elec)")

	# Total water volume is between the max and min levels
	@constraint(m, [ts in p.time_steps],
		m[:dvWaterVolume][ts] <= p.s.existing_hydropower.cubic_meter_maximum
				)
	@constraint(m, [ts in p.time_steps],
		p.s.existing_hydropower.cubic_meter_minimum <= m[:dvWaterVolume][ts] 
				)
	
	# Water flow rate from all turbines combined is above the required minimum water flow
	@constraint(m, [ts in p.time_steps], # t in p.techs.existing_hydropower],
		 sum(m[:dvWaterOutFlow][t, ts] for t in p.techs.existing_hydropower) + m[:dvSpillwayWaterFlow][ts] >= p.s.existing_hydropower.minimum_water_output_cubic_meter_per_second_total_of_all_turbines   # m[:dvWaterOutFlow][t, ts]
				)
	
	# Each turbine must meet the minimum water flow requirement of an individual turbine, if it is on
	@constraint(m, [t in p.techs.existing_hydropower, ts in p.time_steps], 
			m[:dvWaterOutFlow][t, ts] >=  m[:binTurbineActive][t,ts]*p.s.existing_hydropower.minimum_water_output_cubic_meter_per_second_per_turbine    #p.s.existing_hydropower.existing_kw_per_turbine / (p.s.existing_hydropower.efficiency_kwh_per_cubicmeter * p.hours_per_time_step)
				)
	
	# Upstream Reservoir: The total water volume changes based on the water flow rates
	final_time_step = Int(p.s.settings.time_steps_per_hour * 8760)
	time_steps_without_first_time_step = p.time_steps[2:final_time_step]
		
	@variable(m, dvWaterVolumeChange[ts in time_steps_without_first_time_step] >= -100000 )
	
	@constraint(m, [ts in time_steps_without_first_time_step], 
					m[:dvWaterVolumeChange][ts] == p.s.existing_hydropower.water_inflow_cubic_meter_per_second[ts] - m[:dvSpillwayWaterFlow][ts] - sum(m[:dvWaterOutFlow][t,ts] for t in p.techs.existing_hydropower) + sum(m[:dvPumpedWaterFlow][t,ts] for t in p.techs.existing_hydropower)
				)
	
	@constraint(m, [ts in time_steps_without_first_time_step], 
					m[:dvWaterVolume][ts] == 
					m[:dvWaterVolume][ts-1]  
					+ ((3600/p.s.settings.time_steps_per_hour) * m[:dvWaterVolumeChange][ts])   # The (3600/p.s.settings.time_steps_per_hour) converts from m^3 per second, to m^3 per timestep
				)
	
	@constraint(m, m[:dvWaterVolume][1] == p.s.existing_hydropower.initial_reservoir_volume) 
		
	# Upstream Reservoir: Total water volume must be the same in the beginning and the end
	@constraint(m, m[:dvWaterVolume][1] == m[:dvWaterVolume][maximum(p.time_steps)])
	
	# Limit power output from the hydropower turbines to the existing kW capacity:
	@constraint(m, [ts in p.time_steps, t in p.techs.existing_hydropower], m[:dvRatedProduction][t,ts] <= m[:binTurbineActive][t,ts]*p.s.existing_hydropower.existing_kw_per_turbine)
	
	# Limit the water flow through the spillway, if a value was input
	if !isnothing(p.s.existing_hydropower.spillway_maximum_cubic_meter_per_second)
		@constraint(m, [ts in p.time_steps], m[:dvSpillwayWaterFlow][ts] <= p.s.existing_hydropower.spillway_maximum_cubic_meter_per_second)
	end 

	# Model a downstream reservoir
	if p.s.existing_hydropower.model_downstream_reservoir == true
		print("\n Adding downstream reservoir variables and constraints")
		
		final_time_step = Int(p.s.settings.time_steps_per_hour * 8760)
		time_steps_without_first_time_step = p.time_steps[2:final_time_step]

		@variable(m, dvDownstreamReservoirNetWaterFlow[ts in time_steps_without_first_time_step] >= -100000 )
		
		@constraint(m, [ts in time_steps_without_first_time_step], 
						m[:dvDownstreamReservoirNetWaterFlow][ts] == m[:dvSpillwayWaterFlow][ts] + sum(m[:dvWaterOutFlow][t,ts] for t in p.techs.existing_hydropower) - sum(m[:dvPumpedWaterFlow][t,ts] for t in p.techs.existing_hydropower) - m[:dvDownstreamReservoirWaterOutflow][ts]
					)
		
		# Downstream Reservoir: The total water volume changes based on the water flow rates
		@constraint(m, [ts in time_steps_without_first_time_step], m[:dvDownstreamReservoirWaterVolume][ts] == m[:dvDownstreamReservoirWaterVolume][ts-1] + ((3600/p.s.settings.time_steps_per_hour)* (m[:dvDownstreamReservoirNetWaterFlow][ts]))
		)
		
		@constraint(m, m[:dvDownstreamReservoirWaterVolume][1] == p.s.existing_hydropower.initial_downstream_reservoir_water_volume) 

		# Downstream Reservoir: Total water volume must be the same in the beginning and the end
		@constraint(m, m[:dvDownstreamReservoirWaterVolume][1] == m[:dvDownstreamReservoirWaterVolume][maximum(p.time_steps)])

		# Downstream Reservoir: Minimum and maximum water volumes
		@constraint(m, [ts in p.time_steps], m[:dvDownstreamReservoirWaterVolume][ts] >= p.s.existing_hydropower.minimum_downstream_reservoir_volume_cubic_meters)
		@constraint(m, [ts in p.time_steps], m[:dvDownstreamReservoirWaterVolume][ts] <= p.s.existing_hydropower.maximum_downstream_reservoir_volume_cubic_meters)

		# Downstream Reservoir outflow: minimum and maximum flow rates
		@constraint(m, [ts in p.time_steps], 
						m[:dvDownstreamReservoirWaterOutflow][ts] >= p.s.existing_hydropower.minimum_outflow_from_downstream_reservoir_cubic_meter_per_second 
			   		)
					
		@constraint(m, [ts in p.time_steps], 
					   m[:dvDownstreamReservoirWaterOutflow][ts] <= p.s.existing_hydropower.maximum_outflow_from_downstream_reservoir_cubic_meter_per_second
					)
					
		# Ensure that the turbines aren't on when the pumping is happening
			# binTurbineOrPump is 1 when the turbines are on; binTurbineOrPump is 0 when the pumps are operating
		#NumberOfTurbines = 0
		#for t in p.techs.existing_hydropower
		#	NumberOfTurbines = NumberOfTurbines + 1
		#end 
		
		@constraint(m, [ts in p.time_steps], sum(m[:binTurbineActive][t,ts] for t in p.techs.existing_hydropower) <= p.s.existing_hydropower.number_of_turbines * m[:binTurbineOrPump][ts] )
		
		@constraint(m, [ts in p.time_steps], sum(m[:binPumpingWaterActive][t,ts] for t in p.techs.existing_hydropower) <= p.s.existing_hydropower.number_of_pumps * (1 - m[:binTurbineOrPump][ts]))
		
		# Each pump must meet the minimum water flow requirement, if it is on
		@constraint(m, [t in p.techs.existing_hydropower, ts in p.time_steps], 
						m[:dvPumpedWaterFlow][t, ts] >= m[:binPumpingWaterActive][t,ts]*p.s.existing_hydropower.minimum_water_output_cubic_meter_per_second_per_turbine    # TODO: change input value to "minimum water flow cubic meter per second per turbine"
							)
							
		# The electric power input into each pump must be below the pump's electric power rating
		@constraint(m, [t in p.techs.existing_hydropower, ts in p.time_steps], 
						m[:dvPumpPowerInput][t, ts] <= m[:binPumpingWaterActive][t,ts] * p.s.existing_hydropower.existing_kw_per_pump
					)
					
		if p.s.existing_hydropower.computation_type == "average_power_conversion"
			
			# Conversion between pumped water flow rate and power input into the pump
			@constraint(m, [t in p.techs.existing_hydropower, ts in p.time_steps], 
						m[:dvPumpedWaterFlow][t, ts] == m[:dvPumpPowerInput][t, ts] * p.s.existing_hydropower.water_pump_average_cubic_meters_per_second_per_kw )

		else
			throw(@error("A downstream reservoir is only compatible with average_power_conversion at the moment"))
		end
		
	else
		# If pumped water is not allowed, then binAnyTurbineActive is always 1 (meaning that the turbines can always operate)
			# This constraint shouldn't be needed
		#@constraint(m, [ts in p.time_steps], binAnyTurbineActive[ts] == 1)
		
		@info("Preventing use of the water pump variables because there is no downstream reservoir")
		for t in p.techs.existing_hydropower
			for ts in p.time_steps
				fix(m[:dvPumpedWaterFlow][t, ts], 0.0, force=true)
				fix(m[:dvPumpPowerInput][t, ts], 0.0, force=true)
			end
		end				
	end

	# Create an array of binary variable names for turbine or turbine and pumps
	dvs = []
	if p.s.existing_hydropower.model_downstream_reservoir
		dvs = ["binTurbineActive","binPumpingWaterActive"]
	else
		dvs = ["binTurbineActive"]
	end


	# Define the minimum operating time (in time steps) for the hydropower turbine
	if p.s.existing_hydropower.minimum_operating_time_steps_individual_turbine > 1
		print("\n Adding minimum operating time constraint \n")
		@variable(m, indicator_min_operating_time[t in p.techs.existing_hydropower, ts in p.time_steps, dv in dvs], Bin)
		for dv in dvs
			for t in p.techs.existing_hydropower, ts in 1:Int(length(p.time_steps)- p.s.existing_hydropower.minimum_operating_time_steps_individual_turbine - 1 )
				@constraint(m, m[:indicator_min_operating_time][t, ts, dv] =>  { sum(m[Symbol(dv)][t,ts+i] for i in 1:p.s.existing_hydropower.minimum_operating_time_steps_individual_turbine) >= p.s.existing_hydropower.minimum_operating_time_steps_individual_turbine} ) 
				@constraint(m, !m[:indicator_min_operating_time][t, ts, dv] => { m[Symbol(dv)][t,ts+1] - m[Symbol(dv)][t,ts] <= 0  } )
			end
		end
	end
	
	# Define the minimum operating time for the maximum water flow (in time steps) for a hydropower turbine
	if p.s.existing_hydropower.minimum_operating_time_steps_at_local_maximum_turbine_output > 1
		print("\n Adding a constraint for the minimum operating time at a local maximum water flow \n")
		@variable(m, indicator_turn_down[t in p.techs.existing_hydropower, ts in p.time_steps, dv in dvs], Bin)	
		for dv in dvs
			if dv == "binTurbineActive"
				variable = Symbol("dvWaterOutFlow")
			elseif dv == "binPumpingWaterActive"
				variable = Symbol("dvPumpedWaterFlow")
			else
				throw(@error("Error in applying the local maximum operating time constraint"))
			end
			for t in p.techs.existing_hydropower, ts in (2 + p.s.existing_hydropower.minimum_operating_time_steps_at_local_maximum_turbine_output):Int(length(p.time_steps))
				for i in 1:p.s.existing_hydropower.minimum_operating_time_steps_at_local_maximum_turbine_output
					@constraint(m, m[:indicator_turn_down][t, ts, dv] => {m[variable][t, ts-i] == m[variable][t,ts-i-1]})
				end
				@constraint(m, !m[:indicator_turn_down][t, ts, dv] => { m[variable][t,ts] >= m[variable][t,ts-1]  })
			end
		end
	end

	if p.s.existing_hydropower.minimum_turbine_off_time_steps > 1
		print("\n Adding minimum off duration for the turbines \n")
		@variable(m, indicator_turbine_turn_off[t in p.techs.existing_hydropower, ts in p.time_steps], Bin)
		for t in p.techs.existing_hydropower, ts in 1:Int(length(p.time_steps)- p.s.existing_hydropower.minimum_turbine_off_time_steps - 1 )
			@constraint(m, m[:indicator_turbine_turn_off][t, ts] =>  { sum(m[:binTurbineActive][t,ts+i] for i in 1:p.s.existing_hydropower.minimum_turbine_off_time_steps) <= 0 } ) 
			@constraint(m, !m[:indicator_turbine_turn_off][t, ts] => { m[:binTurbineActive][t,ts+1] - m[:binTurbineActive][t,ts] >= 0  } )
		end
	end
	
	# TODO: remove this constraint, which prevents a spike in the spillway use during the first time step
	@constraint(m, [ts in p.time_steps], m[:dvSpillwayWaterFlow][1] == 0)

end

