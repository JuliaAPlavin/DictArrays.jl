module DictArrays

using Dictionaries
using Indexing: getindices
using StructArrays
using DataAPI: Cols
using ConstructionBase
using Accessors
using AccessorsExtra  # for Dictionaries support
using DataPipes
using Tables

export DictArray, Cols

Base.propertynames(d::D) where {D<:AbstractDictionary} = keys(d)
ConstructionBase.setproperties(obj::D, patch::NamedTuple) where {D<:AbstractDictionary} = merge(obj, Dictionary(keys(patch), values(patch)))
Base.@propagate_inbounds Base.getproperty(d::D, s::Symbol) where {D<:AbstractDictionary} = hasfield(D, s) ? getfield(d, s) : d[s]
Base.@propagate_inbounds function Base.setproperty!(d::D, s::Symbol, x) where {D<:AbstractDictionary}
    hasfield(D, s) && return setfield!(d, s, x)
    d[s] = x
    return x
end


struct DictArray
    dct::Dictionary{Symbol, <:AbstractVector}

    # so that we don't have DictArray(::Any) that gets overriden below
    function DictArray(dct::Dictionary{Symbol, <:AbstractVector})
        @assert allequal(map(axes, dct))
        new(dct)
    end
end

DictArray(d::AbstractDictionary) = @p let
    Dictionary(keys(d), values(d))
    map(convert(AbstractVector, _))
    @aside @assert __ isa Dictionary{Symbol, <:AbstractVector}
    DictArray()
end
DictArray(d::Union{AbstractDict,NamedTuple}) = DictArray(Dictionary(keys(d), values(d)))
DictArray(; kwargs...) = DictArray(values(kwargs))
DictArray(tbl) = @p let
    tbl
    Tables.dictcolumntable()
    Dictionary(Tables.columnnames(__), Tables.columns(__))
    DictArray()
end

for f in (:isempty, :length, :size, :firstindex, :lastindex, :eachindex, :keys, :keytype)
    @eval Base.$f(da::DictArray) = $f(first(Dictionary(da)))
end
Base.valtype(::Type{<:DictArray}) = Dictionary{Symbol}
Base.valtype(::DictArray) = Dictionary{Symbol}
Base.eltype(::Type{<:DictArray}) = Dictionary{Symbol}
Base.getindex(da::DictArray, I::Integer...) = map(a -> a[I...], Dictionary(da))
Base.getindex(da::DictArray, I::AbstractVector{<:Integer}) = @modify(a -> a[I], Dictionary(da)[∗])
Base.view(da::DictArray, I::Integer...) = map(a -> view(a, I...), Dictionary(da))
Base.view(da::DictArray, I::AbstractVector{<:Integer}) = @modify(a -> view(a, I), Dictionary(da)[∗])
Base.first(da::DictArray) = map(first, Dictionary(da))
Base.last(da::DictArray) = map(last, Dictionary(da))
Base.values(da::DictArray) = da

Base.propertynames(da::DictArray) = collect(keys(Dictionary(da)))
Base.getproperty(da::DictArray, i::Symbol) = Dictionary(da)[i]
function Base.getindex(da::DictArray, i::Cols{<:Tuple{Vararg{Symbol}}})
    ckeys = i.cols
    cvals = getindices(Dictionary(da), ckeys)
    StructArray(NamedTuple{ckeys}(cvals))
end
Base.getindex(da::DictArray, i::Cols{<:Tuple{Tuple{Vararg{Symbol}}}}) = da[Cols(only(i.cols)...)]
Base.getindex(da::DictArray, i::Cols{<:Tuple{AbstractVector{Symbol}}}) = DictArray(getindices(Dictionary(da), Indices(only(i.cols))))
Base.getindex(da::DictArray, i::Cols) = error("Not supported")

Dictionaries.Dictionary(da::DictArray) = getfield(da, :dct)
Base.Dict(da::DictArray) = Dict(pairs(Dictionary(da)))
Base.NamedTuple(da::DictArray) = (; pairs(Dictionary(da))...)
StructArrays.StructArray(da::DictArray) = da[Cols(keys(Dictionary(da))...)]
Base.collect(da::DictArray) = map(i -> da[i], 1:length(da))

Base.:(==)(a::DictArray, b::DictArray) = Dictionary(a) == Dictionary(b)

Base.filter(f, da::DictArray) = da[map(f, da)]

function Base.map(f, da::DictArray)
    t = tracedkeys(first(da))
    fres = f(t)
    _map(f, da, Cols(_accessed(t)...))
end
    
function _map(f, da::DictArray, cols::Cols)
    try
        map(da[cols]) do r
            try
                f(r)
            catch e
                e isa ErrorException || rethrow()
                m = match(r"has no field (\w+)$", e.msg)
                isnothing(m) && rethrow()
                throw(_map(f, da, Cols(cols.cols..., Symbol(m.captures[1]))))
            end
        end
    catch e
        e isa Exception && rethrow()
        return e
    end
end


struct TracedKeys
    dct::Dictionary{Symbol, <:Any}
    accessed::Vector{Symbol}
end

tracedkeys(dct) = TracedKeys(dct, [])
_dct(t::TracedKeys) = getfield(t, :dct)
_accessed(t::TracedKeys) = unique(__accessed(t))
__accessed(t::TracedKeys) = getfield(t, :accessed)

Base.getproperty(t::TracedKeys, i::Symbol) = t[i]
function Base.getindex(t::TracedKeys, i::Symbol)
    push!(__accessed(t), i)
    _dct(t)[i]
end
function Base.getindex(t::TracedKeys, i::Tuple{Vararg{Symbol}})
    append!(__accessed(t), i)
    NamedTuple{i}(getindices(_dct(t), i))
end
Base.merge(nt::NamedTuple, t::TracedKeys) = merge(nt, t[Tuple(keys(_dct(t)))])


ConstructionBase.setproperties(da::DictArray, patch::NamedTuple) = 
    @modify(Dictionary(da)) do dct
        for (k, v) in pairs(patch)
            @reset dct[k] = v
        end
        dct
    end
Accessors.set(da::DictArray, ::Type{Dictionary}, val::Dictionary) = DictArray(val)
Accessors.delete(da::DictArray, ::PropertyLens{P}) where {P} = @delete Dictionary(da)[P]
Accessors.insert(da::DictArray, ::PropertyLens{P}, val) where {P} = @insert Dictionary(da)[P] = val
Accessors.mapproperties(f, da::DictArray) = @modify(f, Dictionary(da)[∗])

function Accessors.setindex(da::DictArray, val::Dictionary{Symbol}, I::Integer...)
    @assert keys(Dictionary(da)) == keys(val)
    @modify(Dictionary(da) |> keyed(∗)) do (k, col)
        @set col[I...] = val[k]
    end
end


Tables.istable(::Type{<:DictArray}) = true
Tables.columnaccess(::Type{<:DictArray}) = true
Tables.columns(da::DictArray) = da
Tables.schema(da::DictArray) = Tables.Schema(collect(keys(Dictionary(da))), collect(map(eltype, Dictionary(da))))

end
