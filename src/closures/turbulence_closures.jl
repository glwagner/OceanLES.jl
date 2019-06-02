module TurbulenceClosures

export
    TurbulenceClosure,
    IsotropicDiffusivity,
    TensorDiffusivity,

    MolecularDiffusivity,
    ConstantIsotropicDiffusivity,
    ConstantAnisotropicDiffusivity,
    ConstantSmagorinsky,
    AnisotropicMinimumDissipation,

    TurbulentDiffusivities,
    calculate_diffusivities!,

    ∇_κ_∇ϕ,
    ∇_κ_∇T,
    ∇_κ_∇S,
    ∂ⱼ_2ν_Σ₁ⱼ,
    ∂ⱼ_2ν_Σ₂ⱼ,
    ∂ⱼ_2ν_Σ₃ⱼ,

    ν₁₁, ν₂₂, ν₃₃,
    κ₁₁, κ₂₂, κ₃₃,

    ν_ccc,
    ν_ffc,
    ν_fcf,
    ν_cff,
    κ_ccc,

    ∂x_caa, ∂x_faa, ∂x²_caa, ∂x²_faa,
    ∂y_aca, ∂y_afa, ∂y²_aca, ∂y²_afa,
    ∂z_aac, ∂z_aaf, ∂z²_aac, ∂z²_aaf,

    ▶x_caa, ▶x_faa,
    ▶y_aca, ▶y_afa,
    ▶z_aac, ▶z_aaf,

    ▶xy_cca, ▶xz_cac, ▶yz_acc,
    ▶xy_cfa, ▶xz_caf, ▶yz_acf,
    ▶xy_fca, ▶xz_fac, ▶yz_afc,
    ▶xy_ffa, ▶xz_faf, ▶yz_aff

using
    Oceananigans,
    GPUifyLoops,
    Oceananigans.Operators

using Oceananigans.Operators: incmod1, decmod1

abstract type TurbulenceClosure{T} end
abstract type IsotropicDiffusivity{T} <: TurbulenceClosure{T} end
abstract type TensorDiffusivity{T} <: TurbulenceClosure{T} end

@inline ∇_κ_∇T(args...) = ∇_κ_∇ϕ(args...)
@inline ∇_κ_∇S(args...) = ∇_κ_∇ϕ(args...)

# Tensor transport coefficient simplifications
κ₁₁_ccc(i, j, k, grid, closure::IsotropicDiffusivity, args...) = κ_ccc(i, j, k, grid, closure, args...)
κ₂₂_ccc(i, j, k, grid, closure::IsotropicDiffusivity, args...) = κ_ccc(i, j, k, grid, closure, args...)
κ₃₃_ccc(i, j, k, grid, closure::IsotropicDiffusivity, args...) = κ_ccc(i, j, k, grid, closure, args...)

ν₁₁_ccc(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_ccc(i, j, k, grid, closure, args...)
ν₂₂_ccc(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_ccc(i, j, k, grid, closure, args...)
ν₃₃_ccc(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_ccc(i, j, k, grid, closure, args...)

ν₁₁_ffc(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_ffc(i, j, k, grid, closure, args...)
ν₂₂_ffc(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_ffc(i, j, k, grid, closure, args...)
ν₃₃_ffc(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_ffc(i, j, k, grid, closure, args...)

ν₁₁_fcf(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_fcf(i, j, k, grid, closure, args...)
ν₂₂_fcf(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_fcf(i, j, k, grid, closure, args...)
ν₃₃_fcf(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_fcf(i, j, k, grid, closure, args...)

ν₁₁_cff(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_cff(i, j, k, grid, closure, args...)
ν₂₂_cff(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_cff(i, j, k, grid, closure, args...)
ν₃₃_cff(i, j, k, grid, closure::IsotropicDiffusivity, args...) = ν_cff(i, j, k, grid, closure, args...)

geo_mean_Δ(grid::RegularCartesianGrid{T}) where T = (grid.Δx * grid.Δy * grid.Δz)^T(1/3)

function typed_keyword_constructor(T, Closure; kwargs...)
    closure = Closure(; kwargs...)
    names = fieldnames(Closure)
    vals = [convert(T, getproperty(closure, name)) for name in names]
    return Closure{T}(vals...)
end

Base.eltype(::TurbulenceClosure{T}) where T = T

include("closure_operators.jl")
include("velocity_gradients.jl")
include("constant_diffusivity_closures.jl")
include("constant_smagorinsky.jl")
include("anisotropic_minimum_dissipation.jl")

# Packaged operators
ν₁₁ = (ccc=ν₁₁_ccc, ffc=ν₁₁_ffc, fcf=ν₁₁_fcf, cff=ν₁₁_cff)
ν₂₂ = (ccc=ν₂₂_ccc, ffc=ν₂₂_ffc, fcf=ν₂₂_fcf, cff=ν₂₂_cff)
ν₃₃ = (ccc=ν₃₃_ccc, ffc=ν₃₃_ffc, fcf=ν₃₃_fcf, cff=ν₃₃_cff)

κ₁₁ = (ccc=κ₁₁_ccc, )
κ₂₂ = (ccc=κ₂₂_ccc, )
κ₃₃ = (ccc=κ₃₃_ccc, )

TurbulentDiffusivities(arch::Architecture, grid::Grid, args...) = nothing

end # module
