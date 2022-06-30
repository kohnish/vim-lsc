vim9script

def Num_last_difference(old: list<any>, new: list<any>, offset: number): number
    var length_old = len(old)
    var length_new = len(new)
    var length = length_old
    if length_old > length_new
        length = length_new
    endif
    for i in range(length - 1) 
        if old[length_old - i + offset] != new[length_new - i + offset]
            return -1 * i
        endif
    endfor
    return -1 * length
enddef

def Num_first_difference(old: list<any>, new: list<any>, offset: number): number
    var length_old = len(old)
    var length_new = len(new)
    var length = length_old
    if length_old > length_new
        length = length_new
    endif
    for i in range(length - 1) 
        if old[i + offset] != new[i + offset]
            return i
        endif
    endfor
    return length - 1
enddef

def FirstDifference(old: list<any>, new: list<any>): list<any>
    var line_count = min([len(old), len(new)])
    if line_count == 0 | return [0, 0] | endif
    var i = Num_first_difference(old, new, 0)

    if i >= line_count
      return [line_count - 1, strchars(old[line_count - 1])]
    endif

    var old_line = old[i]
    var new_line = new[i]
    var length = min([strchars(old_line), strchars(new_line)])
    var j = 0
    while j < length
        if strgetchar(old_line, j) != strgetchar(new_line, j)
            break
        endif
        j += 1
    endwhile
    return [i, j]
enddef

def LastDifference(old: list<any>, new: list<any>, start_char: number): list<any>
  var line_count = min([len(old), len(new)])
  if line_count == 0 | return [0, 0] | endif
  var i = Num_last_difference(old, new, -1)
  var old_line = ""
  var new_line = ""
  if i <= -1 * line_count
    i = -1 * line_count
    old_line = strcharpart(old[i], start_char)
    new_line = strcharpart(new[i], start_char)
  else
    old_line = old[i]
    new_line = new[i]
  endif
  var old_line_length = strchars(old_line)
  var new_line_length = strchars(new_line)
  var length = min([old_line_length, new_line_length])
  var j = -1
  while j >= -1 * length
    if strgetchar(old_line, old_line_length + j) != strgetchar(new_line, new_line_length + j)
      break
    endif
    j -= 1
  endwhile
  return [i, j]
enddef

def ExtractText(lines: list<any>, start_line: number, start_char: number, end_line: number, end_char: number): string
    if start_line == len(lines) + end_line
        if end_line == 0 | return '' | endif
        var line = lines[start_line]
        var length = strchars(line) + end_char - start_char + 1
        return strcharpart(line, start_char, length)
    endif

    var result = strcharpart(lines[start_line], start_char) .. "\n"
    for line in lines[start_line + 1 : end_line - 1]
        result = result .. line .. "\n"
    endfor
    if end_line != 0
        var line = lines[end_line]
        var length = strchars(line) + end_char + 1
        result = result .. strcharpart(line, 0, length)
    endif
    return result
enddef

def Length(lines: list<any>, start_line: number, start_char: number, end_line: number, end_char: number): number
    var adj_end_line = len(lines) + end_line
    var adj_end_char = 0
    if adj_end_line >= len(lines)
        adj_end_char = end_char - 1
    else
        adj_end_char = strchars(lines[adj_end_line]) + end_char
    endif
    if start_line == adj_end_line
        return adj_end_char - start_char + 1
    endif

    var result = strchars(lines[start_line]) - start_char + 1
    for line in range(start_line + 1, adj_end_line - 1)
        result += strchars(lines[line]) + 1
    endfor
    result += adj_end_char + 1
    return result
enddef

def Contents_diff(old: list<any>, new: list<any>): dict<any>
    var first_diff = FirstDifference(old, new)
    var start_line = first_diff[0]
    var start_char = first_diff[1]
    var end_diff = LastDifference(old[start_line : ], new[start_line : ], start_char)
    var end_line = end_diff[0]
    var end_char = end_diff[1]

    var text = ExtractText(new, start_line, start_char, end_line, end_char)
    var length = Length(old, start_line, start_char, end_line, end_char)

    var adj_end_line = len(old) + end_line
    var adj_end_char = end_line == 0 ? 0 : strchars(old[end_line]) + end_char + 1

    var result = { 
        'range': {
            'start': {'line': start_line, 'character': start_char},
            'end': {'line': adj_end_line, 'character': adj_end_char}
            },
        'text': text,
        'rangeLength': length
        }
  return result
enddef

def g:Vim9_lsc9_did_change_param(file_versions: dict<any>, file_path: string, file_content: dict<list<string>>, incremental: bool): dict<any>
    var document_params = {'textDocument': { 'uri': "file://" .. file_path, 'version': file_versions[file_path]}}

    var current_content = getbufline(bufnr(file_path), 1, '$')
    var params = {}
    if incremental
        var old_content = file_content[file_path]
        var change = Contents_diff(old_content, current_content)
        file_content[file_path] = current_content
        var incremental_params = copy(document_params)
        incremental_params.contentChanges = [change]
        params = incremental_params
    else
        var full_params = copy(document_params)
        var change = {'text': join(current_content, "\n") .. "\n"}
        full_params.contentChanges = [change]
        params = full_params
    endif
    return params
enddef
