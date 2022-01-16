"""
    IMAGEMIME

Union of MIME image types.
Based on Pluto.PlutoRunner.imagemimes.
"""
const IMAGEMIME = Union{
    MIME"image/svg+xml",
    MIME"image/png",
    MIME"image/jpg",
    MIME"image/jpeg",
    MIME"image/bmp",
    MIME"image/gif"
}

"""
    HTMLOptions(;
        code_class::AbstractString="language-julia",
        output_class::AbstractString="code-output",
        output_pre_class::AbstractString="documenter-example-output",
        hide_code::Bool=false,
        hide_md_code::Bool=true,
        add_state::Bool=true,
        append_build_context::Bool=false,
        compiler_options::Union{Nothing,CompilerOptions}=nothing
    )

Options for `notebook2html`:

- `code_class`:
    HTML class for code.
    This is used by CSS and/or the syntax highlighter.
` `output_pre_class`:
    HTML class for `<pre>`.
- `output_class`:
    HTML class for output.
    This is used by CSS and/or the syntax highlighter.
- `hide_code`:
    Whether to omit all code blocks.
    Can be useful when readers are not interested in code at all.
- `hide_md_code`:
    Whether to omit all Markdown code blocks.
- `add_state`:
    Whether to add a comment in HTML with the state of the input notebook.
    This state can be used for caching.
    Specifically, this state stores a checksum of the input notebook and the Julia version.
- `append_build_context`:
    Whether to append build context.
    When set to `true`, this adds information about the dependencies and Julia version.
    This is not executed via Pluto.jl's evaluation to avoid having to add extra dependencies to existing notebooks.
    Instead, this reads the manifest from the notebook file.
- `compiler_options`:
    `Pluto.Configuration.CompilerOptions` to be passed to Pluto.
    This can, for example, be useful to pass custom system images from `PackageCompiler.jl`.
"""
struct HTMLOptions
    code_class::String
    output_pre_class::String
    output_class::String
    hide_code::Bool
    hide_md_code::Bool
    add_state::Bool
    append_build_context::Bool
    compiler_options::Union{Nothing,CompilerOptions}

    function HTMLOptions(;
        code_class::AbstractString="language-julia",
        output_pre_class::AbstractString="documenter-example-output",
        output_class::AbstractString="code-output",
        hide_code::Bool=false,
        hide_md_code::Bool=true,
        add_state::Bool=true,
        append_build_context::Bool=false,
        compiler_options::Union{Nothing,CompilerOptions}=nothing
    )
        return new(
            string(code_class)::String,
            string(output_pre_class)::String,
            string(output_class)::String,
            hide_code,
            hide_md_code,
            add_state,
            append_build_context,
            compiler_options
        )
    end
end

"""
    _escape_html(s::AbstractString)

Escape HTML.
Useful for showing HTML inside code blocks, see
https://github.com/rikhuijzer/PlutoStaticHTML.jl/issues/9.
"""
function _escape_html(s::AbstractString)
    s = replace(s, '<' => "&lt;")
    s = replace(s, '>' => "&gt;")
    return s
end

function code_block(code; code_class="language-julia")
    if code == ""
        return ""
    end
    code = _escape_html(code)
    return """<pre><code class="$code_class">$code</code></pre>"""
end

function output_block(s; class="code-output", pre_class="pre_class")
    if s == ""
        return ""
    end
    return """<pre class=$pre_class><code class="$class">$s</code></pre>"""
end

function _code2html(code::AbstractString, hopts::HTMLOptions)
    if hopts.hide_code
        return ""
    end
    if hopts.hide_md_code && startswith(code, "md\"")
        return ""
    end
    if contains(code, "# hideall")
        return ""
    end
    sep = '\n'
    lines = split(code, sep)
    filter!(!endswith("# hide"), lines)
    code = join(lines, sep)
    return code_block(code; hopts.code_class)
end

function _output2html(body, T::IMAGEMIME, hopts)
    encoded = base64encode(body)
    uri = "data:$T;base64,$encoded"
    return """<img src="$uri">"""
end

function _output2html(body, ::MIME"application/vnd.pluto.stacktrace+object", hopts)
    return error(body)
end

function _tr_wrap(elements::Vector)
    joined = join(elements, '\n')
    return "<tr>\n$joined\n</tr>"
end
_tr_wrap(::Array{String, 0}) = "<tr>\n<td>...</td>\n</tr>"

function _output2html(body::Dict{Symbol,Any}, ::MIME"application/vnd.pluto.table+object", hopts)
    rows = body[:rows]
    nms = body[:schema][:names]
    headers = _tr_wrap(["<th>$colname</th>" for colname in nms])
    contents = map(rows) do row
        # Drop index.
        row = row[2:end]
        # Unpack the type and throw away mime info.
        elements = try
            first.(only(row))
        catch
            first.(first.(row))
        end
        elements = ["<td>$e</td>" for e in elements]
        return _tr_wrap(elements)
    end
    content = join(contents, '\n')
    return """
        <table>
        $headers
        $content
        </table>
        """
end

abstract type Struct end

function symbol2type(s::Symbol)
    if s == :Tuple
        return Tuple
    elseif s == :Array
        return Array
    elseif s == :struct
        return Struct
    else
        @warn "Missing type: $s"
        return Missing
    end
end

"""
    _clean_tree(parent, element::Tuple{Any, Tuple{String, MIME}}, T)

Drop metadata.
For example, `(1, ("\"text\"", MIME type text/plain))` becomes "text".
"""
function _clean_tree(parent, element::Tuple{Any, Tuple{String, MIME}}, T)
    return first(last(element))
end

function _clean_tree(parent, element::Tuple{Any, Any}, T)
    embedded = first(last(element))
    if embedded isa String
        return embedded
    end
    struct_name = embedded[:prefix]
    elements = embedded[:elements]
    subelements = [_clean_tree(parent, e, Nothing) for e in elements]
    joined = join(subelements, ", ")
    return struct_name * '(' * joined * ')'
end

function _clean_tree(parent, elements::Tuple{Any, Tuple}, T)
    body = first(last(elements))
    T = symbol2type(body[:type])
    return _clean_tree(body, body[:elements], T)
end

function _clean_tree(parent, elements::AbstractVector, T::Type{Tuple})
    cleaned = [_clean_tree(parent, e, Nothing) for e in elements]
    joined = join(cleaned, ", ")
    return "($joined)"
end

function _clean_tree(parent, elements::AbstractVector, T::Type{Array})
    cleaned = [_clean_tree(parent, e, Nothing) for e in elements]
    joined = join(cleaned, ", ")
    return "[$joined]"
end

function _clean_tree(parent, elements::AbstractVector, T::Type{Struct})
    cleaned = [_clean_tree(parent, e, Nothing) for e in elements]
    joined = join(cleaned, ", ")
    return parent[:prefix] * '(' * joined * ')'
end

# Fallback. This shouldn't happen. Convert to string to avoid failure.
function _clean_tree(parent, elements, T)
    @warn "Couldn't convert $parent"
    return string(elements)::String
end

function _output2html(body::Dict{Symbol,Any}, ::MIME"application/vnd.pluto.tree+object", hopts)
    T = symbol2type(body[:type])
    cleaned = _clean_tree(body, body[:elements], T)
    pre_class = hopts.output_pre_class
    class = hopts.output_class
    return output_block(cleaned; class, pre_class)
end

_output2html(body, ::MIME"text/plain", hopts) = output_block(body)
_output2html(body, ::MIME"text/html", hopts) = body
_output2html(body, T::MIME, hopts) = error("Unknown type: $T")

function _cell2html(cell::Cell, hopts::HTMLOptions)
    code = _code2html(cell.code, hopts)
    output = _output2html(cell.output.body, cell.output.mime, hopts)
    return """
        $code
        $output
        """
end

"""
    _append_cell!(notebook::Notebook, cell::Cell)

Add one `cell` to the end of the `notebook`.
This is based on `add_remote_cell` in Pluto's `Editor.js`.
"""
function _append_cell!(notebook::Notebook, cell::Cell)
    push!(notebook.cell_order, cell.cell_id)
    notebook.cells_dict[cell.cell_id] = cell
    return notebook
end

function _append_cell!(notebook::Notebook, cells::AbstractVector{Cell})
    foreach(c -> _append_cell!(notebook, c), cells)
    return notebook
end

"""
    run_notebook!(nb::Notebook, session)

Run all cells in `nb`.
Throws an error as soon as a cell fails.
"""
function run_notebook!(nb::Notebook, session)
    cells = [nb.cells_dict[cell_uuid] for cell_uuid in nb.cell_order]
    for cell in cells
        update_save_run!(session, nb, cell; run_async=false, save=false)
        if cell.errored
            body = cell.output.body
            msg = body[:msg]
            stacktrace = body[:stacktrace]
            msg = """
                $msg

                Details:
                $stacktrace
                """
            error(msg)
        end
    end
    return nothing
end

const BEGIN_IDENTIFIER = "<!-- PlutoStaticHTML.Begin -->"
const END_IDENTIFIER = "<!-- PlutoStaticHTML.End -->"

isready(nb::Notebook) = nb.process_status == "ready"

"""
    notebook2html(nb::Notebook, path, opts::HTMLOptions=HTMLOptions()) -> String

Return the code and output as HTML for `nb`.
Assumes that the notebook has already been executed.
"""
function notebook2html(nb::Notebook, path, opts::HTMLOptions=HTMLOptions())::String
    @assert isready(nb)
    order = nb.cell_order
    outputs = map(order) do cell_uuid
        cell = nb.cells_dict[cell_uuid]
        _cell2html(cell, opts)
    end
    html = join(outputs, '\n')
    if opts.add_state && !isnothing(path)
        html = string(path2state(path)) * html
    end
    if opts.append_build_context
        html = html * _context(nb)
    end
    html = string(BEGIN_IDENTIFIER, '\n', html, '\n', END_IDENTIFIER)::String
    return html
end

const TMP_COPY_PREFIX = "_tmp_"

"""
    _tmp_copy(path::AbstractString)

Return the path of a temp copy of the file at `path`.
This avoids Pluto making changes to the original notebook.
"""
function _tmp_copy(path::AbstractString)::String
    dir = dirname(path)
    file = basename(path)
    tmp_path = joinpath(dir, TMP_COPY_PREFIX * file)
    cp(path, tmp_path; force=true)
    return tmp_path
end

"""
    _load_notebook(
        path::AbstractString,
        compiler_options::Union{Nothing,CompilerOptions}=nothing
    ) -> Notebook

Return the notebook at `path` while ensuring that the file at `path` will not be modified.
This method only loads the notebook; it doesn't evaluate cells.
"""
function _load_notebook(
        path::AbstractString;
        compiler_options::Union{Nothing,CompilerOptions}=nothing
    )::Notebook
    tmp_path = _tmp_copy(path)
    nb = load_notebook_nobackup(tmp_path)
    nb.compiler_options = compiler_options
    return nb
end

"""
    notebook2html(
        path::AbstractString,
        opts::HTMLOptions=HTMLOptions();
        session=ServerSession(),
        append_cells=Cell[],
    ) -> String

Run the Pluto notebook at `path` and return the code and output as HTML.
This makes a copy of the notebook at `path` and runs it.

Keyword arguments:

- `append_cells`: Specify one or more `Pluto.Cell`s to be appended at the end of the notebook.
    Be careful when adding new packages via this method because it may disable Pluto.jl's built-in package management.
"""
function notebook2html(
        path::AbstractString,
        opts::HTMLOptions=HTMLOptions();
        session=ServerSession(),
        append_cells=Cell[],
    )::String
    nb = _load_notebook(path)
    PlutoStaticHTML._append_cell!(nb, append_cells)
    run_notebook!(nb, session)
    html = notebook2html(nb, path, opts)
    return html
end
