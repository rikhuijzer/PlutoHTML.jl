module PlutoStaticHTML

using Base64: base64encode
using Pkg:
    Types.Context,
    Types.UUID,
    Operations
using Pluto:
    Cell,
    CellOutput,
    Notebook,
    PkgCompat,
    PlutoRunner,
    ServerSession,
    SessionActions,
    WorkspaceManager,
    generate_html,
    load_notebook_nobackup,
    update_dependency_cache!,
    update_run!,
    update_save_run!

include("module_doc.jl")
include("context.jl")
include("html.jl")
include("build.jl")

export notebook2html, run_notebook!
export parallel_build!

end # module
