" operator-api - Define your own operator using a callback function
"
" A new design of the operator-user api which handles nmap, omap, vmap, imap
" in a unified way.
"
" Acknowdgement: the development of this plugin is inspired by Kana Natsuno's
" vim-operator-user (https://github.com/kana/vim-operator-user)
"
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
" Interface  "{{{1

" augument the info dict with 'start', 'end' and 'motion_wiseness'
function! s:setpos(startmark, endmark, motion_wiseness, invoke_mode)
  let pos1 = getpos(a:startmark)
  let pos2 = getpos(a:endmark)

  if a:invoke_mode == 'v'
    " exclusive needs special treatment
    if &selection == 'exclusive'
      if a:motion_wiseness == 'char'
        if pos2[2] != 1
          let pos2[2] -= 1
        elseif pos2[1] == 1
          let pos2 = pos1
        else
          let pos2[1] -= 1
          let n = len(getline(pos2[1]))
          let pos2[2] = n?n:1  " at least 1
        endif
      endif
      " if you only select one char and press d, that char will be deleted even
      " in exclusive mode
      if pos2[1] < pos1[1] || (pos2[1] == pos1[1] && pos2[2] < pos1[2])
        let pos2 = pos1
      endif
    endif
    let s:info['start'] = pos1
    let s:info['end'] = pos2
    let s:info['End'] = pos2
    call setpos("'[", pos1)
    call setpos("']", pos2)
    let s:info['empty'] = 0  " visual mode will never be empty
  else
    " Whenever 'operatorfunc' is called, '[ is always placed before '] even if
    " a backward motion is given to g@.  But there is the only one exception.
    " If an empty region is given to g@, '[ and '] are set to the same line, but
    " '[ is placed after '].
    " see https://github.com/kana/vim-operator-replace/issues/2
    let s:info['empty'] = pos1[1] == pos2[1] && pos1[2] > pos2[2]
    let s:info['start'] = pos1
    let s:info['End'] = pos2
    if !s:info['empty']
      let s:info['end'] = pos2
    endif
  endif
  let s:info['motion_wiseness'] = a:motion_wiseness
endfunction

"let g:oinfo = s:info

" mode: i for imap, v for vmap, n for nmap
" (omap does not call this function)
" the returned dict will be augumented with 'start', 'end' and 'motion_wiseness'
"
" execute_mode: the mode the function is called
" invoke_mode: the mode the mapping is invoked, (whether it is imap, omap...)
function! s:init_info(callback, invoke_mode, extra)
  let s:saved = {
        \ 'virtualedit': &virtualedit,
        \ }
  let info = {
        \ 'callback' : function(a:callback),
        \ 'cursor': getpos("."),
        \ 'count': v:count,
        \ 'count1': v:count1,
        \ 'register': v:register,
        \ 'invoke_mode': a:invoke_mode,
        \ 'buf': bufnr('%'),
        \ }
  call extend(info, a:extra)
  let s:info = info
endfunction

function! operator_api#operatorfunc(motion_wiseness) abort
  let l:Func = s:info.callback
  call s:setpos("'[", "']", a:motion_wiseness, s:info.invoke_mode)
  try
    let rv = l:Func(s:info)
    if type(rv) == v:t_list
      call setpos('.', rv)
    endif
  catch
    throw 'operator nmap: ' . v:exception
  finally
    let &virtualedit = s:saved.virtualedit
    if s:info.invoke_mode == 'i' && s:saved.restore_cursor
      if s:info.buf != bufnr('%')
        exe 'b' s:info.buf
      endif
      " call cursor() does not work
      call setpos('.', getpos("'^"))
    endif
  endtry
endfunction

" because we are using <expr> mapping, the count inserted is still in the
" typeahead buffer waiting to be processed
" to cancel this count, use "@_" in normal/visual mode
" In operator-pending mode, this count is not cancellable
function! operator_api#_nmap(callback, propagate_count, extra)
  set operatorfunc=operator_api#operatorfunc
  call s:init_info(a:callback, 'n', a:extra)
  let cancel = a:propagate_count ? '' : '@_'
  return cancel . 'g@'
endfunction

let s:motion_wiseness = {'v': 'char', 'V': 'line', "\<c-v>": 'block'}
let s:visual_mode = { 'char':'v', 'line': 'V', 'block': "\<c-v>"}
function! operator_api#_vmap(funcname, count, extra_options)
  let command = printf(":\<c-u>call operator_api#_vmap(%s, -1, %s)\<cr>", string(a:funcname), a:extra_options)
  if a:count == -1
    " this part is called in normal mode, by the command defined above
    let Callback = function(a:funcname)
    call s:init_info(Callback, 'v', a:extra_options)
    call s:setpos("'<", "'>", s:motion_wiseness[visualmode()], 'v')
    try
      let rv = Callback(s:info)
      if type(rv) == v:t_list
        call setpos('.', rv)
      endif
    catch
      throw 'operator vmap: ' . v:exception
    endtry
  elseif a:count == 0
    " this part is called in <expr> mode for the case propagate_count == 0
    return command
  else
    " this part is called in <expr> mode for the case propagate_count == 1
    return printf(":\<cr>%sv%s", a:count, command)
  endif
endfunction

function! operator_api#_imap(callback, restore_cursor, extra)
  try
    call s:init_info(a:callback, 'i', a:extra)
    let s:saved['restore_cursor'] = a:restore_cursor
    set operatorfunc=operator_api#operatorfunc
    let &virtualedit = 'onemore'
    return "\<c-o>g@"
  catch
    throw 'operator imap: ' . v:exception
  endtry
endfunction
function! operator_api#_omap(callback, forward, extra)
  let samemap = v:operator == 'g@'
        \  && &operatorfunc == 'operator_api#operatorfunc'
        \  && s:info['callback'] == function(a:callback)
  if !samemap
    return "\<esc>"
  elseif a:forward || v:count1 == 1
    return '_'
  else
    let rv = printf(":normal! %d-\<cr>", v:count1 - 1)
    return rv
  endif
endfunction

" optional: modes (default "nvo")
" extra_options (a dict to passed to info)
function! operator_api#define(keyseq, callback, ...) abort
  let keyseq = a:keyseq
  if type(a:callback) != v:t_string || type(function(a:callback)) != v:t_func
    throw printf('define operator %s failed: callback %s is not a function', a:keyseq, a:callback)
  endif
  try
    let funcname = string(a:callback)
    let modes = get(a:000, 0, 'nvo')
    let extra_options = get(a:000, 1, {})
    if eval(string(extra_options)) != extra_options
      throw 'extra_options cannot be used'
    endif
    if modes =~ '[nN]'
      let propagate_count = modes =~ 'n'
      execute printf('nnoremap <silent> <expr> %s operator_api#_nmap(%s, %d, %s)',
            \  keyseq, funcname, propagate_count, extra_options)
    endif
    if modes =~ '[vV]'
      let propagate_count = modes =~ 'V'
      let count = propagate_count? 'v:count1' : '0'
      execute printf('vnoremap <silent> <expr> %s operator_api#_vmap(%s, %s, %s)',
            \ keyseq, funcname, count, extra_options)
    endif
    if modes =~ '[iI]'
      let restore_cursor = modes =~ 'I'
      execute printf('inoremap <silent> <expr> %s operator_api#_imap(%s, %d, %s)',
            \  keyseq, funcname, restore_cursor, extra_options)
    endif
    if modes =~ '[oO]'
      let forward = modes =~ 'o'
      execute printf('onoremap <silent> <expr> %s operator_api#_omap(%s, %d, %s)',
            \  keyseq, funcname, forward, extra_options)
    endif
  catch
    throw printf('define operator %s failed: %s', a:keyseq, v:exception)
  endtry
endfunction

" other helper functions
function! operator_api#default_map(name)
  return '<Plug>(operator-api-' . a:name . ')'
endfunction
function! operator_api#default_callback(info)
  echo a:info
  if a:info.type == 'o'
    return a:info.End
  else
    return a:info.start
  endif
endfunction
call operator_api#define(';o', 'operator_api#default_callback', 'nvio', {'type': 'o'})
call operator_api#define(';O', 'operator_api#default_callback', 'NVIO', {'type': 'O'})

function! operator_api#selection()
  if s:info.empty
    return []
  endif
  let [l1, c1] = s:info.start[1:2]
  let [l2, c2] = s:info.end[1:2]
  let mode = s:info.motion_wiseness
  let lines = getline(l1, l2)
  if mode == 'line' || mode == 'V'
  elseif mode == 'block' || mode == "\<c-v>"
    call map(lines, {i,x-> x[c1-1:c2-1]})
  elseif mode == 'char' || mode == 'v'
    if l1 == l2
      let lines[0] = lines[0][c1-1:c2-1]
    else
      let lines[0] = lines[0][c1-1:]
      let lines[-1] = lines[-1][:c2-1]
    endif
  else
    throw 'unknown mode: ' . mode
  endif
  return lines
endfunction

function! operator_api#deletion_moves_cursor()
  if s:info.empty
    return 0
  endif
  let motion_wiseness = s:info.motion_wiseness
  let motion_end_pos = s:info.end
  let [buffer_end_line, buffer_end_col] = [line('$'), len(getline('$'))]
  let [motion_end_line, motion_end_col] = motion_end_pos[1:2]
  let motion_end_last_col = len(getline(motion_end_line))
  if motion_wiseness ==# 'char'
    return ((motion_end_last_col == motion_end_col)
    \       || (buffer_end_line == motion_end_line
    \           && buffer_end_col <= motion_end_col))
    "return motion_end_last_col == motion_end_col
  elseif motion_wiseness ==# 'line'
    return buffer_end_line == motion_end_line
  elseif motion_wiseness ==# 'block'
    return 0
  else
    echoerr 'E2: Invalid wise name:' string(motion_wiseness)
    return 0
  endif
endfunction

function! operator_api#visual_select(...) abort
  let invoke_mode = s:info.invoke_mode
  let keystrokes = get(a:000, 0, '')
  let motion_wiseness = get(a:000, 1, s:info['motion_wiseness'])
  if s:info.empty && motion_wiseness != 'line'
    call setpos("'<", [0, 0, 0, 0])
    call setpos("'>", [0, 0, 0, 0])
    throw 'empty region in v-char/v-block mode is not allowed'
  else
    let vmode = s:visual_mode[motion_wiseness]
    exe printf('normal! `[%s`]%s', vmode, keystrokes)
  endif
  return
endfunction

" __END__  "{{{1
" vim: foldmethod=marker
