# `max_simple_payback_years` "maximize size" feature (`src/core/reopt.jl`)

> Dev notes — not yet wired into `docs/make.jl` nav, so this page isn't published to
> the doc site. Promote it (add to `make.jl`) once the design has settled.

## Design intent

Among solutions satisfying `simple_payback <= max_simple_payback_years`, push
toward the largest capacity/size, not just the cost-optimal size — capturing extra
value from generation/energy even when the incremental capex/opex isn't as
cost-effective as the smaller optimal size.

This is implemented as a two-stage lexicographic solve in `optimize_reopt!`:
1. Maximize `MaximizeSizeObjective` subject to the `max_simple_payback_years` constraint.
2. Lock that maximum (within a small tolerance) and minimize lifecycle cost (`Costs`)
   while holding it, so the specific tech mix chosen for that size is the cheapest one.

## Why size-based (`dvSize`/`dvStoragePower`), not production-based

- Chosen deliberately over incentivizing production (`dvRatedProduction`), after
  weighing pros/cons.
- Size-based avoids the degenerate case: bigger nameplate capacity with no more
  energy produced (pure added cost, no value).
- Production-based has the mirror-image risk for dispatchable/fuel-burning techs
  (Generator, CHP): the optimizer can satisfy a production incentive by just
  dispatching more during less cost-effective/uneconomical hours, without growing
  size at all — real fuel/O&M costs per kWh already compete against any artificial
  per-kWh incentive, so it either does nothing (incentive too weak) or distorts
  dispatch (incentive too strong) instead of reliably growing size.
- For intermittent techs (PV, Wind) size and production are ~proportional anyway,
  so the choice barely matters there; the divergence is specific to dispatchable
  techs, which is why size was generalized to work for `p.techs.maximize_size`
  (all techs except ExistingBoiler/ExistingChiller) plus storage power capacity.
- A possible future "maximize production" option/toggle was explicitly deferred as
  a separate feature — not implemented, no current plan to add it.

## `dvStorageEnergy` excluded from `MaximizeSizeObjective`

`MaximizeSizeObjective` sums `dvSize[t]` (`maximize_size` techs) plus
`dvStoragePower[b]` only — `dvStorageEnergy[b]` (kWh) is intentionally excluded.

`add_storage_size_constraints` ties energy to power via duration bounds:

```julia
dvStorageEnergy[b] <= dvStoragePower[b] * max_duration_hours
dvStorageEnergy[b] >= dvStoragePower[b] * min_duration_hours
```

If kWh were included in the stage-1 objective, stage 1 would push energy to the
duration ceiling "for free" (more objective units, no cost weighting), consuming
real capex against the payback budget and crowding out PV/battery-kW growth, even
when that duration wasn't economically justified.

With kWh excluded, stage 1 only maximizes nameplate power/capacity (consistent
across PV/Wind/CHP/battery-kW); stage 2 picks battery kWh/duration purely on
economics, bounded only by the existing min/max duration constraints. This applies
to all storage types in `p.s.storage.types.all` (elec/hot/cold), not just
`ElectricStorage`, for consistency, even though the duration-ratio constraint
itself only exists for `ElectricStorage`.

## Related: NPV>=0 vs simple-payback approach

- Old stale branch `NatLabRockies/REopt.jl@max_size_positive_npv` (604 commits
  behind master) implements a genuinely different, NPV-like mechanism:
  `Costs <= bau_lcc + MaximizeProductionIncentive` (full discounted LCC comparison,
  using `p.s.financial.bau_lcc`) combined with a production-based incentive
  (`ProductionByTech`, coefficient -10). This is the likely ancestor of the
  `MaximizeProductionIncentive` naming in current code.
- Current codebase uses `bau_year_one_operating_cost` + `max_simple_payback_years`
  (undiscounted single-year payback), which is a different/stricter criterion than
  full lifecycle NPV.
- NPV>=0 is intended to remain a SEPARATE, not-yet-implemented feature — do not
  conflate with the current payback-years-based maximize-size constraint.

## Known numerical gotcha (already fixed)

`Year1OperatingCost` (JuMP expression) vs externally-computed
`bau_year_one_operating_cost` (Float64) can differ by ~1e-7 floating point noise;
amplified by the `max_simple_payback_years` multiplier this can flip a
truly-feasible constraint to INFEASIBLE. Fixed via a `payback_tol` epsilon added
to the RHS of the payback constraint (see `reopt.jl` comments around
`PaybackSavings`/`payback_tol`).
