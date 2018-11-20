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
function! s:setpos(startmark, endmark, motion_wiseness)
  unlockvar s:info
  let pos1 = getpos("'".a:startmark)
  let pos2 = getpos("'".a:endmark)
  2Log pos1 pos2
  if pos1[1] > pos2[1] || (pos1[1] == pos2[1] && pos1[2] > pos2[2])
    let s:info['start'] = pos2
    let s:info['end'] = pos1
  else
    let s:info['start'] = pos1
    let s:info['end'] = pos2
  endif
  let s:info['motion_wiseness'] = a:motion_wiseness
  lockvar s:info
endfunction

" mode: i for imap, v for vmap, n for nmap
" (omap does not call this function)
" the returned dict will be augumented with 'start', 'end' and 'motion_wiseness'
"
" execute_mode: the mode the function is called
" invoke_mode: the mode the mapping is invoked, (whether it is imap, omap...)
function! s:init_info(callback, invoke_mode, execute_mode)
  unlock! s:info
  let s:info = {
        \ 'callback' : function(a:callback),
        \ 'cursor': getpos("."),
        \ 'count': v:count,
        \ 'count1': v:count1,
        \ 'register': v:register,
        \ 'invoke_mode': a:invoke_mode,
        \ 'execute_mode' : a:execute_mode,
        \ }
  lockvar s:info
  let s:saved = {
        \ 'virtualedit': &virtualedit,
        \ }
endfunction

function! operator_api#operatorfunc(motion_wiseness) abort
  let F = s:info.callback
  2Log a:motion_wiseness 'opfunc'
  call s:setpos('[', ']', a:motion_wiseness)
  try
    call F(s:info)
  finally
    let &virtualedit = s:saved.virtualedit
  endtry
endfunction
function! operator_api#operatorfunc_dummy()
  let &virtualedit = s:saved.virtualedit
endfunction

function! operator_api#nmap(callback, propagate_count)
  set operatorfunc=operator_api#operatorfunc
  call s:init_info(a:callback, 'n', 'n')
  " because we are using <expr> mapping, the count inserted is still in the
  " typeahead buffer waiting to be processed
  " to cancel this count, use "@_" in normal/visual mode
  " In operator-pending mode, this count is not cancellable
  "
  "let count = s:info.count
  "let count_str = count ? string(count) : ''
  return a:propagate_count ? "g@" : '@_g@'
endfunction
function! operator_api#imap(callback, call_in_normal_mode)
  let &virtualedit = 'onemore'
  if a:call_in_normal_mode
    call s:init_info(a:callback, 'i', 'n')
    set operatorfunc=operator_api#operatorfunc
    return "\<c-o>g@"
  else
    call s:init_info(a:callback, 'i', 'i')
    set operatorfunc=operator_api#operatorfunc_dummy
    exe "normal! \<c-o>g@"
    let F = function(a:callback)
    return F(s:info)
  endif
endfunction
function! operator_api#omap(callback)
  let samemap = v:operator == "g@"
        \  && (&operatorfunc == 'operator_api#operatorfunc'
        \  || &operatorfunc == 'operator_api#operatorfunc_dummy')
        \  && s:info['callback'] == function(a:callback)
  return samemap? 'g@' : "\<esc>"
endfunction


let s:motion_wiseness = {'v': 'char', 'V': 'line', "\<c-v>": 'block'}
let s:visual_mode = { 'char':'v', 'line': 'V', 'block': "\<c-v>"}
" this function is called in normal mode, since we didn't use <expr>-map
function! operator_api#vmap(callback, call_in_normal_mode)
  if a:call_in_normal_mode
    call s:init_info(a:callback, 'v', 'n')
    call s:setpos("<", ">", s:motion_wiseness[visualmode()])
    "call setpos("'[", s:info.start)
    "call setpos("']", s:info.end)
    2Log getpos("'<") getpos("'>")
  else
    call s:init_info(a:callback, 'v', 'v')
    call s:setpos(".", "v", s:motion_wiseness[mode()])
  endif
  let F = function(a:callback)
  return F(s:info)
endfunction

function! operator_api#define(keyseq, callback, ...)
  let keyseq = a:keyseq
  let funcname = string(a:callback)
  let modes = get(a:000, 0, 'nvo')
  if modes =~ '[nN]'
    let propagate_count = modes =~ 'n'
    execute printf('nnoremap <script> <silent> <expr> %s operator_api#nmap(%s, %d)', keyseq, funcname, propagate_count)
  endif
  if modes =~ 'o'
    execute printf('onoremap <script> <silent> <expr> %s operator_api#omap(%s)', keyseq, funcname)
  endif
  if modes =~ '[iI]'
    let call_in_normal_mode = modes =~ 'i'
    execute printf('inoremap <script> <silent> <expr> %s operator_api#imap(%s, %d)', keyseq, funcname, call_in_normal_mode)
  endif
  if modes =~ '[vV]'
    let call_in_normal_mode = modes =~ 'v'
      " doesn't use <expr>, the function is called in normal mode
    if call_in_normal_mode
      execute printf('vnoremap <script> <silent> %s :<c-u>call operator_api#vmap(%s, 1)<cr>', keyseq, funcname)
    else
      " uses <expr>, the function is called in visual mode
      execute printf('vnoremap <script> <silent> <expr> %s operator_api#vmap(%s, 0)<cr>', keyseq, funcname)
    endif
  endif
endfunction


function! operator_api#default_map(name)
  return '<Plug>(operator-' . a:name . ')'
endfunction
function! operator_api#default_callback(info)
  echo a:info
endfunction
call operator_api#define(';o', 'operator_api#default_callback', 'novi')
call operator_api#define(';O', 'operator_api#default_callback', 'Novi')

" when will this happen?
function! operator_api#is_empty_region(start, end)
  " Whenever 'operatorfunc' is called, '[ is always placed before '] even if
  " a backward motion is given to g@.  But there is the only one exception.
  " If an empty region is given to g@, '[ and '] are set to the same line, but
  " '[ is placed after '].
  let start = s:info.start
  let end = s:info.end
  return start[1] == end[1] && end[2] < start[2]
endfunction

function! operator_api#visual_select() abort
  let invoke_mode = s:info.invoke_mode
  let execute_mode = s:info.execute_mode
  if invoke_mode == 'v'
    if execute_mode == 'n'
      normal! gv
    else
      " already in visual mode
    endif
  elseif execute_mode == 'n'
    let vmode = s:visual_mode[s:info['motion_wiseness']]
    exe printf('normal! `[%s`]', vmode)
  elseif execute_mode == 'i'
    let vmode = s:visual_mode[s:info['motion_wiseness']]
    exe printf("normal! \<c-o>`[%s`]", vmode)
  endif
endfunction

function! operator_api#get_visual_selection()

endfunction

function! operator_api#deletion_moves_cursor()
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
" __END__  "{{{1
" vim: foldmethod=marker
