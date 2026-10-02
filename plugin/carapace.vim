if exists('g:loaded_carapace')
    finish
endif
let g:loaded_carapace = 1

if get(g:, 'carapace_enabled', 1)
    set completefunc=carapace#CarapaceComplete
endif
