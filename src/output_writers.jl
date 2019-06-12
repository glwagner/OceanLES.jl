"Return the filename extension for the `OutputWriter` filetype."
ext(fw::OutputWriter) = throw("Not implemented.")

function filename(fw, name, iteration)
    if fw.naming_scheme == :iteration
        fw.filename_prefix * name * lpad(iteration, fw.padding, "0") * ext(fw)
    elseif fw.naming_scheme == :file_number
        file_num = Int(iteration / fw.output_frequency)
        fw.filename_prefix * name * lpad(file_num, fw.padding, "0") * ext(fw)
    else
        throw(ArgumentError("Invalid naming scheme: $(fw.naming_scheme)"))
    end
end

mutable struct JLD2OutputWriter{O, I} <: OutputWriter
        filepath :: String
         outputs :: O
        interval :: I
        previous :: Float64
    asynchronous :: Bool
end

function savesubstruct!(file, model, name, flds=propertynames(getproperty(model, name)))
    for fld in flds
        file["$name/$fld"] = getproperty(getproperty(model, name), fld)
    end
    return nothing
end

noinit(args...) = nothing

function JLD2OutputWriter(model, outputs; dir=".", prefix="", interval=1, init=noinit, force=false,
                          asynchronous=false)

    mkpath(dir)
    filepath = joinpath(dir, prefix*".jld2")
    force && isfile(filepath) && rm(filepath, force=true)

    jldopen(filepath, "a+") do file
        init(file, model)
        savesubstruct!(file, model, :grid)
        savesubstruct!(file, model, :eos)
        savesubstruct!(file, model, :constants)
        savesubstruct!(file, model, :closure)
    end

    return JLD2OutputWriter(filepath, outputs, interval, 0.0, asynchronous)
end

function write_output(model, fw::JLD2OutputWriter)
    @info @sprintf("Calculating JLD2 output %s...", keys(fw.outputs))
    @time data = Dict((name, f(model)) for (name, f) in fw.outputs)

    iter = model.clock.iteration
    time = model.clock.time
    path = fw.filepath

    @info @sprintf("Writing JLD2 output %s...", keys(fw.outputs))
    t0 = time_ns()
    if fw.asynchronous
        @async remotecall(jld2output!, 2, path, iter, time, data)
    else
        jld2output!(path, iter, time, data)
    end
    @info "Done writing (t: $(prettytime(time_ns()-t0)))"

    return nothing
end

function jld2output!(path, iter, time, data)
    jldopen(path, "r+") do file
        file["timeseries/t/$iter"] = time
        for (name, datum) in data
            file["timeseries/$name/$iter"] = datum
        end
    end
    return nothing
end

struct HorizontalAverages{A}
    U :: A
    V :: A
    T :: A
    S :: A
end

function HorizontalAverages(arch::CPU, grid::Grid{FT}) where FT
    U = zeros(FT, 1, 1, grid.Tz)
    V = zeros(FT, 1, 1, grid.Tz)
    T = zeros(FT, 1, 1, grid.Tz)
    S = zeros(FT, 1, 1, grid.Tz)

    HorizontalAverages(U, V, T, S)
end

function HorizontalAverages(arch::GPU, grid::Grid{FT}) where FT
    U = CuArray{FT}(undef, 1, 1, grid.Tz)
    V = CuArray{FT}(undef, 1, 1, grid.Tz)
    T = CuArray{FT}(undef, 1, 1, grid.Tz)
    S = CuArray{FT}(undef, 1, 1, grid.Tz)

    HorizontalAverages(U, V, T, S)
end

HorizontalAverages(model) = HorizontalAverages(model.arch, model.grid)


struct VerticalPlanes{A}
    U :: A
    V :: A
    T :: A
    S :: A
end

function VerticalPlanes(arch::CPU, grid::Grid{FT}) where FT
    U = zeros(FT, grid.Tx, 1, grid.Tz)
    V = zeros(FT, grid.Tx, 1, grid.Tz)
    T = zeros(FT, grid.Tx, 1, grid.Tz)
    S = zeros(FT, grid.Tx, 1, grid.Tz)

    VerticalPlanes(U, V, T, S)
end

function VerticalPlanes(arch::GPU, grid::Grid{FT}) where FT
    U = CuArray{FT}(undef, grid.Tx, 1, grid.Tz)
    V = CuArray{FT}(undef, grid.Tx, 1, grid.Tz)
    T = CuArray{FT}(undef, grid.Tx, 1, grid.Tz)
    S = CuArray{FT}(undef, grid.Tx, 1, grid.Tz)

    VerticalPlanes(U, V, T, S)
end

VerticalPlanes(model) = VerticalPlanes(model.arch, model.grid)

