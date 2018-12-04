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

" augument the info dict with 'begin', 'end' and 'motion_wiseness'
let s:motion_wiseness = {'v': 'char', 'V': 'line', "\<c-v>": 'block'}
let s:visual_mode = { 'char':'v', 'line': 'V', 'block': "\<c-v>"}
function! s:compare_pos(pos1, pos2, motion_wiseness)
  if a:pos1[1] < a:pos2[1]
    return -1
  elseif a:pos1[1] > a:pos2[1]
    return 1
  elseif a:motion_wiseness == 'line'
    return 0
  elseif a:pos1[2] < a:pos2[2]
    return -1
  elseif a:pos1[2] > a:pos2[2]
    return 1
  else
    return 0
  endif
endfunction
function! s:set_pos(beginmark, endmark, motion_wiseness)
  let pos1 = getpos(a:beginmark)
  let pos2 = getpos(a:endmark)
  let info = s:info
  if info.invoke_mode =~ 'v'
    if &selection == 'exclusive' " exclusive needs special treatment
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
    let info['begin'] = pos1
    let info['end'] = pos2
    let info['End'] = pos2
    call setpos("'[", pos1)
    call setpos("']", pos2)
    let empty = 0
  else
    " Whenever 'operatorfunc' is called, '[ is always placed before '] even if
    " a backward motion is given to g@.  But there is the only one exception.
    " If an empty region is given to g@, '[ and '] are set to the same line, but
    " '[ is placed after '].
    " see https://github.com/kana/vim-operator-replace/issues/2
    let empty = pos1[1] == pos2[1] && pos1[2] > pos2[2]
    let info['begin'] = pos1
    let info['End'] = pos2
    if !empty
      let info['end'] = pos2
    endif
  endif
  if empty
    let dir = 'empty'
  else
    let compare1 = s:compare_pos(info.begin, info.curpos, a:motion_wiseness)
    let compare2 = s:compare_pos(info.curpos, info.End, a:motion_wiseness)
    if compare1 == 0
      let dir = compare2 == 0 ? 'Enclose' : 'forward'
    elseif compare1 == -1
      let dir = compare2 == 0? 'backward' : (compare2 == -1? 'enclose': 'Backward')
    else
      let dir = 'Forward'
    endif
    if a:motion_wiseness == 'line' || dir =~ '^[bf]' " linewise does not have backward and forward
      let dir = 'enclose'
    endif
  endif
  let s:info['motion_wiseness'] = a:motion_wiseness
  let s:info['motion_direction'] = dir
endfunction

" invoke_mode: the mode the mapping is invoked, (whether it is imap, omap...)
" define_mode: the mode the mapping is defined, nNvViIoO
function! s:init_info(callback, invoke_mode, define_mode, extra, hidden)
  " hidden is overwritten
  let s:meta = copy(a:hidden)
  let s:meta['virtualedit'] = &virtualedit
  let s:meta['callback'] = function(a:callback)
  " extra overwrites info
  let info = {
        \ 'curpos': getcurpos(),
        \ 'length': len(getline('.')),
        \ 'count': v:count,
        \ 'count1': v:count1,
        \ 'register': v:register,
        \ 'invoke_mode': a:invoke_mode,
        \ 'define_mode': a:define_mode,
        \ 'buf': bufnr('%'),
        \ }
  call extend(info, a:extra)
  let s:info = info
endfunction

function! s:adjust_cursor()
  let info = s:info
  if info.motion_direction =~? '^back'
    let line = info.end[1]
    let change = 'begin'
  elseif info.motion_direction =~? '^for'
    let line = info.begin[1]
    let change = 'end'
  else  " enclose or empty
    let line = info.curpos[1]
    let change = ''
  endif
  let change = get(info, 'change_at', change)
  if change == 'begin'
    let col = info.curpos[2] + len(getline(line)) - info.length
  elseif change == 'both'
    let col = info.curpos[2] + (len(getline(line)) - info.length)/2
  else
    let col = info.curpos[2]
  endif
  return [0, line, col, 0]
endfunction
function! s:get(key)
  let key = a:key
  if !has_key(s:info, key)
    return []
  endif
  let rv = s:info[key]
  let mode = s:info.invoke_mode
  if type(rv) != v:t_dict
    return [rv]
  elseif has_key(rv, mode)
    return [rv[mode]]
  elseif has_key(rv, '_') " default
    return [rv['_']]
  else
    return []
  endif
endfunction
function! s:post_process()
  let info = s:info
  let cursor = s:get('cursor')
  if !empty(cursor)
    let cursor = cursor[0]
    if type(cursor) == v:t_string
      if cursor == 'Curpos'
        let pos = info.curpos
      elseif cursor == 'curpos'
        let pos = s:adjust_cursor()
      else
        let pos = getpos(cursor)
      endif
    elseif type(cursor) == v:t_list
      let pos = cursor
    endif
    call setpos('.', pos)
  endif
  let shift = s:get('shift')
  if !empty(shift)
    let [l, c] = shift[0]
    let curpos = getpos('.')
    let curpos[1] += l
    let curpos[2] += c
    call setpos('.', curpos)
  endif
endfunction
function! operator_api#operatorfunc(motion_wiseness) abort
  let l:Func = s:meta.callback
  call s:set_pos("'[", "']", a:motion_wiseness)
  try
    call l:Func(s:info)
    call s:post_process()
  catch
    Throw 'operator nmap'
  finally
    let &virtualedit = s:meta.virtualedit
    if s:info.define_mode == 'I'
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
" In operator-pending mode, this count can be cancelled by entering :normal
function! operator_api#_nmap(callback, define_mode, extra, hidden)
  " in both cases, s:info.register == v:register
  " s:info.count1 is the count entered before operator
  " v:count1 is for the motion depending on whether the count is propagated
  " from the op. So do not use it for the op
  set operatorfunc=operator_api#operatorfunc
  call s:init_info(a:callback, 'n', a:define_mode, a:extra, a:hidden)
  let cancel = a:define_mode == 'n' ? '' : printf("\<esc>".'"%s', s:info.register)
  return cancel . 'g@'
endfunction
function! operator_api#_imap(callback, define_mode, extra, hidden)
  " not register and not count can be entered for the op
  " the motion can have a count
  try
    call s:init_info(a:callback, 'i', a:define_mode, a:extra, a:hidden)
    set operatorfunc=operator_api#operatorfunc
    let &virtualedit = 'onemore'
    return "\<c-o>g@"
  catch
    Throw 'operator imap'
  endtry
endfunction
function! operator_api#_omap(callback, define_mode, extra, hidden)
  let samemap = v:operator == 'g@'
        \  && &operatorfunc == 'operator_api#operatorfunc'
        \  && s:meta['callback'] == function(a:callback)
        \  && (s:meta['callback'] != function('operator_api#_vmap_wrapper') ||
        \  s:meta['vmapto'] == get(a:hidden, 'vmapto', ''))
  " in both cases, s:info.register == v:register
  " s:info.count1 is the count entered before operator
  " v:count1 is for the motion depending on whether the count is propagated
  " from the op. So do not use it for the op
  if !samemap
    return "\<esc>"
  elseif v:count1 == 1 || a:define_mode == 'o'
    return '_'
  else
    " use normal to cancel make the count already typed ineffective
    return printf(":normal! %d-\<cr>", v:count1 - 1)
  endif
endfunction
function! operator_api#_vmap(callback, define_mode, extra, hidden)
  set operatorfunc=operator_api#operatorfunc
  call s:init_info(a:callback, 'v', a:define_mode, a:extra, a:hidden)
  " register and count should be obtained from s:info, not v:register and
  " v:count. When the motion is entered, the register cannot be accessed, the
  " v:count is for the motion instead of the operator, since we use :normal
  " here
  "
  " In both cases, s:info.count1 is the count entered for the op.
  if a:define_mode == 'V'
    " In this case, v:count1 == s:info.count1
    let rv = printf(":\<cr>" . '"%sg@:normal! `<%dv' . "\<cr>", s:info.register, s:info.count1)
  else
    " In this case, v:count1 == 1 alway
    let count = s:info.count? string(s:info.count1) : ''
    let rv = printf(":\<cr>" . '"%s%sg@:normal! gv'  . "\<cr>", s:info.register, count)
  endif
  return rv
endfunction

function! s:define(keyseq, Callback, extra, hidden, mode, define_mode)
  let template = '%snoremap <silent> <expr> %s operator_api#_%smap(%s, %s, %s, %s)'
  let command = printf(template, a:mode, a:keyseq, a:mode,
        \  string(a:Callback), string(a:define_mode), a:extra, a:hidden)
  exe command
endfunction

" optional: modes (default "nvo")
" extra_options (a dict to passed to info)
function! operator_api#define(keyseq, callback, ...) abort
  let keyseq = a:keyseq
  if type(a:callback) != v:t_string && type(a:callback) == v:t_func
    Throw printf('define operator %s failed: callback %s is not a function', a:keyseq, a:callback)
  endif
  try
    let modes = get(a:000, 0, 'nvo')
    let extra_options = get(a:000, 1, {})
    let hidden_options = get(a:000, 2, {})
    let l:Define = {mode, define_mode -> s:define(a:keyseq, a:callback,
          \  extra_options, hidden_options, mode, define_mode)}
    if eval(string(extra_options)) != extra_options
      Throw 'extra_options cannot be used'
    endif
    if modes =~ '[nN]'
      "if propagate_count, count for nmap is multiplied by count for omap to
      "define motion
      "otherwise, count for nmap is handled by op and count for omap is
      "handled by motion
      let define_mode = modes =~ 'n'? 'n': 'N'
      call l:Define('n', define_mode)
    endif
    if modes =~ '[vV]'
      "if propagate_count, count for vmap is to redefine the text to be
      "operated on, so 3xx will operator an area that is 3 times as largs as
      "the selected region. The predefined operators like d and y behaves as
      "modes == 'v', and the count for 'v' is discarded
      let define_mode = modes =~ 'v'? 'v': 'V'
      call l:Define('v', define_mode)
    endif
    if modes =~ '[iI]'
      " count in i mode always affects motion
      let define_mode = modes =~ 'i'? 'i': 'I'
      call l:Define('i', define_mode)
    endif
    if modes =~ '[oO]'
      " count in o mode always affects motion
      " mode O select n lines backward
      let define_mode = modes =~ 'o'? 'o': 'O'
      call l:Define('o', define_mode)
    endif
  catch
    Throw printf('define operator %s failed', a:keyseq)
  endtry
endfunction

function! operator_api#_vmap_wrapper(info)
  let remap = s:meta['remap']
  let mapto = s:meta['vmapto']
  if a:info.define_mode == 'N' || a:info.define_mode == 'v'
    let count = string(a:info.count1)
  else
    let count = ''
  endif
  call operator_api#visual_select(count . mapto, remap)
endfunction
function! operator_api#from_vmap(keyseq, mapto, ...) abort
  let modes = get(a:000, 0, 'nvo')
  let remap = get(a:000, 1, 1)
  let extra = copy(get(a:000, 2, {}))
  let hidden = copy(get(a:000, 3, {}))
  call extend(hidden, {'vmapto': a:mapto, 'remap': remap})
  let args = [a:keyseq, 'operator_api#_vmap_wrapper', modes, extra, hidden]
  call call('operator_api#define', args)
endfunction

" other helper functions
function! operator_api#default_map(name)
  return '<Plug>(operator-api-' . a:name . ')'
endfunction
function! operator_api#default_callback(info)
  echo v:register v:count1 v:count a:info
endfunction
call operator_api#define(';o', 'operator_api#default_callback', 'nvio', {'type': 'o'})
call operator_api#define(';O', 'operator_api#default_callback', 'NVIO', {'type': 'O'})

function! operator_api#selection()
  if s:info.motion_direction == 'empty'
    return []
  endif
  let [l1, c1] = s:info.begin[1:2]
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
    Throw 'unknown mode: ' . mode
  endif
  return lines
endfunction

function! operator_api#deletion_moves_cursor()
  if s:info.motion_direction == 'empty'
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

" optional:
" 1. the normal mode keys to send after entering visual
function! operator_api#visual_select(...) abort
  let keystrokes = get(a:000, 0, '')
  let remap = get(a:000, 1, 0)
  let motion_wiseness = s:info['motion_wiseness']
  let motion_direction = s:info['motion_direction']
  if motion_direction == 'empty' && motion_wiseness != 'line'
    call setpos("'<", [0, 0, 0, 0])
    call setpos("'>", [0, 0, 0, 0])
    Throw 'empty region in v-char/v-block mode is not allowed'
  else
    let bang = remap? '' : '!'
    let vmode = s:visual_mode[motion_wiseness]
    exe printf('normal%s `[%s`]%s', bang, vmode, keystrokes)
  endif
  return
endfunction

"""""""""""" Examples

"call operator_api#from_vmap(';>', '>', 'NovI', 0)
"call operator_api#from_vmap(';<', '<', 'NovI', 0)
"call operator_api#from_vmap('<f9>', '<Plug>NERDCommenterToggle', 'novi')

" __END__  "{{{1
" vim: foldmethod=marker
