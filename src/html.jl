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

function code_block(code; class="language-julia")
    if code == ""
        return ""
    end
    return """<pre><code class="$class">$code</code></pre>"""
end

function output_block(s; class="code-output")
    if s == ""
        return ""
    end
    return """<pre><code class="$class">$s</code></pre>"""
end

function _code2html(code::AbstractString, class)
    if contains(code, "# hideall")
        return ""
    end
    return code_block(code; class)
end

function _output2html(body, T::IMAGEMIME, class)
    encoded = base64encode(body)
    uri = "data:$T;base64,$encoded"
    return """<img src="$uri">"""
end

function _output2html(body, ::MIME"application/vnd.pluto.stacktrace+object", class)
    return error(body)
end

function _tr_wrap(elements::Vector)
    joined = join(elements, '\n')
    return "<tr>$joined</tr>"
end

function _output2html(body::Dict{Symbol,Any}, ::MIME"application/vnd.pluto.table+object", class)
    rows = body[:rows]
    nms = body[:schema][:names]
    headers = _tr_wrap(["<th>$colname</th>" for colname in nms])
    contents = map(rows) do row
        # Drop index.
        row = row[2:end]
        # Unpack the type and throw away mime info.
        elements = first.(only(row))
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

_output2html(body, ::MIME"text/plain", class) = output_block(body)
_output2html(body, ::MIME"text/html", class) = body
_output2html(body, T::MIME, class) = error("Unknown type: $T")

function _cell2html(cell::Cell, code_class, output_class)
    code = _code2html(cell.code, code_class)
    output = _output2html(cell.output.body, cell.output.mime, output_class)
    return """
        $code
        $output
        """
end

"""
    notebook2html(
        notebook::Notebook;
        session=ServerSession(),
        code_class="language-julia",
        output_class="code-output"
    )

Run the `notebook` and return the code and output as HTML.
"""
function notebook2html(
        notebook::Notebook;
        session=ServerSession(),
        code_class="language-julia",
        output_class="code-output"
    )
    cells = [last(e) for e in notebook.cells_dict]
    update_run!(session, notebook, cells)
    order = notebook.cell_order
    outputs = map(order) do cell_uuid
        cell = notebook.cells_dict[cell_uuid]
        _cell2html(cell, code_class, output_class)
    end
    return join(outputs, '\n')
end

"""
    notebook2html(path::AbstractString)

Run the Pluto notebook at `path` and return the code and output as HTML.
"""
function notebook2html(path::AbstractString)
    notebook = load_notebook_nobackup(path)
    return notebook2html(notebook)
end
