vim9script

import autoload "./server.vim"
import autoload "./util.vim"

var g_format_delay = false

def GetLineByteFromPos(bnr: number, pos: dict<number>): number
    var col: number = pos.character
    # When on the first character, we can ignore the difference between byte and
    # character
    if col > 0
        # Need a loaded buffer to read the line and compute the offset
        if !bnr->bufloaded()
            bnr->bufload()
        endif

        var ltext: list<string> = bnr->getbufline(pos.line + 1)
        if !ltext->empty()
            var bidx = ltext[0]->byteidx(col)
            if bidx != -1
                return bidx
            endif
        endif
    endif
    return col
enddef

def SetLines(lines: list<string>, A: list<number>, B: list<number>, new_lines: list<string>): list<string>
    var i_0: number = A[0]

    # If it extends past the end, truncate it to the end. This is because the
    # way the LSP describes the range including the last newline is by
    # specifying a line number after what we would call the last line.
    var numlines: number = lines->len()
    var i_n = [B[0], numlines - 1]->min()

    if i_0 < 0 || i_0 >= numlines || i_n < 0 || i_n >= numlines
        var msg = "set_lines: Invalid range, A = " .. A->string()
        msg ..= ", B = " ..    B->string() .. ", numlines = " .. numlines
        msg ..= ", new lines = " .. new_lines->string()
        return lines
    endif

    # save the prefix and suffix text before doing the replacements
    var prefix: string = ''
    var suffix: string = lines[i_n][B[1] :]
    if A[1] > 0
        prefix = lines[i_0][0 : A[1] - 1]
    endif

    var new_lines_len: number = new_lines->len()

    var n: number = i_n - i_0 + 1
    if n != new_lines_len
        if n > new_lines_len
            # remove the deleted lines
            lines->remove(i_0, i_0 + n - new_lines_len - 1)
        else
            # add empty lines for newly the added lines (will be replaced with the
            # actual lines below)
            lines->extend(repeat([''], new_lines_len - n), i_0)
        endif
    endif

    # replace the previous lines with the new lines
    for i in range(new_lines_len)
        lines[i_0 + i] = new_lines[i]
    endfor

    # append the suffix (if any) to the last line
    if suffix != ''
        var i = i_0 + new_lines_len - 1
        lines[i] = lines[i] .. suffix
    endif

    # prepend the prefix (if any) to the first line
    if prefix != ''
        lines[i_0] = prefix .. lines[i_0]
    endif

    return lines
enddef

def Edit_sort_func(a: dict<any>, b: dict<any>): number
    if a.A[0] != b.A[0]
        return b.A[0] - a.A[0]
    endif
    if a.A[1] != b.A[1]
        return b.A[1] - a.A[1]
    endif
    return 0
enddef

def FormatCb(bnr: number, msg: dict<any>): void
    var text_edits = msg["result"]
    if text_edits->empty()
        return
    endif

    var orig_cursor_pos = getcurpos()
    # if the buffer is not loaded, load it and make it a listed buffer
    if !bnr->bufloaded()
        bnr->bufload()
    endif
    setbufvar(bnr, '&buflisted', true)

    var start_line: number = 4294967295
    var finish_line: number = -1
    var updated_edits: list<dict<any>> = []
    var start_row: number
    var start_col: number
    var end_row: number
    var end_col: number

    # create a list of buffer positions where the edits have to be applied.
    for e in text_edits
        # Adjust the start and end columns for multibyte characters
        start_row = e.range.start.line
        start_col = GetLineByteFromPos(bnr, e.range.start)
        end_row = e.range.end.line
        end_col = GetLineByteFromPos(bnr, e.range.end)
        start_line = [e.range.start.line, start_line]->min()
        finish_line = [e.range.end.line, finish_line]->max()
        updated_edits->add({A: [start_row, start_col], B: [end_row, end_col], lines: e.newText->split("\n", true)})
    endfor

    # Reverse sort the edit operations by descending line and column numbers so
    # that they can be applied without interfering with each other.
    updated_edits->sort(Edit_sort_func)

    var lines: list<string> = bnr->getbufline(start_line + 1, finish_line + 1)
    # This causes issues with haskell-language-server sometimes so just add lines without checking eol stuff
    # var fix_eol: bool = bnr->getbufvar('&fixeol')
    # var set_eol = fix_eol && bnr->getbufinfo()[0].linecount <= finish_line + 1
    # if set_eol && lines[-1]->len() != 0
    #     lines->add('')
    # endif
    if bnr->getbufinfo()[0].linecount <= finish_line + 1
        lines->add('')
    endif

    for e in updated_edits
        var A: list<number> = [e.A[0] - start_line, e.A[1]]
        var B: list<number> = [e.B[0] - start_line, e.B[1]]
        lines = SetLines(lines, A, B, e.lines)
    endfor

    # If the last line is empty and we need to set EOL, then remove it.
    # if set_eol && lines[-1]->len() == 0
    #     lines->remove(-1)
    # endif

    # Delete all the lines that need to be modified
    bnr->deletebufline(start_line + 1, finish_line + 1)

    # if the buffer is empty, appending lines before the first line adds an
    # extra empty line at the end. Delete the empty line after appending the
    # lines.
    var dellastline: bool = false
    if start_line == 0 && bnr->getbufinfo()[0].linecount == 1 && bnr->getbufline(1)[0] == ''
        dellastline = true
    endif

    # Append the updated lines
    appendbufline(bnr, start_line, lines)

    # This causes issues with haskell-language-server
    # if dellastline
    # bnr->deletebufline(bnr->getbufinfo()[0].linecount)
    # endif
    setpos('.', orig_cursor_pos)
enddef

def Reset_format_delay(arg: any): void
    g_format_delay = false
enddef

def FormatRequest(arg: any): void
    g_format_delay = true
    var params: dict<any>
    params = { 'textDocument': { 'uri': util.Uri() } }
    if exists('g:lsc_format_options')
        params['options'] = g:lsc_format_options
    endif
    server.UserRequest('textDocument/formatting', params, function(FormatCb, [bufnr('')]))
    timer_start(1000, Reset_format_delay)
enddef

export def Format(): void
    if g_format_delay
        timer_start(1000, FormatRequest)
    else
        FormatRequest(0)
    endif
enddef
