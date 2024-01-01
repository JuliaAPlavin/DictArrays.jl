module FlexiMapsExt

import FlexiMaps: mapview
using DictArrays
using DictArrays: Dictionary
using DictArrays.Accessors
using DictArrays.Accessors.CompositionsBase: compose, decompose

mapview(f::PropertyLens, da::DictArray) = f(da)
mapview(f::IndexLens{Tuple{Symbol}}, da::DictArray) = f(Dictionary(da))
function mapview(f::ComposedFunction, da::DictArray)
    fs = decompose(f)
    mapview(compose(Base.front(fs)...), mapview(last(fs), da))
end

end
