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
"  - n, N uses nmap
"  - v, V uses vmap
"  - i, I uses imap
"  - o, O uses omap
function! s:init_info(callback_name, invoke_mode, define_mode, extra)
  let s:meta = {}
  let s:meta['virtualedit'] = &virtualedit
  let s:meta['callback'] = a:callback_name
  let x = s:meta.callback
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
    let change = 'before'
  elseif info.motion_direction =~? '^for'
    let line = info.begin[1]
    let change = 'after'
  else  " enclose or empty
    let line = info.curpos[1]
    let change = ''
  endif
  let change = get(info, 'change_pos', change)
  if change == 'before'
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
" used to set &opfunc
function! operator_api#_operatorfunc(motion_wiseness) abort
  let callback_name = s:meta['callback']
  let all_callbacks = string(s:callback_map)
  let l:Func = s:callback_map[callback_name]
  call s:set_pos("'[", "']", a:motion_wiseness)
  try
    call l:Func(s:info)
    call s:post_process()
  catch
    Throw 'operator nmap'
  finally
    if s:info.invoke_mode == 'i'
      call operator_api#_imap_restore()
    endif
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
"
" Maybe: using n for the count to be propagated
" using N for the count not to be propagated
function! operator_api#_nmap(callback_name, define_mode, extra)
  " in both cases, s:info.register == v:register
  " s:info.count1 is the count entered before operator
  " v:count1 is for the motion depending on whether the count is propagated
  " from the op. So do not use it for the op
  "
  call s:init_info(a:callback_name, 'n', a:define_mode, a:extra)
  set operatorfunc=operator_api#_operatorfunc
  " if N mode: then cancel the count by esc
  let cancel = a:define_mode == 'n' ? '' : printf("\<esc>".'"%s', s:info.register)
  return cancel . 'g@'
endfunction
function! operator_api#_imap_restore()
  let &virtualedit = s:meta.virtualedit
  let maparg = s:meta.esc_maparg
  if get(maparg, 'buffer', 0)
    exe (maparg.noremap ? 'onoremap ' : 'omap ') .
         \ (maparg.buffer ? '<buffer> ' : '') .
         \ (maparg.expr   ? '<expr> '   : '') .
         \ (maparg.nowait ? '<nowait> ' : '') .
         \ (maparg.silent ? '<silent> ' : '') .
         \ maparg.lhs . ' ' .
         \ maparg.rhs
  else
    ounmap <buffer> <esc>
  endif
  return "\<esc>"
endfunction
" imap is implemented using omap, which is implemented using nmap
function! operator_api#_imap(callback_name, define_mode, extra)
  " not register and not count can be entered for the op
  " the motion can have a count
  try
    call s:init_info(a:callback_name, 'i', a:define_mode, a:extra)
    set operatorfunc=operator_api#_operatorfunc
    let &virtualedit = 'onemore'
    " if operator is cancelled, we need to restore virtualedit
    let s:meta.esc_maparg = maparg('<esc>', 'o', 0, 1)
    onoremap <buffer> <expr> <esc> operator_api#_imap_restore()
    return "\<c-o>g@"
  catch
    Throw 'operator imap'
  endtry
endfunction
" omap is implemented using nmap
function! operator_api#_omap(callback_name, define_mode, extra)
  let callback = s:callback_map[a:callback_name]
  let issamemap = v:operator == 'g@'
        \  && &operatorfunc == 'operator_api#_operatorfunc'
        \  && s:meta['callback'] == callback
        \  && (s:meta['callback'] != function('operator_api#_vmap_wrapper') ||
        \  s:meta['vmapto'] == get(a:extra, '_vmapto', ''))
  " in both cases, s:info.register == v:register
  " s:info.count1 is the count entered before operator
  " v:count1 is for the motion depending on whether the count is propagated
  " from the op. So do not use it for the op
  if !issamemap
    return "\<esc>"
  elseif v:count1 == 1 || a:define_mode == 'o'
    return '_'
  else
    " use normal to cancel make the count already typed ineffective
    return printf(":normal! %d-\<cr>", v:count1 - 1)
  endif
endfunction

function! operator_api#_vmap(callback_name, define_mode, extra)
  call s:init_info(a:callback_name, 'v', a:define_mode, a:extra)
  set operatorfunc=operator_api#_operatorfunc
  " register and count should be obtained from s:info, not v:register and
  " v:count. When the motion is entered, the register cannot be accessed, the
  " v:count is for the motion instead of the operator, since we use :normal
  " here
  "
  " In both cases, s:info.count1 is the count entered for the op.
  " Maybe: V for propagating the count
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

function! s:func_to_string(func)
  return type(a:func) == v:t_func? string(a:func) : a:func
endfunction
" optinal: dict with keys:
" "buffer": number, map is for <buffer=N>
function! s:define(keyseq, callback, extra, mode, define_mode, buffer)
  let Callback = function(a:callback)
  let callback_name = s:func_to_string(a:callback)
  let s:callback_map[callback_name] = Callback
  let buffer = a:buffer? '<buffer>' : ''
  let template = '%snoremap %s <silent> <expr> %s operator_api#_%smap(%s, %s, %s)'
  let command = printf(template, a:mode, buffer, a:keyseq, a:mode,
        \  string(callback_name), string(a:define_mode), a:extra)
  exe command
endfunction

" function map: name -> callback Funcref
" this is to handle lambdas for which a Funcref cannot be reconstructed from
" its string
" For normal functions, function(string(func)) will still get the Funcref to
" func, but for lambda, function(string(lambda)) will not get the Funcref
let s:callback_map = {}
function! operator_api#_registered_callbacks()
  return s:callback_map
endfunction

" params
"   keyseq: key sequence to be mapped
"   callback: funcref or string name of func
"     this func will be called with info, a dict with the following keys,
"     which stores the infomation about the motion (help_info)
"       - 'buf': the current buffer
"       - 'length': line length of current line
"       - 'invoke_mode': any in 'nvoi'
"       - 'define_mode': any in 'nNvVoOiI'
"           - the lower case letters propagate the count
"             (eg: 2;o3j will select 7 lines, move down 6 lines)
"           - the upper case letters do not propage the count
"             (eg: 2;O3j will select 4 lines, move down 3 lines)
"           - in both cases, info.count will be 3
"           - NOTE: when we do n-op-m-motion:
"             - in v mode, n is replayed after we do visual selected
"             - in V mode, n is dropped
"             - in n/o mode, n*m is applied to motion for selection, afterwards,
"                op does not receive n again
"             - in N/O mode, m is appied to motion for selection, afterwards, we
"                replay n before op
"             - in iI mode, there is not way to insert n, since n will be typed
"             as text. Comparing to i, GUESS: I is able to put the cursor back to the
"             current buffer if the callback moved the cursor out of the
"             current buffer
"
"       - 'count1': v:count1,
"       - 'count': v:count,
"       - 'register': v:register,
"       - 'motion_wiseness': 'char', 'line', 'block'
"       - 'motion_direction': 'enclose', 'Enclose', 'forward', 'Forward',
"                             'backward', 'Backward', or 'empty'
"               - enclose is when text object is used or line mode?
"       - 'begin': getpos of begin of selection
"       - 'end':
"           - when empty selection: key do not exist
"           - otherwise: getpos of end of selection
"       - 'End':   getpos of end of selection
"       - 'curpos': curent cursor position
"       - 'curpos': getcurpos(),
"       - other keys from a:extra are merged with info too, to overwrite
"         the above keys with caution
" optional:
" 0 modes (default "nvo")
" 1 extra_options: a dict to be passed to info, and merged into info dic
" 2 buffer: 0 means no <buffer>, N means <buffer=N>
function! operator_api#define(keyseq, callback, ...) abort
  let keyseq = a:keyseq
  if type(a:callback) != v:t_string && type(a:callback) != v:t_func
    Throw printf('define operator %s failed: callback %s is not a function', a:keyseq, a:callback)
  endif
  let modes = get(a:000, 0, 'nvo')
  let extra_options = get(a:000, 1, {})
  let buffer = get(a:000, 3, 0)
  let l:Define = {mode, define_mode -> s:define(a:keyseq, a:callback,
        \  extra_options, mode, define_mode, buffer)}
  try
    if type(extra_options) != v:t_dict || eval(string(extra_options)) != extra_options
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
    " in N mode, need to replay count since the count is not propagated to
    " motion
    " in v mode, count is not consumed by motion, so we need to keep it
    let count = string(a:info.count1)
  else
    let count = ''
  endif
  if s:info.motion_direction != 'empty'
    let seq = '"' . a:info.register . count . mapto
    call operator_api#visual_select(seq, remap)
  endif
endfunction

function! operator_api#_last_replace()
  return s:_last_replace
endfunction
function! operator_api#_do_replace(newstr)
  let s:_last_replace = a:newstr
  call operator_api#visual_select("c\<c-r>=operator_api#_last_replace()\<cr>")
endfunction

" take a function with signature f(info) -> replace_str
" returns a function with param info, which can be used for
" operator_api#define
function! operator_api#get_replace_ref(Replace_func)
  return {info -> operator_api#_do_replace(function(a:Replace_func)(info))}
endfunction

" If you already have a vmap, using this function to define maps that
" also works in other mode as a operator
"
" parameters:
"   keyseq: key sequence to be mapped: note: should not use "\<>", such as
"   "<cr>" directly
"   mapto:  key sequence in v mode: note need to use "\<>" for key
"   modes:  any combination of 'nNvViIoO'
"   remap:  whether remap is allowed (as in nmap vs nnoremap) default: 1
"   extra:  dict (default {}), following keys has special meaning
"     - 'cursor': 'curpos', 'Curpos'
"     - 'change_pos': 'before', 'after', 'both'
"     which is used to adjust the cursor position
"     MORE DOC NEEDED
"   buffer: 0 means no <buffer>, N means <buffer=N>
function! operator_api#from_vmap(keyseq, mapto, ...) abort
  let modes = get(a:000, 0, 'nvo')
  let remap = get(a:000, 1, 1)
  let extra = copy(get(a:000, 2, {}))
  let buffer = get(a:000, 4, 0)
  call extend(extra, {'_vmapto': a:mapto, '_remap': remap})  " add two options for meta
  let args = [a:keyseq, 'operator_api#_vmap_wrapper', modes, extra, buffer]
  call call('operator_api#define', args)
endfunction

" returns a default map with name
" example:
" call operator_api#define(operator_api#default_map('myop'), 'op_impl', "nov")
function! operator_api#default_map(name)
  return '<Plug>(operator-api-' . a:name . ')'
endfunction
" a simple callback that displays the v:register, v:count1, v:count and s:info
function! operator_api#default_callback(info)
  echo v:register v:count1 v:count getpos("'[") getpos("']") getpos("'<") getpos("'>") a:info
endfunction
" these two default operators simply displays the move's info
call operator_api#define(';o', 'operator_api#default_callback', 'nvio', {'type': 'o'})
call operator_api#define(';O', 'operator_api#default_callback', 'NVIO', {'type': 'O'})

" return the selected text from the motion
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

" returns whether deleting some chars in selection will move the cursor
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

" optional params
" (0): the normal mode keys to send after entering visual
" (1): 1: use "normal", 0: use "normal!"
function! operator_api#visual_select(...) abort
  let keystrokes = get(a:000, 0, '')
  let remap = get(a:000, 1, 0)
  let motion_wiseness = s:info['motion_wiseness']
  let motion_direction = s:info['motion_direction']
  if motion_direction == 'empty' && motion_wiseness != 'line'
    call setpos("'<", [0, 0, 0, 0])
    call setpos("'>", [0, 0, 0, 0])
    let msg = string(s:info)
    Throw 'empty region in v-char/v-block mode is not allowed:' . msg
  else
    let bang = remap? '' : '!'
    let vmode = s:visual_mode[motion_wiseness]
    exe printf('normal%s `[%s`]%s', bang, vmode, keystrokes)
  endif
  return
endfunction


"""""""""""" Examples

" define a function to return the text to be replaced
" fu! ToUpper(info)
"   return toupper(join(operator_api#selection(), "\n"))
" endfu
" call operator_api#define("pp", operator_api#get_replace_ref('Replace333'), "nvio")

"call operator_api#from_vmap(';>', '>', 'NovI', 0)
"call operator_api#from_vmap(';<', '<', 'NovI', 0)
"call operator_api#from_vmap('<f9>', '<Plug>NERDCommenterToggle', 'novi')

" __END__  "{{{1
" vim: foldmethod=marker
