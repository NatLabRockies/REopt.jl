# CHP Expansion Project - Merge Order Analysis

## Executive Summary

This document provides a recommended merge order for the 6 CHP (Combined Heat and Power) expansion pull requests to minimize merge conflicts. The PRs range from 3 to 585 additions and modify critical CHP constraint files.

## Pull Request Overview

| PR # | Title | Files Changed | Lines Added | Lines Deleted | Status |
|------|-------|---------------|-------------|---------------|--------|
| 552 | Off-grid CHP | 8 | 187 | 14 | Draft, Mergeable |
| 553 | Multiple CHPs | 20 | 585 | 379 | Draft, Mergeable |
| 554 | CHP Independent Thermal | 7 | 823 | 2 | Draft, Mergeable |
| 555 | CHP Production Factor Input | 3 | 67 | 0 | Draft, Mergeable |
| 556 | Avoid CHP Binaries When Not Needed | 2 | 259 | 40 | Draft, Mergeable |
| 557 | CHP Ramp Rate Limitation Option | 6 | 257 | 1 | Draft, Mergeable |

## File Conflict Analysis

### Critical Files Modified by Multiple PRs

#### 1. `src/core/chp.jl` (Modified by ALL 6 PRs)
**Conflict Severity: HIGH**
- **PR 552**: Adds `operating_reserve_required_fraction` field
- **PR 553**: Adds `name` and `fuel_cost_escalation_rate_fraction` fields, adds `get_chp_by_name()` function
- **PR 554**: Adds 3 fields (`can_produce_thermal_independently`, `min_thermal_kw`, `max_thermal_kw`)
- **PR 555**: Adds `production_factor_series` field
- **PR 556**: No structural changes (only uses existing fields)
- **PR 557**: Adds `ramp_rate_fraction_per_hour` field

**Analysis**: All field additions are independent and can be combined without logic conflicts. The order matters only for clean diffs.

#### 2. `src/constraints/chp_constraints.jl` (Modified by PRs 553, 554, 556, 557)
**Conflict Severity: CRITICAL**
- **PR 553**: Major refactor - loops through each CHP, uses `p.chp_params[t]` instead of `p.s.chp`
- **PR 554**: Adds 2 new constraint functions for independent thermal mode
- **PR 556**: Refactors constraint structure, makes binary creation conditional
- **PR 557**: Adds ramp rate constraint function

**Analysis**: PR 553 fundamentally changes the structure from single CHP to multiple CHPs. This MUST be merged first as it affects how all other PRs reference CHP data.

#### 3. `src/core/reopt_inputs.jl` (Modified by PRs 553, 554)
**Conflict Severity: MEDIUM**
- **PR 553**: Major changes to `setup_chp_inputs()`, adds `chp_params` dict
- **PR 554**: Only uses existing structure (no conflicts if 553 goes first)

#### 4. `src/core/scenario.jl` (Modified by PRs 552, 553)
**Conflict Severity: MEDIUM**
- **PR 552**: Passes `off_grid_flag` to CHP constructor
- **PR 553**: Changes `chp::Union{CHP, Nothing}` to `chps::Array{CHP, 1}`

**Analysis**: PR 553's array change is fundamental. Must merge before 552.

#### 5. `src/results/chp.jl` (Modified by PRs 553, 554, 557)
**Conflict Severity: MEDIUM**
- **PR 553**: Major refactor to support multiple CHPs
- **PR 554**: Adds new result fields for thermal capacity
- **PR 557**: Adds curtailment tracking

**Analysis**: PR 553 changes the fundamental structure. Must merge first.

## Recommended Merge Order

### Phase 1: Foundation - Multiple CHP Infrastructure
**1. PR 553 - Multiple CHPs** (FIRST - Foundation for all others)
- **Rationale**: This PR fundamentally restructures how CHP is handled throughout the codebase, changing from a single CHP object to an array of CHPs. Every other PR assumes either single or multiple CHP structure. Merging this first establishes the new architecture.
- **Impact**: 20 files changed, 585 additions, 379 deletions
- **Conflicts**: Will conflict with all other PRs, but these are the easiest to resolve if merged first
- **Dependencies**: None (works on current `develop` branch)
- **Post-merge actions**: Other PRs will need updates to use `p.s.chps[1]` instead of `p.s.chp` and `p.chp_params[t]` instead of direct parameter access

### Phase 2: Core CHP Features  
**2. PR 554 - CHP Independent Thermal** (Second - Independent capability)
- **Rationale**: Adds significant new capability (independent thermal production) with minimal structural conflicts. After PR 553, this becomes a straightforward addition of new constraint functions.
- **Impact**: 7 files, 823 additions, 2 deletions
- **Conflicts**: Minimal after PR 553 is merged (mainly in `chp_constraints.jl`)
- **Dependencies**: Requires PR 553's multiple CHP structure
- **Post-merge actions**: Update to work with `chp_params[t]` accessor pattern

**3. PR 552 - Off-grid CHP** (Third - Off-grid support)
- **Rationale**: Adds operating reserve logic for off-grid scenarios. Clean addition of new constraints with minimal overlap with PR 554.
- **Impact**: 8 files, 187 additions, 14 deletions
- **Conflicts**: Minor in `chp.jl` (field additions) and `operating_reserve_constraints.jl`
- **Dependencies**: Benefits from PR 553's infrastructure
- **Post-merge actions**: Update to work with array-based CHP structure from PR 553

### Phase 3: Operational Improvements
**4. PR 555 - CHP Production Factor Input** (Fourth - Small, focused addition)
- **Rationale**: Smallest PR with the narrowest scope. Only adds one field and updates one function. Very low conflict risk.
- **Impact**: 3 files, 67 additions, 0 deletions
- **Conflicts**: Minimal (just field addition in `chp.jl`)
- **Dependencies**: Works with any previous structure
- **Post-merge actions**: Trivial updates for multiple CHP if needed

**5. PR 556 - Avoid CHP Binaries When Not Needed** (Fifth - Optimization)
- **Rationale**: Refactors constraint creation logic to conditionally create binaries. Should be merged after core features (552, 554) are in place to ensure binary logic works with all new constraint types.
- **Impact**: 2 files, 259 additions, 40 deletions
- **Conflicts**: Medium in `chp_constraints.jl` (refactors function signatures)
- **Dependencies**: Should come after PRs 552 and 554 to ensure binary logic handles operating reserves and independent thermal
- **Post-merge actions**: Verify binary creation logic works with all constraint types from earlier PRs

**6. PR 557 - CHP Ramp Rate Limitation** (Last - Additional constraint)
- **Rationale**: Adds ramp rate constraints as a new, independent feature. Should be last as it adds to the constraint structure that all previous PRs have established.
- **Impact**: 6 files, 257 additions, 1 deletion
- **Conflicts**: Minor (adds new constraint function, field in `chp.jl`, results tracking)
- **Dependencies**: Benefits from all previous PRs being in place
- **Post-merge actions**: Minimal - mainly ensuring it works with multiple CHP and binary optimization from PR 556

## Detailed Merge Strategy

### Step 1: Merge PR 553 (Multiple CHPs)
**Pre-merge checklist:**
- [ ] All tests passing on PR 553
- [ ] Review changes to ensure no breaking changes for existing single-CHP scenarios
- [ ] Create backup branch of develop before merge

**Post-merge actions:**
1. Update PR 552, 554, 556, 557 to work with multiple CHP structure:
   - Change `p.s.chp` → `p.s.chps[1]` or loop through `p.s.chps`
   - Change direct parameter access → `p.chp_params[t][:parameter_name]`
   - Update test scenarios as needed

2. Run all CHP-related tests to ensure backward compatibility

### Step 2: Merge PR 554 (Independent Thermal)
**Pre-merge checklist:**
- [ ] PR 554 rebased on latest develop (includes PR 553)
- [ ] Conflicts in `chp_constraints.jl` resolved
- [ ] Tests updated for multiple CHP structure
- [ ] Verify independent thermal constraints work with multiple CHPs

**Post-merge actions:**
1. Update PR 556 to ensure binary creation logic includes independent thermal constraints
2. Update PR 557 ramp constraints to work with independent thermal mode

### Step 3: Merge PR 552 (Off-grid CHP)
**Pre-merge checklist:**
- [ ] PR 552 rebased on latest develop (includes PRs 553, 554)
- [ ] Update to work with `chps` array and `chp_params`
- [ ] Tests passing with multiple CHP infrastructure
- [ ] Operating reserve logic verified

**Post-merge actions:**
1. Update PR 556 to ensure binary logic includes operating reserve constraints
2. Verify PR 557 ramp rate works in off-grid scenarios

### Step 4: Merge PR 555 (Production Factor)
**Pre-merge checklist:**
- [ ] PR 555 rebased on latest develop
- [ ] Field added to correct location in CHP struct
- [ ] Production factor logic works with multiple CHPs

**Post-merge actions:**
1. Verify production factor series interacts correctly with binary optimization (PR 556)

### Step 5: Merge PR 556 (Binary Optimization)
**Pre-merge checklist:**
- [ ] PR 556 rebased on latest develop (includes all previous PRs)
- [ ] Binary creation logic updated to check:
   - Operating reserve intercepts (from PR 552)
   - Independent thermal intercepts (from PR 554)  
   - Production factor effects (from PR 555)
- [ ] All tests passing with conditional binary creation
- [ ] Performance improvement verified

**Post-merge actions:**
1. Update PR 557 to work with conditional binary creation

### Step 6: Merge PR 557 (Ramp Rate)
**Pre-merge checklist:**
- [ ] PR 557 rebased on latest develop (includes all previous PRs)
- [ ] Ramp rate constraints work with:
   - Multiple CHPs (PR 553)
   - Independent thermal mode (PR 554)
   - Off-grid scenarios (PR 552)
   - Conditional binary creation (PR 556)
- [ ] All tests passing

**Post-merge actions:**
1. Final integration testing with all CHP features enabled
2. Update documentation with all new CHP capabilities

## Conflict Resolution Guidelines

### For `src/core/chp.jl` field additions:
```julia
# All PRs add fields - combine them in order:
Base.@kwdef mutable struct CHP <: AbstractCHP
    # Existing fields...
    
    # From PR 552:
    operating_reserve_required_fraction::Real = 0.0
    
    # From PR 553:
    name::String = "CHP"
    fuel_cost_escalation_rate_fraction::Union{Nothing, Float64} = nothing
    
    # From PR 554:
    can_produce_thermal_independently::Bool = false
    min_thermal_kw::Float64 = 0.0
    max_thermal_kw::Float64 = NaN
    
    # From PR 555:
    production_factor_series::Union{Nothing, Vector{<:Real}} = nothing
    
    # From PR 557:
    ramp_rate_fraction_per_hour::Float64 = 1.0
    
    # Rest of fields...
end
```

### For `src/constraints/chp_constraints.jl`:
1. **PR 553 first**: Establishes loop structure `for t in p.techs.chp`
2. **PR 554 second**: Adds independent thermal functions (called conditionally)
3. **PR 556 third**: Wraps constraint calls in conditional checks
4. **PR 557 last**: Adds ramp rate function (called conditionally)

## Risk Assessment

| Phase | Risk Level | Mitigation |
|-------|-----------|------------|
| Phase 1 (PR 553) | HIGH | Extensive testing, staged deployment |
| Phase 2 (PRs 554, 552) | MEDIUM | Careful conflict resolution in constraint files |
| Phase 3 (PRs 555, 556, 557) | LOW | Independent features, minimal overlap |

## Timeline Estimate

Assuming one PR merged and validated per day:
- **Day 1**: Merge PR 553, update other PRs
- **Day 2**: Merge PR 554
- **Day 3**: Merge PR 552  
- **Day 4**: Merge PR 555
- **Day 5**: Merge PR 556
- **Day 6**: Merge PR 557
- **Day 7**: Final integration testing

**Total: ~1-2 weeks** (includes buffer for issue resolution)

## Alternative Approaches Considered

### Option A: Merge smallest PRs first (555, 552, 557, 556, 554, 553)
**Rejected because**: PR 553 changes fundamental architecture. Merging it last would require extensive rework of all previously merged PRs.

### Option B: Merge feature PRs in parallel tracks
**Rejected because**: Too many files overlap, would create merge hell.

### Option C: Combine all PRs into one mega-PR
**Rejected because**: Loses granularity, harder to review, harder to isolate issues.

## Success Criteria

- [ ] All 6 PRs successfully merged to develop branch
- [ ] All existing tests pass
- [ ] All new tests pass
- [ ] No regression in existing CHP functionality
- [ ] Documentation updated with new features
- [ ] Performance benchmarks show improvement (from PR 556)

## Conclusion

The recommended merge order prioritizes:
1. **Infrastructure first** (PR 553) - Foundation for everything else
2. **Core features** (PRs 554, 552) - Major capabilities
3. **Operational improvements** (PRs 555, 556, 557) - Enhancements and optimizations

This order minimizes conflicts, maintains logical feature groupings, and reduces the number of times each PR needs to be rebased.

## Questions or Issues?

Contact the development team or comment on the PRs for clarification.

---

**Document created**: December 29, 2024  
**Author**: GitHub Copilot Coding Agent  
**Status**: Ready for review
