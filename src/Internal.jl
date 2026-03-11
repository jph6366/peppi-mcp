module PeppiJlrs
using JlrsCore.Wrap
import peppi_jlrs_jll: libpeppi_jlrs_path

@wrapmodule(libpeppi_jlrs_path, :peppi_jlrs_init)

function __init__()
    @initjlrs
end

end
