"============================================================================
"File:        syntastic.vim
"Description: vim plugin for on the fly syntax checking
"Maintainer:  Martin Grenfell <martin.grenfell at gmail dot com>
"Version:     2.3.0
"Last Change: 16 Feb, 2012
"License:     This program is free software. It comes without any warranty,
"             to the extent permitted by applicable law. You can redistribute
"             it and/or modify it under the terms of the Do What The Fuck You
"             Want To Public License, Version 2, as published by Sam Hocevar.
"             See http://sam.zoy.org/wtfpl/COPYING for more details.
"
"============================================================================

if exists("g:loaded_syntastic_plugin")
    finish
endif
let g:loaded_syntastic_plugin = 1

runtime plugin/syntastic/*.vim

let s:running_windows = has("win16") || has("win32")

if !exists("g:syntastic_enable_signs")
    let g:syntastic_enable_signs = 1
endif

if !exists("g:syntastic_error_symbol")
    let g:syntastic_error_symbol = '>>'
endif

if !exists("g:syntastic_warning_symbol")
    let g:syntastic_warning_symbol = '>>'
endif

if !exists("g:syntastic_style_error_symbol")
    let g:syntastic_style_error_symbol = 'S>'
endif

if !exists("g:syntastic_style_warning_symbol")
    let g:syntastic_style_warning_symbol = 'S>'
endif

if !has('signs')
    let g:syntastic_enable_signs = 0
endif

if !exists("g:syntastic_enable_balloons")
    let g:syntastic_enable_balloons = 1
endif
if !has('balloon_eval')
    let g:syntastic_enable_balloons = 0
endif

if !exists("g:syntastic_enable_highlighting")
    let g:syntastic_enable_highlighting = 1
endif

" highlighting requires getmatches introduced in 7.1.040
if v:version < 701 || (v:version == 701 && !has('patch040'))
    let g:syntastic_enable_highlighting = 0
endif

if !exists("g:syntastic_echo_current_error")
    let g:syntastic_echo_current_error = 1
endif

if !exists("g:syntastic_auto_loc_list")
    let g:syntastic_auto_loc_list = 2
endif

if !exists("g:syntastic_auto_jump")
    let syntastic_auto_jump=0
endif

if !exists("g:syntastic_quiet_warnings")
    let g:syntastic_quiet_warnings = 0
endif

if !exists("g:syntastic_stl_format")
    let g:syntastic_stl_format = '[Syntax: line:%F (%t)]'
endif

if !exists("g:syntastic_mode_map")
    let g:syntastic_mode_map = {}
endif

if !has_key(g:syntastic_mode_map, "mode")
    let g:syntastic_mode_map['mode'] = 'active'
endif

if !has_key(g:syntastic_mode_map, "active_filetypes")
    let g:syntastic_mode_map['active_filetypes'] = []
endif

if !has_key(g:syntastic_mode_map, "passive_filetypes")
    let g:syntastic_mode_map['passive_filetypes'] = []
endif

if !exists("g:syntastic_check_on_open")
    let g:syntastic_check_on_open = 0
endif

if !exists("g:syntastic_loc_list_height")
    let g:syntastic_loc_list_height = 10
endif

let s:registry = g:SyntasticRegistry.Instance()

function! s:CompleteCheckerName(argLead, cmdLine, cursorPos)
    let checker_names = []
    for ft in s:CurrentFiletypes()
        for checker in s:registry.availableCheckersFor(ft)
            call add(checker_names, checker.name())
        endfor
    endfor
    return join(checker_names, "\n")
endfunction

command! SyntasticToggleMode call s:ToggleMode()
command! -nargs=? -complete=custom,s:CompleteCheckerName SyntasticCheck call s:UpdateErrors(0, <f-args>) <bar> call s:Redraw()
command! Errors call s:ShowLocList()

highlight link SyntasticError SpellBad
highlight link SyntasticWarning SpellCap

augroup syntastic
    if g:syntastic_echo_current_error
        autocmd cursormoved * call s:EchoCurrentError()
    endif

    autocmd BufReadPost * if g:syntastic_check_on_open | call s:UpdateErrors(1) | endif
    autocmd BufWritePost * call s:UpdateErrors(1)

    autocmd BufWinEnter * if empty(&bt) | call s:AutoToggleLocList() | endif
    autocmd BufWinLeave * if empty(&bt) | lclose | endif
augroup END


"refresh and redraw all the error info for this buf when saving or reading
function! s:UpdateErrors(auto_invoked, ...)
    if !empty(&buftype)
        return
    endif

    let time = reltime()
    try
    if !a:auto_invoked || s:ModeMapAllowsAutoChecking()
        if a:0 >= 1
            call s:CacheErrors(a:1)
        else
            call s:CacheErrors()
        endif
    end

    if g:syntastic_enable_balloons
        call s:RefreshBalloons()
    endif

    if g:syntastic_enable_signs
        call s:RefreshSigns()
    endif

    if g:syntastic_enable_highlighting
        call s:HighlightErrors()
    endif

    let loclist = s:LocList()
    if g:syntastic_auto_jump && loclist.hasErrorsOrWarningsToDisplay()
        silent! ll
    endif

    call s:AutoToggleLocList()
    finally
        echomsg 'UpdateErrors(' . a:auto_invoked . '): ' . reltimestr(reltime(time))
    endtry
endfunction

"automatically open/close the location list window depending on the users
"config and buffer error state
function! s:AutoToggleLocList()
    let loclist = s:LocList()
    if loclist.hasErrorsOrWarningsToDisplay()
        if g:syntastic_auto_loc_list == 1
            call s:ShowLocList()
        endif
    else
        if g:syntastic_auto_loc_list > 0

            "TODO: this will close the loc list window if one was opened by
            "something other than syntastic
            lclose
        endif
    endif
endfunction

"lazy init the loc list for the current buffer
function! s:LocList()
    if !exists("b:syntastic_loclist")
        let b:syntastic_loclist = g:SyntasticLoclist.New([])
    endif
    return b:syntastic_loclist
endfunction

"clear the loc list for the buffer
function! s:ClearCache()
    unlet! b:syntastic_loclist
endfunction

function! s:CurrentFiletypes()
    "sub - for _ in filetypes otherwise we cant name syntax checker
    "functions legally for filetypes like "gentoo-metadata"
    let fts = substitute(&ft, '-', '_', 'g')
    return split(fts, '\.')
endfunction

"detect and cache all syntax errors in this buffer
function! s:CacheErrors(...)
    let time = reltime()
    try
    call s:ClearCache()
    let newLoclist = g:SyntasticLoclist.New([])

    if filereadable(expand("%"))
        for ft in s:CurrentFiletypes()

            if a:0
                let checker = s:registry.getChecker(ft, a:1)
                if !empty(checker)
                    let checkers = [checker]
                endif
            else
                let checkers = s:registry.getActiveCheckers(ft)
            endif

            for checker in checkers
                let loclist = checker.getLocList()

                if !loclist.isEmpty()
                    let newLoclist = newLoclist.extend(loclist)

                    "only get errors from one checker at a time
                    break
                endif
            endfor
        endfor
    endif

    let b:syntastic_loclist = newLoclist
    finally
        echomsg 'CacheErrors: ' . reltimestr(reltime(time))
    endtry
endfunction

"toggle the g:syntastic_mode_map['mode']
function! s:ToggleMode()
    if g:syntastic_mode_map['mode'] == "active"
        let g:syntastic_mode_map['mode'] = "passive"
    else
        let g:syntastic_mode_map['mode'] = "active"
    endif

    call s:ClearCache()
    call s:UpdateErrors(1)

    echo "Syntastic: " . g:syntastic_mode_map['mode'] . " mode enabled"
endfunction

"check the current filetypes against g:syntastic_mode_map to determine whether
"active mode syntax checking should be done
function! s:ModeMapAllowsAutoChecking()
    let fts = split(&ft, '\.')

    if g:syntastic_mode_map['mode'] == 'passive'
        "check at least one filetype is active
        let actives = g:syntastic_mode_map["active_filetypes"]
        return !empty(filter(fts, 'index(actives, v:val) != -1'))
    else
        "check no filetypes are passive
        let passives = g:syntastic_mode_map["passive_filetypes"]
        return empty(filter(fts, 'index(passives, v:val) != -1'))
    endif
endfunction

if g:syntastic_enable_signs
    "define the signs used to display syntax and style errors/warns
    exe 'sign define SyntasticError text='.g:syntastic_error_symbol.' texthl=error'
    exe 'sign define SyntasticWarning text='.g:syntastic_warning_symbol.' texthl=todo'
    exe 'sign define SyntasticStyleError text='.g:syntastic_style_error_symbol.' texthl=error'
    exe 'sign define SyntasticStyleWarning text='.g:syntastic_style_warning_symbol.' texthl=todo'
endif

"start counting sign ids at 5000, start here to hopefully avoid conflicting
"with any other code that places signs (not sure if this precaution is
"actually needed)
let s:first_sign_id = 5000
let s:next_sign_id = s:first_sign_id

"place signs by all syntax errs in the buffer
function! s:SignErrors()
    let time = reltime()
    try
    let loclist = s:LocList()
    echomsg 'loclist[' . loclist.length()  . ']'
    if loclist.hasErrorsOrWarningsToDisplay()

        let errors = loclist.filter({'bufnr': bufnr('')})
        let time2 = reltime()
        try
        for i in errors
            let sign_severity = 'Error'
            let sign_subtype = ''
            if has_key(i,'subtype')
                let sign_subtype = i['subtype']
            endif
            if i['type'] ==? 'w'
                let sign_severity = 'Warning'
            endif
            let sign_type = 'Syntastic' . sign_subtype . sign_severity

            if !s:WarningMasksError(i, errors)
                exec "sign place ". s:next_sign_id ." line=". i['lnum'] ." name=". sign_type ." file=". expand("%:p")
                call add(s:BufSignIds(), s:next_sign_id)
                let s:next_sign_id += 1
            endif
        endfor
        finally
            echomsg 'SignErrors loop: ' . reltimestr(reltime(time2))
        endtry
    endif
    finally
        echomsg 'SignErrors: ' . reltimestr(reltime(time))
    endtry
endfunction

"return true if the given error item is a warning that, if signed, would
"potentially mask an error if displayed at the same time
function! s:WarningMasksError(error, llist)
    if a:error['type'] !=? 'w'
        return 0
    endif

    let loclist = g:SyntasticLoclist.New(a:llist)
    return len(loclist.filter({ 'type': "E", 'lnum': a:error['lnum'] })) > 0
endfunction

"remove the signs with the given ids from this buffer
function! s:RemoveSigns(ids)
    let time = reltime()
    try
    for i in a:ids
        exec "sign unplace " . i
        call remove(s:BufSignIds(), index(s:BufSignIds(), i))
    endfor
    finally
        echomsg 'RemoveSigns: ' . reltimestr(reltime(time))
    endtry
endfunction

"get all the ids of the SyntaxError signs in the buffer
function! s:BufSignIds()
    if !exists("b:syntastic_sign_ids")
        let b:syntastic_sign_ids = []
    endif
    return b:syntastic_sign_ids
endfunction

"update the error signs
function! s:RefreshSigns()
    let time = reltime()
    try
    let old_signs = copy(s:BufSignIds())
    echomsg '* old_signs[' . len(old_signs) . ']'
    call s:SignErrors()
    call s:RemoveSigns(old_signs)
    let s:first_sign_id = s:next_sign_id
    finally
        echomsg 'RefreshSigns: ' . reltimestr(reltime(time))
    endtry
endfunction

"display the cached errors for this buf in the location list
function! s:ShowLocList()
    let loclist = s:LocList()
    if !loclist.isEmpty()
        call setloclist(0, loclist.toRaw())
        let num = winnr()
        exec "lopen " . g:syntastic_loc_list_height
        if num != winnr()
            wincmd p
        endif
    endif
endfunction

"highlight the current errors using matchadd()
"
"The function `Syntastic_{&ft}_GetHighlightRegex` is used to get the regex to
"highlight errors that do not have a 'col' key (and hence cant be done
"automatically). This function must take one arg (an error item) and return a
"regex to match that item in the buffer.
"
"If the 'force_highlight_callback' key is set for an error item, then invoke
"the callback even if it can be highlighted automatically.
function! s:HighlightErrors()
    let time = reltime()
    try
    call s:ClearErrorHighlights()
    let loclist = s:LocList()

    let fts = substitute(&ft, '-', '_', 'g')
    for ft in split(fts, '\.')

        for item in loclist.toRaw()

            let force_callback = has_key(item, 'force_highlight_callback') && item['force_highlight_callback']

            let group = item['type'] == 'E' ? 'SyntasticError' : 'SyntasticWarning'
            if get( item, 'col' ) && !force_callback
                let lastcol = col([item['lnum'], '$'])
                let lcol = min([lastcol, item['col']])
                call matchadd(group, '\%'.item['lnum'].'l\%'.lcol.'c')
            else

                if exists("*SyntaxCheckers_". ft ."_GetHighlightRegex")
                    let term = SyntaxCheckers_{ft}_GetHighlightRegex(item)
                    if len(term) > 0
                        call matchadd(group, '\%' . item['lnum'] . 'l' . term)
                    endif
                endif
            endif
        endfor
    endfor
    finally
        echomsg 'HighlightErrors: ' . reltimestr(reltime(time))
    endtry
endfunction

"remove all error highlights from the window
function! s:ClearErrorHighlights()
    for match in getmatches()
        if stridx(match['group'], 'Syntastic') == 0
            call matchdelete(match['id'])
        endif
    endfor
endfunction

"set up error ballons for the current set of errors
function! s:RefreshBalloons()
    let time = reltime()
    try
    let b:syntastic_balloons = {}
    let loclist = s:LocList()
    if loclist.hasErrorsOrWarningsToDisplay()
        for i in loclist.toRaw()
            let b:syntastic_balloons[i['lnum']] = i['text']
        endfor
        set beval bexpr=SyntasticErrorBalloonExpr()
    endif
    finally
        echomsg 'RefreshBalloons: ' . reltimestr(reltime(time))
    endtry
endfunction

"print as much of a:msg as possible without "Press Enter" prompt appearing
function! s:WideMsg(msg)
    let old_ruler = &ruler
    let old_showcmd = &showcmd

    "convert tabs to spaces so that the tabs count towards the window width
    "as the proper amount of characters
    let msg = substitute(a:msg, "\t", repeat(" ", &tabstop), "g")
    let msg = strpart(msg, 0, winwidth(0)-1)

    "This is here because it is possible for some error messages to begin with
    "\n which will cause a "press enter" prompt. I have noticed this in the
    "javascript:jshint checker and have been unable to figure out why it
    "happens
    let msg = substitute(msg, "\n", "", "g")

    set noruler noshowcmd
    redraw

    echo msg

    let &ruler=old_ruler
    let &showcmd=old_showcmd
endfunction

"echo out the first error we find for the current line in the cmd window
function! s:EchoCurrentError()
    let loclist = s:LocList()
    "If we have an error or warning at the current line, show it
    let errors = loclist.filter({'lnum': line("."), "type": 'e'})
    let warnings = loclist.filter({'lnum': line("."), "type": 'w'})

    let b:syntastic_echoing_error = len(errors) || len(warnings)
    if len(errors)
        return s:WideMsg(errors[0]['text'])
    endif
    if len(warnings)
        return s:WideMsg(warnings[0]['text'])
    endif

    "Otherwise, clear the status line
    if b:syntastic_echoing_error
        echo
        let b:syntastic_echoing_error = 0
    endif
endfunction

"the script changes &shellpipe and &shell to stop the screen flicking when
"shelling out to syntax checkers. Not all OSs support the hacks though
function! s:OSSupportsShellpipeHack()
    return !s:running_windows && (s:uname() !~ "FreeBSD") && (s:uname() !~ "OpenBSD")
endfunction

function! s:IsRedrawRequiredAfterMake()
    return !s:running_windows && (s:uname() =~ "FreeBSD" || s:uname() =~ "OpenBSD")
endfunction

"Redraw in a way that doesnt make the screen flicker or leave anomalies behind.
"
"Some terminal versions of vim require `redraw!` - otherwise there can be
"random anomalies left behind.
"
"However, on some versions of gvim using `redraw!` causes the screen to
"flicker - so use redraw.
function! s:Redraw()
    let time = reltime()
    try
    if has('gui_running')
        redraw
    else
        redraw!
    endif
    finally
        echomsg 'Redraw: '.reltimestr(reltime(time))
    endtry
endfunction

function! s:uname()
    if !exists('s:uname')
        let s:uname = system('uname')
    endif
    return s:uname
endfunction

"the args must be arrays of the form [major, minor, macro]
function SyntasticIsVersionAtLeast(installed, required)
    if a:installed[0] != a:required[0]
        return a:installed[0] > a:required[0]
    endif

    if a:installed[1] != a:required[1]
        return a:installed[1] > a:required[1]
    endif

    return a:installed[2] >= a:required[2]
endfunction

"return a string representing the state of buffer according to
"g:syntastic_stl_format
"
"return '' if no errors are cached for the buffer
function! SyntasticStatuslineFlag()
    let loclist = s:LocList()
    if loclist.hasErrorsOrWarningsToDisplay()
        let errors = loclist.errors()
        let warnings = loclist.warnings()

        let num_errors = len(errors)
        let num_warnings = len(warnings)

        let output = g:syntastic_stl_format

        "hide stuff wrapped in %E(...) unless there are errors
        let output = substitute(output, '\C%E{\([^}]*\)}', num_errors ? '\1' : '' , 'g')

        "hide stuff wrapped in %W(...) unless there are warnings
        let output = substitute(output, '\C%W{\([^}]*\)}', num_warnings ? '\1' : '' , 'g')

        "hide stuff wrapped in %B(...) unless there are both errors and warnings
        let output = substitute(output, '\C%B{\([^}]*\)}', (num_warnings && num_errors) ? '\1' : '' , 'g')


        "sub in the total errors/warnings/both
        let output = substitute(output, '\C%w', num_warnings, 'g')
        let output = substitute(output, '\C%e', num_errors, 'g')
        let output = substitute(output, '\C%t', loclist.length(), 'g')

        "first error/warning line num
        let output = substitute(output, '\C%F', loclist.toRaw()[0]['lnum'], 'g')

        "first error line num
        let output = substitute(output, '\C%fe', num_errors ? errors[0]['lnum'] : '', 'g')

        "first warning line num
        let output = substitute(output, '\C%fw', num_warnings ? warnings[0]['lnum'] : '', 'g')

        return output
    else
        return ''
    endif
endfunction

"A wrapper for the :lmake command. Sets up the make environment according to
"the options given, runs make, resets the environment, returns the location
"list
"
"a:options can contain the following keys:
"    'makeprg'
"    'errorformat'
"
"The corresponding options are set for the duration of the function call. They
"are set with :let, so dont escape spaces.
"
"a:options may also contain:
"   'defaults' - a dict containing default values for the returned errors
"   'subtype' - all errors will be assigned the given subtype
function! SyntasticMake(options)
    let old_loclist = getloclist(0)
    let old_makeprg = &l:makeprg
    let old_shellpipe = &shellpipe
    let old_shell = &shell
    let old_errorformat = &l:errorformat

    if s:OSSupportsShellpipeHack()
        "this is a hack to stop the screen needing to be ':redraw'n when
        "when :lmake is run. Otherwise the screen flickers annoyingly
        let &shellpipe='&>'
        let &shell = '/bin/bash'
    endif

    if has_key(a:options, 'makeprg')
        let &l:makeprg = a:options['makeprg']
    endif

    if has_key(a:options, 'errorformat')
        let &l:errorformat = a:options['errorformat']
    endif

    silent lmake!
    let errors = getloclist(0)

    call setloclist(0, old_loclist)
    let &l:makeprg = old_makeprg
    let &l:errorformat = old_errorformat
    let &shellpipe=old_shellpipe
    let &shell=old_shell

    if s:IsRedrawRequiredAfterMake()
        call s:Redraw()
    endif

    if has_key(a:options, 'defaults')
        call SyntasticAddToErrors(errors, a:options['defaults'])
    endif

    " Add subtype info if present.
    if has_key(a:options, 'subtype')
        call SyntasticAddToErrors(errors, {'subtype': a:options['subtype']})
    endif

    return errors
endfunction

"get the error balloon for the current mouse position
function! SyntasticErrorBalloonExpr()
    if !exists('b:syntastic_balloons')
        return ''
    endif
    return get(b:syntastic_balloons, v:beval_lnum, '')
endfunction

"take a list of errors and add default values to them from a:options
function! SyntasticAddToErrors(errors, options)
    for i in range(0, len(a:errors)-1)
        for key in keys(a:options)
            if !has_key(a:errors[i], key) || empty(a:errors[i][key])
                let a:errors[i][key] = a:options[key]
            endif
        endfor
    endfor
    return a:errors
endfunction

" vim: set et sts=4 sw=4:
