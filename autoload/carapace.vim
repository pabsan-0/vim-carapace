let s:carapace_binary = get(g:, 'carapace_binary', 'carapace')
let s:carapace_binary_available = executable(s:carapace_binary)
let s:carapace_binary_warned = false

if empty($CARAPACE_BRIDGES)
    let $CARAPACE_BRIDGES = get(g:, 'carapace_bridges', 'zsh,fish,bash')
endif


function! s:FindWordStart(line) abort
    let start = col('.') - 1
    while start > 0 && a:line[start - 1] =~ '\S'
        let start -= 1
    endwhile
    return start
endfunction


function! s:CollectCommandLines(linenum, base) abort
    let lines = []  " List of lines in multiline \-escaped commands, oldest first

    let current_line = getline(a:linenum)
    let start = s:FindWordStart(current_line)
    call insert(lines, current_line[:start - 1] . a:base)

    let prev = a:linenum - 1
    while prev > 0
        let text = getline(prev)
        if text !~ '\\\s*$'
            break
        endif
        call insert(lines, substitute(text, '\\\s*$', ' ', ''))
        let prev -= 1
    endwhile
    return lines
endfunction


function! s:ParseCommand(lines, base) abort
    let words = []   " List of all non-whitespace words
    let leaders = [] " List of indices for the first word of each line
    for line in a:lines
        let toks = split(line, '\s\+')
        if !empty(toks)
            call add(leaders, len(words))
            call extend(words, toks)
        endif
    endfor

    " Stub for the word being completed, if still empty
    if a:base ==# '' && !empty(words)
        call add(words, '')
    endif

    return [words, leaders]
endfunction


function! s:IsLeaderFullyTyped(leader_idx, words) abort
    " NOTE: true = the leader has arguments after it (it is not the word being completed).
    return a:leader_idx < len(a:words) - 1
endfunction


function! s:CompleteCommand(cmd) abort
    " Completion powered by vim
    let type = a:cmd =~# '/' ? 'file' : 'shellcmd'
    return map(sort(getcompletion(a:cmd, type)), {_, v -> {'word': v}})
endfunction


function! s:CompleteArgs(cmd, rest) abort
    let words = carapace#overrides#Apply(a:cmd, a:rest)
    return s:QueryCarapace(words[0], words)
endfunction


function! s:QueryCarapace(cmd, words) abort
    let args = [s:carapace_binary, a:cmd, 'export'] + a:words
    let output = system(join(map(copy(args), 'shellescape(v:val)'), ' '))

    try
        let json = json_decode(output)
    catch
        return []
    endtry

    let result = []
    if type(json) == v:t_dict && type(get(json, 'values', 0)) == v:t_list
        for item in json.values
            if get(item, 'value', '') == ''
                continue
            endif
            let comp = {'word': item.value}
            if get(item, 'display', '') != ''
                let comp['abbr'] = item.display
            endif
            if get(item, 'description', '') != ''
                let comp['menu'] = item.description
            endif
            call add(result, comp)
        endfor
    endif
    return result
endfunction


function! carapace#CarapaceComplete(findstart, base) abort
    if !get(g:, 'carapace_enabled', 1)
        return a:findstart ? -3 : v:none
    endif

    if !s:carapace_binary_available
        if !s:carapace_binary_warned
            echom "[carapace] Missing carapace binary. See README.md"
            let s:carapace_binary_warned = true
        endif
        return []
    endif

    if a:findstart
        return s:FindWordStart(getline('.'))
    endif
    let lines = s:CollectCommandLines(line('.'), a:base)
    let [words, leaders] = s:ParseCommand(lines, a:base)
    if empty(words)
        return v:none
    endif

    " Bounded fallback: if first word won't complete, attempt next line leader
    let budget = get(g:, 'carapace_leader_fallbacks', 2)
    for ii in leaders
        let cmd = words[ii]
        if cmd =~# '^-'
            continue  " Skip leading keyword arguments
        endif
        let result = s:IsLeaderFullyTyped(ii, words)
                    \ ? s:CompleteArgs(cmd, words[ii:])
                    \ : s:CompleteCommand(cmd)
        if !empty(result)
            return result
        endif

        let budget -= 1
        if budget < 0
            break
        endif
    endfor
    return v:none
endfunction
