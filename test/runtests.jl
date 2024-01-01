using TestItems
using TestItemRunner
@run_package_tests


@testitem "_" begin
    import Aqua
    Aqua.test_all(DictArrays; ambiguities=false)
    Aqua.test_ambiguities(DictArrays)

    import CompatHelperLocal as CHL
    CHL.@check()
end
