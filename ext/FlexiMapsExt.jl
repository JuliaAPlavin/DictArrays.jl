module FlexiMapsExt

using FlexiMaps
using DictArrays
using DictArrays: Dictionary
using DictArrays.Accessors
using DictArrays.Accessors.CompositionsBase: compose, decompose

FlexiMaps.mapview(f::PropertyLens, da::DictArray) = f(da)
FlexiMaps.mapview(f::IndexLens{Tuple{Symbol}}, da::DictArray) = f(Dictionary(da))
function FlexiMaps.mapview(f::ComposedFunction, da::DictArray)
    fs = decompose(f)
    mapview(compose(Base.front(fs)...), mapview(last(fs), da))
end

FlexiMaps._similar_with_content_sameeltype(da::DictArray) = copy(da)

end
