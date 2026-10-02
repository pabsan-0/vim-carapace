" vim-carapace test suite (run via: sh test/run.sh)
"
" Public behavior only: every completion case goes through the completefunc
" carapace#CarapaceComplete (findstart then complete); data-only rule ops go
" through carapace#overrides#Apply. Real carapace on $PATH, no stub.

let s:root     = $CARAPACE_TEST_ROOT
let s:scenario = $CARAPACE_TEST_SCENARIO
let s:bindir   = $CARAPACE_TEST_BINDIR
let s:data     = $CARAPACE_TEST_DATA
let s:rows     = []

execute 'set runtimepath+=' . fnameescape(s:root)
set virtualedit=onemore

if s:scenario ==# 'nobin'
    let g:carapace_binary = '/nonexistent/carapace'
elseif s:scenario ==# 'falsebin'
    let g:carapace_binary = $CARAPACE_TEST_FALSE
elseif s:scenario ==# 'bridges_custom'
    let g:carapace_bridges = 'zzz'
endif


" -- plumbing ---------------------------------------------------------------

function! s:given(extra) abort
    if has_key(a:extra, 'lines')
        return join(a:extra.lines, ' ')
    elseif has_key(a:extra, 'words')
        return join(a:extra.words, ' ')
    elseif has_key(a:extra, 'cmd')
        return a:extra.cmd
    endif
    return ''
endfunction

function! s:test(name, expected, actual, extra) abort
    let v:errors = []
    try
        call assert_equal(a:expected, a:actual)
    catch
        call add(v:errors, 'exception: ' . v:exception)
    endtry
    call add(s:rows, [s:scenario, empty(v:errors) ? 'Pass' : 'Fail', a:name,
                \ s:given(a:extra), string(a:expected), string(a:actual)])
endfunction

function! s:row(fields) abort
    return join(map(copy(a:fields), 'substitute(v:val, "\\t", " ", "g")'), "\t")
endfunction

" Drive the completefunc as Vim does. Returns [result, debug-context].
function! s:complete(lines, lnum) abort
    silent! %delete _
    call setline(1, a:lines)
    let line = a:lines[a:lnum - 1]
    call cursor(a:lnum, strlen(line) + 1)
    let start = carapace#CarapaceComplete(1, '')
    let base = (type(start) == v:t_number && start >= 0) ? line[start :] : ''
    let got = carapace#CarapaceComplete(0, base)
    return [got, {'lines': a:lines, 'lnum': a:lnum, 'start': start, 'base': base}]
endfunction

function! s:clear_rules() abort
    if exists('g:carapace_overrides') | unlet g:carapace_overrides | endif
endfunction

function! s:with_rules(rules, name, lines, lnum, fn, arg) abort
    let g:carapace_overrides = a:rules
    let [got, extra] = s:complete(a:lines, a:lnum)
    call s:test(a:name, 1, call(a:fn, [got, a:arg]), extend(extra, {'rules': a:rules}))
    call s:clear_rules()
endfunction

" result predicates
function! s:first(res, arg) abort
    return (type(a:res) == v:t_list && !empty(a:res)) ? (get(a:res[0], 'word', '') ==# a:arg) : 0
endfunction
function! s:has(res, arg) abort
    if type(a:res) != v:t_list | return 0 | endif
    for c in a:res | if get(c, 'word', '') ==# a:arg | return 1 | endif | endfor
    return 0
endfunction
function! s:excl(res, arg) abort
    return !s:has(a:res, a:arg)
endfunction
function! s:all(res, arg) abort
    if type(a:res) != v:t_list || empty(a:res) | return 0 | endif
    for c in a:res | if strpart(get(c, 'word', ''), 0, strlen(a:arg)) !=# a:arg | return 0 | endif | endfor
    return 1
endfunction
function! s:menu(res, arg) abort
    if type(a:res) != v:t_list | return 0 | endif
    for c in a:res | if get(c, 'menu', '') !=# '' | return 1 | endif | endfor
    return 0
endfunction

function! s:run_units(cases) abort
    for c in a:cases
        call s:clear_rules()
        if !empty(c[4]) | let g:carapace_overrides = c[4] | endif
        call s:test(c[0], c[3], carapace#overrides#Apply(c[1], c[2]),
                    \ {'cmd': c[1], 'words': c[2], 'rules': c[4]})
    endfor
    call s:clear_rules()
endfunction

function! s:run_exact(cases) abort
    for c in a:cases
        let [got, extra] = s:complete(c[1], c[2])
        call s:test(c[0], c[3], got, extra)
    endfor
endfunction

function! s:run_preds(cases) abort
    for c in a:cases
        let [got, extra] = s:complete(c[1], c[2])
        call s:test(c[0], 1, call(c[3], [got, c[4]]), extra)
    endfor
endfunction


" -- case tables ------------------------------------------------------------

let s:units = [
\ ['overrides: absent config is a no-op',   'git',              ['git', 'x'],                 ['git', 'x'],                 {}],
\ ['overrides: rule keyed by basename',     '/opt/tools/mycmd', ['/opt/tools/mycmd', 'x'],    ['mycmd', 'x'],               {'mycmd': [['Replace', '/opt/tools/mycmd', 'mycmd']]}],
\ ['overrides: Replace renames command',    'mycmd',            ['mycmd', 'x'],               ['real', 'x'],                {'mycmd': [['Replace', 'mycmd', 'real']]}],
\ ['overrides: single word untouched',      'git',              ['git'],                      ['git'],                      {}],
\ ['overrides: Drop whole token only',      'x',                ['x', '--gst-', '--gst-plugin-load'], ['x', '--gst-plugin-load'], {'x': [['Drop', '--gst-']]}],
\ ['overrides: Drop regex family',          'x',                ['x', '--gst-plugin-load', 'cur'],    ['x', 'cur'],                 {'x': [['Drop', '--gst-.*']]}],
\ ['overrides: \c case-insensitive',        'x',                ['x', '--DEBUG', 'cur'],      ['x', 'cur'],                 {'x': [['Drop', '\c--debug']]}],
\ ['overrides: current word untouched',     'git',              ['git', 'che'],               ['git', 'che'],               {'git': [['Drop', 'che']]}],
\ ['overrides: Drop',                       'x',                ['x', '-v', '-vv', '--keep'], ['x', '--keep'],              {'x': [['Drop', '-v+']]}],
\ ['overrides: DropWithValue',              'x',                ['x', '--config', 'val', '--keep'], ['x', '--keep'],        {'x': [['DropWithValue', '--config']]}],
\ ['overrides: DropFrom',                   'x',                ['x', 'sub', '--', 'tail'],   ['x', 'sub', 'tail'],         {'x': [['DropFrom', '--']]}],
\ ['overrides: InsertAfter',                'nix',              ['nix', 'build'],             ['nix', 'run', 'build'],      {'nix': [['InsertAfter', 'nix', 'run']]}],
\ ['overrides: KeepFirst',                  'x',                ['x', 'a', 'b', 'c'],         ['x', 'a', 'c'],              {'x': [['KeepFirst', 2]]}],
\ ['overrides: empty body returns original','x',                ['x', 'a'],                   ['x', 'a'],                   {'x': [['KeepFirst', 0]]}],
\ ['overrides: malformed rule skipped',     'x',                ['x', 'a'],                   ['x', 'a'],                   {'x': [['Bogus', 'a'], ['Drop']]}],
\ ['overrides: invalid regex skipped',      'x',                ['x', 'a'],                   ['x', 'a'],                   {'x': [['Drop', '[']]}],
\ ]

let s:exact = [
\ ['command word: no match',           ['zzzqqqzzz'], 1, v:none],
\ ['args: git zzz -> v:none',          ['git zzz'],   1, v:none],
\ ['override: unknown command -> none',['xyzzyq '],   1, v:none],
\ ]

let s:preds = [
\ ['args: git che -> check-attr',        ['git che'],           1, function('s:first'), 'check-attr'],
\ ['args: git che excludes add',         ['git che'],           1, function('s:excl'),  'add'],
\ ['args: git che all start with che',   ['git che'],           1, function('s:all'),   'che'],
\ ['args: cat completes fixture file',   ['cat '.s:data.'/fi'], 1, function('s:has'),   s:data.'/fixture.txt'],
\ ['args: git trailing space has add',   ['git '],              1, function('s:has'),   'add'],
\ ['args: git entries carry a menu',     ['git '],              1, function('s:menu'),  ''],
\ ['multiline: git \ + che',             ['git \', 'che'],      2, function('s:has'),   'check-attr'],
\ ['multiline: continuation then empty', ['git \', ''],         2, function('s:has'),   'add'],
\ ['multiline: option-led leader skip',  ['--x \', 'git '],     2, function('s:has'),   'add'],
\ ]


" -- scenarios --------------------------------------------------------------

function! s:run_main() abort
    call carapace#CarapaceComplete(1, '')
    call s:run_units(s:units)
    call s:run_exact(s:exact)
    call s:run_preds(s:preds)

    " command-word completion, PATH pinned to the fixture dir
    let saved = $PATH
    let $PATH = s:bindir
    call s:test('command word: gst-l -> gst-launch-1.0', [{'word': 'gst-launch-1.0'}],
                \ s:complete(['gst-l'], 1)[0], {'lines': ['gst-l'], 'lnum': 1})
    call s:test('command word: path form', [{'word': s:bindir . '/gst-launch-1.0'}],
                \ s:complete([s:bindir . '/gst-l'], 1)[0], {'lines': [s:bindir . '/gst-l'], 'lnum': 1})
    let $PATH = saved

    call s:with_rules({'xyzzyq': [['Replace', 'xyzzyq', 'git']]},
                \ 'override: Replace xyzzyq -> git', ['xyzzyq che'], 1, function('s:first'), 'check-attr')
    call s:with_rules({'git': [['Drop', 'zzz']]},
                \ 'override: Drop zzz -> add', ['git zzz '], 1, function('s:has'), 'add')

    let g:carapace_enabled = 0
    call s:test('config: disabled findstart -> -3', -3, carapace#CarapaceComplete(1, ''), {})
    call s:test('config: disabled complete -> v:none', v:none, carapace#CarapaceComplete(0, ''), {})
    let g:carapace_enabled = 1

    let saved_cf = &completefunc
    set completefunc=
    let g:carapace_enabled = 0
    if exists('g:loaded_carapace') | unlet g:loaded_carapace | endif
    runtime plugin/carapace.vim
    call s:test('plugin: enabled=0 leaves completefunc empty', '', &completefunc, {})
    set completefunc=
    let g:carapace_enabled = 1
    if exists('g:loaded_carapace') | unlet g:loaded_carapace | endif
    runtime plugin/carapace.vim
    call s:test('plugin: enabled=1 sets completefunc', 'carapace#CarapaceComplete', &completefunc, {})
    set completefunc=
    let &completefunc = saved_cf

    if $CARAPACE_HAVE_GST ==# '1' | call s:run_gst() | endif
endfunction

function! s:run_gst() abort
    let wrapper = ['wrapper.py \', 'gst-launch-1.0 \', '--gst-plugin-load /x \', 'v4 . ']
    let bare = ['gst-launch-1.0 --gst-plugin-load /x v4 ']

    call s:test('gst: bare --gst-plugin-load derails to options', 1,
                \ s:excl(s:complete(bare, 1)[0], '3gppmux'), {'lines': bare, 'lnum': 1})

    call s:with_rules({'gst-launch-1.0': [['DropWithValue', '--gst-plugin-load']]},
                \ 'gst: DropWithValue restores elements', wrapper, 4, function('s:has'), '3gppmux')
    call s:with_rules({'gst-launch-1.0': [['DropWithValue', '--gst-plugin-load'], ['KeepFirst', 2]]},
                \ 'gst: chained DropWithValue + KeepFirst', wrapper, 4, function('s:has'), '3gppmux')
    call s:with_rules({'gst-launch-1.0': [['Replace', 'gst-launch-1.0', 'git']]},
                \ 'gst: Replace gst -> git yields subcommands', ['gst-launch-1.0 che'], 1, function('s:first'), 'check-attr')

    call s:test('gst: --gst-plug completes option name', 1,
                \ s:has(s:complete(['gst-launch-1.0 --gst-plug'], 1)[0], '--gst-plugin-load'),
                \ {'lines': ['gst-launch-1.0 --gst-plug'], 'lnum': 1})

    let g:carapace_leader_fallbacks = 0
    call s:test('gst: leader_fallbacks=0 blocks wrapper', v:none, s:complete(wrapper, 4)[0],
                \ {'lines': wrapper, 'lnum': 4})
    unlet g:carapace_leader_fallbacks

    let saved = $PATH
    let $PATH = s:bindir
    call s:test('gst: inner leader gst-l command completion', [{'word': 'gst-launch-1.0'}],
                \ s:complete(['wrapper.py \', 'gst-l'], 2)[0], {'lines': ['wrapper.py \', 'gst-l'], 'lnum': 2})
    let $PATH = saved
endfunction

function! s:run_nobin() abort
    call s:test('no-bin: complete -> []', [], carapace#CarapaceComplete(0, ''), {'binary': g:carapace_binary})
    call s:test('no-bin: again -> [] (warn once)', [], carapace#CarapaceComplete(0, ''), {})
endfunction

function! s:run_falsebin() abort
    let [got, extra] = s:complete(['git '], 1)
    call s:test('false-bin: JSON decode failure -> v:none', v:none, got, extra)
endfunction

function! s:run_bridges() abort
    call carapace#CarapaceComplete(1, '')
    call s:test('bridges: $CARAPACE_BRIDGES', $CARAPACE_TEST_EXPECT_BRIDGES, $CARAPACE_BRIDGES,
                \ {'scenario': s:scenario, 'g:carapace_bridges': get(g:, 'carapace_bridges', '')})
endfunction


try
    if s:scenario ==# 'main'
        call s:run_main()
    elseif s:scenario ==# 'nobin'
        call s:run_nobin()
    elseif s:scenario ==# 'falsebin'
        call s:run_falsebin()
    elseif s:scenario ==# 'bridges' || s:scenario ==# 'bridges_custom'
        call s:run_bridges()
    else
        throw 'unknown scenario: ' . s:scenario
    endif
catch
    call add(s:rows, [s:scenario, 'Fail', 'harness error: ' . v:exception, '', '', ''])
finally
    call writefile(map(copy(s:rows), 's:row(v:val)'), $CARAPACE_TEST_RESULTS)
endtry

qa!
