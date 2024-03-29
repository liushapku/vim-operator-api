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
function! s:set_pos(pos_begin, pos_end, curpos, motion_wiseness)
  let s:info['curpos'] = a:curpos
  let s:info['length'] = len(getline('.'))
  let s:info['buf'] = bufnr('%')
  let pos1 = a:pos_begin
  let pos2 = a:pos_end
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
    if !info['repeat']  " we need to save info for repeating '.'
      let info['visual_repeat'] = {'nrow': pos2[1] - pos1[1]}
      if a:motion_wiseness == 'char'
        let info['visual_repeat']['nchar'] = pos2[2]
      elseif a:motion_wiseness == 'block'
        let info['visual_repeat']['ncol'] = pos2[2] - pos1[2]
      endif
    endif
  else
    " Whenever 'opfunc' is called, '[ is always placed before '] even if
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
"
" this is set when _[nvio]map is called
" some other info is injected by s:set_pos when the opfunc is called
function! s:init_info(keyseq, callback_name, invoke_mode, define_mode, extra)
  let info = {
        \ 'repeat': 0,
        \ 'key': a:keyseq,
        \ 'virtualedit': &virtualedit,
        \ 'callback': a:callback_name,
        \ 'count': v:count,
        \ 'count1': v:count1,
        \ 'register': v:register,
        \ 'invoke_mode': a:invoke_mode,
        \ 'define_mode': a:define_mode,
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
fu! s:get_repeat_visual_pos()
  " don't know why getcurpos() will return the curpos when the last v mode op
  " is invoked. instead of the correct curpos (curpos when the "." is typed)
  " so we saved the correct curpos in s:info before "." is typed
  " in s:record_count
  let curpos = s:info['curpos']
  let motion = s:info['motion_wiseness']
  let vr = s:info['visual_repeat']
  let lastline = line('$')
  if motion == 'line'  " use the same number of rows
    let pos1 = copy(s:info['begin'])
    let pos1[1] = curpos[1]
    let pos2 = copy(pos1)
    let pos2[1] += vr['nrow']
    if pos2[1] > lastline
      let pos2[1] = lastline
    endif
  elseif motion == 'block' " use the same number of rows and cols
    let pos1 = curpos
    let pos2 = copy(curpos)
    let pos2[1] += vr['nrow']
    let pos2[2] += vr['ncol']
    if pos2[1] > lastline
      let pos2[1] = lastline
    endif
  else
    let pos1 = curpos
    let pos2 = copy(curpos)
    " use the same number of rows. 1st row starts from curpos
    " last row uses same number of chars as last selection
    let pos2[1] += vr['nrow']
    let pos2[2] = vr['nchar']
    if pos2[1] > lastline
      let pos2[1] = lastline
    endif
    let lastcol = len(getline(pos2[1]))
    if pos2[2] > lastcol
      let pos2[2] = lastcol
    endif
  endif
  return [pos1, pos2]
endfu
" used to set &opfunc
function! operator_api#_opfunc(motion_wiseness) abort
  " in all modes, when opfunc is invoked, '[ and '] depicts the start and end
  " of selection. Only when the selection is empty, '] is place before '[ by
  " one char.
  " ONLY ONE EXCPETION: when repeating a visual mode op, not any of
  " '[, '], '<, '> is set. The pos should be set according to rule of `:h
  " visual-repeat`
  let info = s:info
  " Log getpos("'[") getpos("']") getpos("'<") getpos("'>")
  " Log 'before setting' info
  if info['repeat'] && info['invoke_mode'] == 'v'
    let [pos1, pos2] = s:get_repeat_visual_pos()
    let curpos = s:info['curpos'] " this is set by s:record_count.
          " don't know why when repeating visual mode op, the getcurpos()
          " returns the pos when entering last op
  else
    let pos1 = getpos("'[")
    let pos2 = getpos("']")
    let curpos = getcurpos()
  endif
  call s:set_pos(pos1, pos2, curpos, a:motion_wiseness)
  " Log 'after setting' info
  let callback_name = info['callback']
  let all_callbacks = string(s:callback_map)
  let l:Func = s:callback_map[callback_name]
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
  call s:set_repeat(s:info['define_mode'])
  let s:info['repeat'] = s:info['repeat'] + 1
endfunction

" for repeat#set:
"
" g:repeat_count is the second parameter of repeat#set, if provided, or set to v:count when typing op map
" the count when doing repeat is determined by (used by repeat#run(n)):
" 0. repeat#run is only done when g:repeat_tick is b:changedtick
" 1. if g:repeat_count is -1:  ''
" 2. elseif repeat it self has count (like <count>.): this new count
"    elseif g:repeate_count is 0: ''
"    else g:repeate_count
" Note the following autocmd in repeat
" augroup repeatPlugin
"     autocmd!
"     autocmd BufLeave,BufWritePre,BufReadPre * let g:repeat_tick = (g:repeat_tick == b:changedtick || g:repeat_tick == 0) ? 0 : -1
"     autocmd BufEnter,BufWritePost * if g:repeat_tick == 0|let g:repeat_tick = b:changedtick|endif
" augroup END
fu! s:set_repeat(define_mode)
  if (&rtp =~ 'vim-repeat')
    let feed = "\<Plug>(operator-api-repeat)" . get(s:info, 'repeat_feed', '')
    if a:define_mode =~ "[NVIO]"
      call repeat#set("\<Plug>(operator-api-suppress-count)".feed , s:info['count'])
    else
      call repeat#set("\<Plug>(operator-api-propagate-count)".feed, s:info['count'])
    endif
  endif
endfu

" helpful for repeat#set to steal the count to not be propagated to motion
" this count is supplied by repeat#run
fu! s:record_count(propagate, count, count1)
  " when repeating last visual mode op, the getcurpos() returns the curpos when
  " entering the last visual mode op, instead of the current pos when typing "."
  " so we need to save the current pos before typing "."
  let s:info['curpos'] = getcurpos()
  let s:info['count'] = a:count
  let s:info['count1'] = a:count1
  let rv = a:propagate? "" : "\<esc>"
  return rv
endfu
nnoremap <silent> <expr> <Plug>(operator-api-propagate-count) <SID>record_count(1, v:count, v:count1)
nnoremap <silent> <expr> <Plug>(operator-api-suppress-count) <SID>record_count(0, v:count, v:count1)
nnoremap <silent> <Plug>(operator-api-repeat) .

fu! operator_api#info()
  return s:info
endfu

" because we are using <expr> mapping, the count inserted is still in the
" typeahead buffer waiting to be processed
" to cancel this count, use "@_" in normal/visual mode
" In operator-pending mode, this count can be cancelled by entering :normal
"
" Maybe: using n for the count to be propagated
" using N for the count not to be propagated
function! operator_api#_nmap(keyseq, callback_name, define_mode, extra)
  " in both cases, s:info.register == v:register
  " s:info.count1 is the count entered before operator
  " v:count1 is for the motion depending on whether the count is propagated
  " from the op. So do not use it for the op
  "
  call s:init_info(a:keyseq, a:callback_name, 'n', a:define_mode, a:extra)
  set opfunc=operator_api#_opfunc
  " if N mode: then cancel the count by esc
  let cancel = a:define_mode == 'n' ? '' : printf("\<esc>".'"%s', s:info.register)
  return cancel . 'g@'
endfunction
function! operator_api#_imap_restore()
  let &virtualedit = s:info.virtualedit
  let maparg = s:info.esc_maparg
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
function! operator_api#_imap(keyseq, callback_name, define_mode, extra)
  " not register and not count can be entered for the op
  " the motion can have a count
  try
    call s:init_info(a:keyseq, a:callback_name, 'i', a:define_mode, a:extra)
    set opfunc=operator_api#_opfunc
    let &virtualedit = 'onemore'
    " if operator is cancelled, we need to restore virtualedit
    let s:info.esc_maparg = maparg('<esc>', 'o', 0, 1)
    onoremap <buffer> <expr> <esc> operator_api#_imap_restore()
    return "\<c-o>g@"
  catch
    Throw 'operator imap'
  endtry
endfunction
" omap is operator pending mode: when the motion is the same as op we do op in
" current line
function! operator_api#_omap(keyseq, callback_name, define_mode, extra)
  let Callback = s:callback_map[a:callback_name]
  let issamemap = v:operator == 'g@'
        \  && &opfunc == 'operator_api#_opfunc'
        \  && s:info['callback'] == a:callback_name
        \  && (a:callback_name != 'operator_api#_vmap_wrapper' ||
        \  s:info['vmapto'] == get(a:extra, 'vmapto', ''))
  " in both cases, s:info.register == v:register
  " s:info.count1 is the count entered before operator
  " v:count1 is for the motion depending on whether the count is propagated
  " from the op. So do not use it for the op
  if !issamemap
    return "\<esc>"
  elseif v:count1 == 1 || a:define_mode == 'o'
    return '_'
  else
    " use normal to cancel the count, which makes the count already typed ineffective
    return printf(":normal! %d-\<cr>", v:count1 - 1)
  endif
endfunction

function! operator_api#_vmap(keyseq, callback_name, define_mode, extra)
  call s:init_info(a:keyseq, a:callback_name, 'v', a:define_mode, a:extra)
  set opfunc=operator_api#_opfunc
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
  let template = '%snoremap %s <silent> <expr> %s operator_api#_%smap(%s, %s, %s, %s)'
  let command = printf(template, a:mode, buffer, a:keyseq, a:mode,
        \  string(a:keyseq), string(callback_name), string(a:define_mode), a:extra)
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
"     which stores the infomation about the motion (help_info, s:info_desc)
"       the map. After each invokation, either using the map or, using
"       "."/"g@" again, it increases by 1
"       - 'repeat': when using the map directly, set to 0. After each
"       invokation (using map directly, or repeat '.', or 'g@' directly), it is
"       increased by one. So repeat !=0 means repeating
"       - 'repeat_feed': [out], user can set this in the callback to be feed to when
"       using repeat
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
"             as text. Comparing to i, mode I will put the cursor after the
"             text changed. After the operation, will stay in insert mode
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
  let remap = a:info['remap']
  let mapto = a:info['vmapto']
  if a:info.define_mode =~ '[Nv]'
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
  call operator_api#visual_select('"_'. "c\<c-r>=operator_api#_last_replace()\<cr>")
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
  call extend(extra, {'vmapto': a:mapto, 'remap': remap})  " add two options for meta
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
" optional:
"   sep: if not provided, returns a list. otherwise, join with sep
function! operator_api#selection(...)
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
  if a:0 > 0
    return join(lines, a:1)
  else
    return lines
  endif
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
