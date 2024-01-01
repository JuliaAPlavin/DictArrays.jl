module DictArrays

using Dictionaries
using Indexing: getindices
using StructArrays
using DataAPI: Cols
using ConstructionBase
using CompositionsBase: compose, decompose
using Accessors
using DataPipes
using Tables
using FlexiMaps
using UnionCollections: any_element

export DictArray, Cols


struct DictArray{DT<:AbstractDictionary{Symbol}}
    dct::DT

    # so that we don't have DictArray(::Any) that gets overriden below
    function DictArray(dct::AbstractDictionary{Symbol})
        @assert all(isequal(axes(any_element(dct))) ∘ axes, dct)
        new{typeof(dct)}(dct)
    end
end

DictArray(d::AbstractDictionary) = @p let
    d
    map(convert(AbstractArray, _))
    @aside @assert __ isa AbstractDictionary{Symbol}
    DictArray()
end
DictArray(d::AbstractDict) = DictArray(Dictionary(keys(d), values(d)))
DictArray(d::NamedTuple) = DictArray(Dictionary(keys(d), values(d)))
DictArray(; kwargs...) = DictArray(values(kwargs))
DictArray(tbl) = @p let
    tbl
    Tables.dictcolumntable()
    Dictionary(Tables.columnnames(__), Tables.columns(__))
    DictArray()
end

for f in (:isempty, :length, :size, :firstindex, :lastindex, :eachindex, :keys, :keytype)
    @eval Base.$f(da::DictArray) = $f(any_element(AbstractDictionary(da)))
end
Base.axes(da::DictArray, args...) = axes(any_element(AbstractDictionary(da)), args...)
Base.ndims(da::DictArray) = ndims(any_element(AbstractDictionary(da)))
Base.IndexStyle(da::DictArray) = IndexStyle(any_element(AbstractDictionary(da)))
Base.valtype(::Type{<:DictArray}) = AbstractDictionary{Symbol}
Base.valtype(::DictArray) = AbstractDictionary{Symbol}
Base.eltype(::Type{<:DictArray}) = AbstractDictionary{Symbol}
Base.@propagate_inbounds function Base.getindex(da::DictArray, I::Union{Integer,CartesianIndex}...)
    @boundscheck checkbounds(da, I...)
    map(a -> @inbounds(a[I...]), AbstractDictionary(da))
end
Base.@propagate_inbounds function Base.getindex(da::DictArray, I::AbstractVector{<:Integer})
    @boundscheck checkbounds(da, I)
    @modify(dct -> map(a -> @inbounds(a[I]), dct), AbstractDictionary(da))
end
Base.@propagate_inbounds function Base.view(da::DictArray, I)
    @boundscheck checkbounds(da, I)
    @modify(dct -> map(a -> @inbounds(view(a, I)), dct), AbstractDictionary(da))
end

Base.checkbounds(::Type{Bool}, da::DictArray, I...) = checkbounds(Bool, any_element(AbstractDictionary(da)), I...)
Base.checkbounds(da::DictArray, I...) = checkbounds(any_element(AbstractDictionary(da)), I...)
Base.only(da::DictArray) = map(only, AbstractDictionary(da))
Base.first(da::DictArray) = map(first, AbstractDictionary(da))
Base.last(da::DictArray) = map(last, AbstractDictionary(da))
Base.values(da::DictArray) = da

Base.similar(da::DictArray, ::Type{T}) where {T} = similar(Array{T}, axes(da))
Base.similar(da::DictArray, ::Type{<:Union{NamedTuple,AbstractDict,AbstractDictionary}}) = error("Reserved: what exactly this should mean?")
Base.copy(da::DictArray) = @modify(copy, AbstractDictionary(da) |> Elements())

function Base.append!(a::DictArray, b::DictArray)
    @assert propertynames(a) == propertynames(b)
    for k in propertynames(a)
        append!(AbstractDictionary(a)[k], AbstractDictionary(b)[k])
    end
    return a
end

Base.iterate(::DictArray) = error("Iteration deliberately not supported to avoid triggering fallbacks that perform poorly for type-unstable DictArrays.")

Base.propertynames(da::DictArray) = collect(keys(AbstractDictionary(da)))
Base.getproperty(da::DictArray, i::Symbol) = getproperty(AbstractDictionary(da), i)
function Base.getindex(da::DictArray, i::Cols{<:Tuple{Vararg{Symbol}}})
    cspec = NamedTuple{i.cols}(i.cols)
    cols = getindices(AbstractDictionary(da), cspec)::NamedTuple
    StructArray(cols)
end
Base.getindex(da::DictArray, i::Cols{<:Tuple{Tuple{Vararg{Symbol}}}}) = da[Cols(only(i.cols)...)]
Base.getindex(da::DictArray, i::Cols{<:Tuple{AbstractVector{Symbol}}}) = 
    @modify(AbstractDictionary(da)) do dct
        getindices(dct, Indices(only(i.cols)))
    end
Base.getindex(da::DictArray, i::Cols) = error("Not supported")

Dictionaries.AbstractDictionary(da::DictArray) = getfield(da, :dct)
Base.Dict(da::DictArray) = Dict(pairs(AbstractDictionary(da)))
Base.NamedTuple(da::DictArray) = (; pairs(AbstractDictionary(da))...)
StructArrays.StructArray(da::DictArray) = da[Cols(keys(AbstractDictionary(da))...)]
Base.collect(da::DictArray)::AbstractArray{AbstractDictionary{Symbol}} = map(i -> da[i], keys(da))

Base.merge(da::DictArray, args::AbstractDictionary...) = DictArray(merge(AbstractDictionary(da), args...))
Base.merge(da::DictArray, args...) = merge(da, map(_dictionary, args)...)
_dictionary(x::AbstractDictionary) = x
_dictionary(x::DictArray) = AbstractDictionary(x)
_dictionary(x) = Dictionary(x)

Base.:(==)(a::DictArray, b::DictArray) = AbstractDictionary(a) == AbstractDictionary(b)

Base.filter(f, da::DictArray) = da[map(f, da)]

function Base.map(f, da::DictArray)
    t = tracedkeys(first(da))
    fres = f(t)
    _map(f, da, Cols(_accessed(t)...))
end
    
function _map(f, da::DictArray, cols::Cols)
    try
        map(f, da[cols])
    catch e
        e isa ErrorException || rethrow()
        m = match(r"has no field (\w+)$", e.msg)
        isnothing(m) && rethrow()
        return _map(f, da, Cols(cols.cols..., Symbol(m.captures[1])))
    end
end


struct TracedKeys
    dct::AbstractDictionary{Symbol, <:Any}
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


ConstructionBase.setproperties(da::DictArray, patch::NamedTuple) = merge(da, patch)
Accessors.set(da::DictArray, ::Type{AbstractDictionary}, val::AbstractDictionary) = DictArray(val)
Accessors.set(da::DictArray, ::Type{AbstractDictionary}, val) = error("Can only set AbstractDictionary(DictArray) to AbstractDictionary")
Accessors.delete(da::DictArray, ::PropertyLens{P}) where {P} = @delete AbstractDictionary(da)[P]
Accessors.insert(da::DictArray, ::PropertyLens{P}, val) where {P} = @insert AbstractDictionary(da)[P] = val
Accessors.mapproperties(f, da::DictArray) = @modify(f, AbstractDictionary(da) |> Elements())

function Accessors.setindex(da::DictArray, val::AbstractDictionary{Symbol}, I::Integer...)
    @assert keys(AbstractDictionary(da)) == keys(val)
    @modify(AbstractDictionary(da)) do cols
        map(cols, val) do col, v
            @set col[I...] = v
        end
    end
end


Tables.istable(::Type{<:DictArray}) = true
Tables.columnaccess(::Type{<:DictArray}) = true
Tables.columns(da::DictArray) = da
Tables.schema(da::DictArray) = Tables.Schema(collect(keys(AbstractDictionary(da))), collect(map(eltype, AbstractDictionary(da))))


## fast-path for map(), and support for mapview():

Base.map(f::PropertyLens, da::DictArray) = map(identity, f(da))
Base.map(f::IndexLens{Tuple{Symbol}}, da::DictArray) = map(identity, f(AbstractDictionary(da)))
function Base.map(f::ComposedFunction, da::DictArray)
    fs = decompose(f)
    map(compose(Base.front(fs)...), mapview(last(fs), da))
end

FlexiMaps.mapview(f::PropertyLens, da::DictArray) = f(da)
FlexiMaps.mapview(f::IndexLens{Tuple{Symbol}}, da::DictArray) = f(AbstractDictionary(da))
function FlexiMaps.mapview(f::ComposedFunction, da::DictArray)
    fs = decompose(f)
    mapview(compose(Base.front(fs)...), mapview(last(fs), da))
end

# for flatten() to work:
FlexiMaps._similar_with_content_sameeltype(da::DictArray) = copy(da)


# piracy, see PR:
# https://github.com/andyferris/Dictionaries.jl/pull/43
Base.propertynames(d::AbstractDictionary) = keys(d)
Base.@propagate_inbounds Base.getproperty(d::AbstractDictionary, s::Symbol) = hasfield(typeof(d), s) ? getfield(d, s) : d[s]
ConstructionBase.setproperties(obj::AbstractDictionary, patch::NamedTuple) = merge(obj, Dictionary(keys(patch), values(patch)))

end
