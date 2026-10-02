function! s:_MatchesToken(token, pattern) abort
    " Whole-token match; '\C\v' = case-sensitive very-magic.
    return matchstr(a:token, '\C\v' . a:pattern) ==# a:token
endfunction

function! s:DropTokens(args, rule) abort
    let pattern = a:rule[1]
    let out = []
    for token in a:args
        if !s:_MatchesToken(token, pattern)
            call add(out, token)
        endif
    endfor
    return out
endfunction

function! s:DropTokensWithValue(args, rule) abort
    let pattern = a:rule[1]
    let out = []
    let skip = 0
    for token in a:args
        if skip
            let skip = 0
            continue
        endif
        if s:_MatchesToken(token, pattern)
            let skip = 1
        else
            call add(out, token)
        endif
    endfor
    return out
endfunction

function! s:DropTokensFrom(args, rule) abort
    let pattern = a:rule[1]
    let out = []
    for token in a:args
        if s:_MatchesToken(token, pattern)
            break
        endif
        call add(out, token)
    endfor
    return out
endfunction

function! s:ReplaceTokens(args, rule) abort
    let pattern = a:rule[1]
    let replacement = a:rule[2]
    let out = []
    for token in a:args
        call add(out, s:_MatchesToken(token, pattern) ? replacement : token)
    endfor
    return out
endfunction

function! s:InsertTokenAfter(args, rule) abort
    let pattern = a:rule[1]
    let token_to_add = a:rule[2]
    let out = []
    let inserted = 0
    for token in a:args
        call add(out, token)
        if !inserted && s:_MatchesToken(token, pattern)
            call add(out, token_to_add)
            let inserted = 1
        endif
    endfor
    return out
endfunction

function! s:KeepFirstTokens(args, rule) abort
    let n = a:rule[1]
    return n <= 0 ? [] : a:args[:n - 1]
endfunction

let s:overrides = {
    \ 'Drop':          function('s:DropTokens'),
    \ 'DropWithValue': function('s:DropTokensWithValue'),
    \ 'DropFrom':      function('s:DropTokensFrom'),
    \ 'Replace':       function('s:ReplaceTokens'),
    \ 'InsertAfter':   function('s:InsertTokenAfter'),
    \ 'KeepFirst':     function('s:KeepFirstTokens'),
    \ }

function! s:ApplyRule(args, rule) abort
    if type(a:rule) != v:t_list || len(a:rule) < 2 || !has_key(s:overrides, a:rule[0])
        return a:args
    endif
    try
        return s:overrides[a:rule[0]](a:args, a:rule)
    catch
        " Skip malformed rule/patterns so a vimrc typo can't abort completion
        " TODO print err
        echom "[carapace] Malformed override: " .. a:rule
        return a:args
    endtry
endfunction

function! carapace#overrides#Apply(cmd, words) abort
    let key = fnamemodify(a:cmd, ':t')
    let rules = get(g:, 'carapace_overrides', {})
    if len(a:words) < 2 || !has_key(rules, key)
        return a:words
    endif
    " NOTE: [:-2] keeps the command (rules may rewrite it) and excludes the word
    " being completed (last); DropFrom etc. therefore keep that current word.
    let body = a:words[:-2]
    for rule in rules[key]
        let body = s:ApplyRule(body, rule)
    endfor
    if empty(body)
        return a:words
    endif
    return body + [a:words[-1]]
endfunction
