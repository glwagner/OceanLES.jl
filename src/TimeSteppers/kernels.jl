#####
##### Navier-Stokes and tracer advection equations
#####

""" Store previous value of the source term and calculate current source term. """
function calculate_interior_source_terms!(G, arch, grid, coriolis, buoyancy, surface_waves, closure, U, C, pHY′, K, F, parameters, time)
    # Manually choose thread-block layout here as it's ~20% faster.
    # See: https://github.com/climate-machine/Oceananigans.jl/pull/308
    Tx, Ty = 16, 16 # CUDA threads per block
    Bx, By, Bz = floor(Int, grid.Nx/Tx), floor(Int, grid.Ny/Ty), grid.Nz  # Blocks in grid

    @launch(device(arch), threads=(Tx, Ty), blocks=(Bx, By, Bz),
            calculate_Gu!(G.u, grid, coriolis, surface_waves, closure, U, C, K, F, pHY′, parameters, time))

    @launch(device(arch), threads=(Tx, Ty), blocks=(Bx, By, Bz),
            calculate_Gv!(G.v, grid, coriolis, surface_waves, closure, U, C, K, F, pHY′, parameters, time))

    @launch(device(arch), threads=(Tx, Ty), blocks=(Bx, By, Bz),
            calculate_Gw!(G.w, grid, coriolis, surface_waves, closure, U, C, K, F, parameters, time))

    for tracer_index in 1:length(C)
        @inbounds Gc = G[tracer_index+3]
        @inbounds Fc = F[tracer_index+3]
        @inbounds  c = C[tracer_index]

        @launch(device(arch), threads=(Tx, Ty), blocks=(Bx, By, Bz),
                calculate_Gc!(Gc, grid, c, Val(tracer_index), closure, buoyancy, U, C, K, Fc, parameters, time))
    end

    return nothing
end

""" Calculate the right-hand-side of the u-momentum equation. """
function calculate_Gu!(Gu, grid, coriolis, surface_waves, closure, U, C, K, F, pHY′, parameters, time)
    @loop_xyz i j k grid begin
        @inbounds Gu[i, j, k] = ( - div_ũu(i, j, k, grid, U)
                                  - x_f_cross_U(i, j, k, grid, coriolis, U)
                                  - ∂xᶠᵃᵃ(i, j, k, grid, pHY′)
                                  + ∂ⱼ_2ν_Σ₁ⱼ(i, j, k, grid, closure, U, K)
                                  + x_curl_Uˢ_cross_U(i, j, k, grid, surface_waves, U, time)
                                  + ∂t_uˢ(i, j, k, grid, surface_waves, time)
                                  + F.u(i, j, k, grid, time, U, C, parameters))
    end
    return nothing
end

""" Calculate the right-hand-side of the v-momentum equation. """
function calculate_Gv!(Gv, grid, coriolis, surface_waves, closure, U, C, K, F, pHY′, parameters, time)
    @loop_xyz i j k grid begin
        @inbounds Gv[i, j, k] = ( - div_ũv(i, j, k, grid, U)
                                  - y_f_cross_U(i, j, k, grid, coriolis, U)
                                  - ∂yᵃᶠᵃ(i, j, k, grid, pHY′)
                                  + ∂ⱼ_2ν_Σ₂ⱼ(i, j, k, grid, closure, U, K)
                                  + y_curl_Uˢ_cross_U(i, j, k, grid, surface_waves, U, time)
                                  + ∂t_vˢ(i, j, k, grid, surface_waves, time)
                                  + F.v(i, j, k, grid, time, U, C, parameters))
    end
    return nothing
end

""" Calculate the right-hand-side of the w-momentum equation. """
function calculate_Gw!(Gw, grid, coriolis, surface_waves, closure, U, C, K, F, parameters, time)
    @loop_xyz i j k grid begin
        @inbounds Gw[i, j, k] = ( - div_ũw(i, j, k, grid, U)
                                  - z_f_cross_U(i, j, k, grid, coriolis, U)
                                  + ∂ⱼ_2ν_Σ₃ⱼ(i, j, k, grid, closure, U, K)
                                  + z_curl_Uˢ_cross_U(i, j, k, grid, surface_waves, U, time)
                                  + ∂t_wˢ(i, j, k, grid, surface_waves, time)
                                  + F.w(i, j, k, grid, time, U, C, parameters))
    end
    return nothing
end

""" Calculate the right-hand-side of the tracer advection-diffusion equation. """
function calculate_Gc!(Gc, grid, c, tracer_index, closure, buoyancy, U, C, K, Fc, parameters, time)
    @loop_xyz i j k grid begin
        @inbounds Gc[i, j, k] = (- div_uc(i, j, k, grid, U, c)
                                 + ∇_κ_∇c(i, j, k, grid, closure, c, tracer_index, K, C, buoyancy)
                                 + Fc(i, j, k, grid, time, U, C, parameters))
    end
    return nothing
end

""" Apply boundary conditions by adding flux divergences to the right-hand-side. """
function calculate_boundary_source_terms!(Gⁿ, bcs, arch, grid, args...)

    # Velocity fields
    for i in 1:3
        ubcs = bcs[i]
        apply_z_bcs!(Gⁿ[i], arch, grid, ubcs.z.bottom, ubcs.z.top,   args...)
        apply_y_bcs!(Gⁿ[i], arch, grid, ubcs.y.left,   ubcs.y.right, args...)
    end

    # Tracer fields
    for i in 4:length(bcs)
        cbcs = bcs[i]
        apply_z_bcs!(Gⁿ[i], arch, grid, cbcs.z.bottom, cbcs.z.top,   args...)
        apply_y_bcs!(Gⁿ[i], arch, grid, cbcs.y.left,   cbcs.y.right, args...)
    end

    return nothing
end

"""
Update the horizontal velocities u and v via

    `u^{n+1} = u^n + (Gu^{n+½} - δₓp_{NH} / Δx) Δt`
"""
function update_velocities!(U, grid, Δt, G, pNHS)
    @loop_xyz i j k grid begin
        @inbounds U.u[i, j, k] += (G.u[i, j, k] - ∂xᶠᵃᵃ(i, j, k, grid, pNHS)) * Δt
        @inbounds U.v[i, j, k] += (G.v[i, j, k] - ∂yᵃᶠᵃ(i, j, k, grid, pNHS)) * Δt
        @inbounds U.w[i, j, k] += (G.w[i, j, k] - ∂zᵃᵃᶠ(i, j, k, grid, pNHS)) * Δt
    end
    return nothing
end

"""
Update the horizontal velocities u and v via

    `u^{n+1} = u^n + Gu^{n+½} / Δt`
"""
function update_hydrostatic_velocities!(U, grid, Δt, G)
    @loop_xyz i j k grid begin
        @inbounds U.u[i, j, k] += G.u[i, j, k] * Δt
        @inbounds U.v[i, j, k] += G.v[i, j, k] * Δt
    end
    return nothing
end

"""
Update a tracer field via

    `c^{n+1} = c^n + Gc^{n+½} Δt`
"""
function update_tracer!(c, grid, Δt, Gc)
    @loop_xyz i j k grid begin
        @inbounds c[i, j, k] += Gc[i, j, k] * Δt
    end
    return nothing
end

"Update all tracer fields."
function update_tracers!(C, arch, grid, Δt, G)
    for i in 1:length(C)
        @inbounds c = C[i]
        @inbounds Gc = G[i+3]
        @launch device(arch) config=launch_config(grid, :xyz) update_tracer!(c, grid, Δt, Gc)
    end
    return nothing
end

"Update the solution variables (velocities and tracers) for non-hydrostatic problems."
function update_solution!(U, C, arch, grid, Δt, G, pNHS)
    @launch device(arch) config=launch_config(grid, :xyz) update_velocities!(U, grid, Δt, G, pNHS)
    update_tracers!(C, arch, grid, Δt, G)
    return nothing
end

"Update the solution variables (velocities and tracers) for hydrostatic problems."
function update_solution!(U, C, arch, grid, Δt, G, ::Nothing)
    @launch device(arch) config=launch_config(grid, :xyz) update_hydrostatic_velocities!(U, grid, Δt, G)
    @launch device(arch) config=launch_config(grid, :xy) _compute_w_from_continuity!(U, grid)
    update_tracers!(C, arch, grid, Δt, G)
    return nothing
end

#####
##### Vertical integrals
#####

"""
Update the hydrostatic pressure perturbation pHY′. This is done by integrating
the `buoyancy_perturbation` downwards:

    `pHY′ = ∫ buoyancy_perturbation dz` from `z=0` down to `z=-Lz`
"""
function update_hydrostatic_pressure!(pHY′, grid, buoyancy, C)
    @loop_xy i j grid begin
        @inbounds pHY′[i, j, grid.Nz] = - ℑzᵃᵃᶠ(i, j, grid.Nz, grid, buoyancy_perturbation, buoyancy, C) * ΔzF(i, j, grid.Nz, grid)
        @unroll for k in grid.Nz-1 : -1 : 1
            @inbounds pHY′[i, j, k] =
                pHY′[i, j, k+1] - ℑzᵃᵃᶠ(i, j, k+1, grid, buoyancy_perturbation, buoyancy, C) * ΔzF(i, j, k, grid)
        end
    end
    return nothing
end

"""
Compute the vertical velocity w by integrating the continuity equation from the bottom upwards

    `w^{n+1} = -∫ [∂/∂x (u^{n+1}) + ∂/∂y (v^{n+1})] dz`
"""
function compute_w_from_continuity!(model)
    @launch(device(model.architecture), config=launch_config(model.grid, :xy),
            _compute_w_from_continuity!(datatuple(model.velocities), model.grid))
    return nothing
end

function _compute_w_from_continuity!(U, grid)
    @loop_xy i j grid begin
        # U.w[i, j, 1] = 0 is enforced via halo regions.
        @unroll for k in 2:grid.Nz
            @inbounds U.w[i, j, k] = U.w[i, j, k-1] - ΔzC(i, j, k, grid) * hdivᶜᶜᵃ(i, j, k-1, grid, U.u, U.v)
        end
    end
    return nothing
end
