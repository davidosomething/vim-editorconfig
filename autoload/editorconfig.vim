scriptencoding utf-8

let s:save_cpo = &cpo
set cpo&vim

let s:editorconfig = '.editorconfig'

let s:scriptdir = expand('<sfile>:p:r')

" {{{1 Interfaces

" >>> call editorconfig#load()
"
function! editorconfig#load() abort
  augroup plugin-editorconfig-local
    autocmd!
  augroup END
  let l:filepath = expand('%:p')
  let l:rule = s:scan(fnamemodify(l:filepath, ':h'))
  let l:props = s:filter_matched(l:rule, l:filepath)
  if empty(l:props) | return | endif
  let b:editorconfig = l:props
  call s:apply(l:props)
endfunction

function! editorconfig#omnifunc(findstart, base) abort
  if a:findstart
    let l:pos = match(getline('.'), '\%' . col('.') . 'c\k\+\zs\s*=')
    return l:pos+1
  else
    return filter(sort(s:properties()), 'stridx(v:val, a:base) == 0')
  endif
endfunction

" {{{1 Inner functions

" >>> let [s:pattern, s:config] = s:scan(expand('%:p:h'))[0]
" >>> echo s:pattern
" *.vim
" >>> echo s:config.insert_final_newline s:config.indent_style s:config.indent_size
" true space 2

function! s:scan(path) abort "{{{
  let l:editorconfig = findfile(s:editorconfig, fnameescape(a:path) . ';')
  if empty(l:editorconfig) || !filereadable(l:editorconfig) || a:path is# fnamemodify(a:path, ':h')
    return []
  endif
  let l:base_path = fnamemodify(l:editorconfig, ':p:h')
  let [l:is_root, l:_] = s:parse(s:trim(readfile(l:editorconfig)))
  if l:is_root
    call s:set_cwd(l:base_path)
    return l:_
  endif
  return l:_ + s:scan(fnamemodify(l:base_path, ':h'))
endfunction "}}}

" Parse lines into rule lists
" >>> let [s:is_root, s:lists] = s:parse(['root = false', '[*]', 'indent_size = 2'])
" >>> echo s:is_root
" 0
" >>> echo s:lists[0][0]
" *
" >>> echo s:lists[0][1]
" {'indent_size': 2}
" >>> echo s:parse(['root = false', '[*', 'indent_size = 2'])
" Vim(echoerr):editorconfig: failed to parse [*

function! s:parse(lines) abort "{{{
  let [l:unparsed, l:is_root] = s:parse_properties(a:lines)
  let l:_ = []
  while len(l:unparsed) > 0
    let [l:unparsed, l:pattern] = s:parse_pattern(l:unparsed)
    let [l:unparsed, l:properties] = s:parse_properties(l:unparsed)
    let l:_ += [[l:pattern, l:properties]]
  endwhile
  return [get(l:is_root, 'root', 'false') ==# 'true', l:_]
endfunction "}}}

" Parse file glob pattern
" >>> echo s:parse_pattern([])
" [[], '']
" >>> echo s:parse_pattern(['[*.vim]', 'abc'])
" [['abc'], '*.vim']
" >>> echo s:parse_pattern(['[]', ''])
" Vim(echoerr):editorconfig: failed to parse []

function! s:parse_pattern(lines) abort "{{{
  if !len(a:lines) | return [[], ''] | endif
  let l:m = matchstr(a:lines[0], '^\[\zs.\+\ze\]$')
  if !empty(l:m)
    return [a:lines[1 :], l:m]
  else
    if get(g:, 'editorconfig_verbose', 0)
      echoerr printf('editorconfig: failed to parse %s', a:lines[0])
    endif
    return [[], '']
  endif
endfunction "}}}

" Skip pattern fields
" >>> echo s:parse_properties(['[*.vim]', 'abc'])
" [['[*.vim]', 'abc'], {}]
"
" Parse property and store the fields as dictionary
" >>> echo s:parse_properties(['indent_size=2', '[*]'])
" [['[*]'], {'indent_size': 2}]

function! s:parse_properties(lines) abort "{{{
  let l:_ = {}
  if !len(a:lines) | return [[], l:_] | endif
  for l:i in range(len(a:lines))

    let l:line = a:lines[l:i]

    " Parse comments
    let l:m = matchstr(l:line, '^#')
    if !empty(l:m)
      return [[], {}]
    endif

    " Parse file formats
    let l:m = matchstr(l:line, '^\[\zs.\+\ze\]$')
    if !empty(l:m)
      return [a:lines[l:i :], l:_]
    endif

    " Parse properties
    let l:splitted = split(l:line, '\s*=\s*')
    if len(l:splitted) < 2
      if get(g:, 'editorconfig_verbose', 0)
        echoerr printf('editorconfig: failed to parse %s on line %d', l:line, l:i)
      endif
      return [[], {}]
    endif
    let [l:key, l:val] = l:splitted
    let l:_[l:key] = s:eval(l:val)

  endfor
  return [a:lines[l:i+1 :], l:_]
endfunction "}}}

" >>> echo s:eval('2')
" 2
" >>> echo s:eval('true')
" true

function! s:eval(val) abort "{{{
  return type(a:val) == type('') && a:val =~# '^\d\+$' ? eval(a:val) : a:val
endfunction "}}}

function! s:properties() abort "{{{
  return map(s:globpath(s:scriptdir, '*.vim'), "fnamemodify(v:val, ':t:r')")
endfunction "}}}

function! s:globpath(path, expr) abort "{{{
  return has('patch-7.4.279') ? globpath(a:path, a:expr, 0, 1) : split(globpath(a:path, a:expr, 1))
endfunction "}}}

" >>> echo s:trim(['# ', 'foo', '', 'bar'])
" ['foo', 'bar']

function! s:trim(lines) abort "{{{
  return filter(map(a:lines, 's:remove_comment(v:val)'), '!empty(v:val)')
endfunction "}}}

" >>> echo s:remove_comment('# foo')
"
" >>> echo s:remove_comment('bar')
" bar

function! s:remove_comment(line) abort "{{{
  let l:pos = match(a:line, '[;#].\+')
  return l:pos == -1 ? a:line : l:pos == 0 ? '' : a:line[: l:pos-1]
endfunction "}}}

function! s:set_cwd(dir) abort "{{{
  if g:editorconfig_root_chdir
    lcd `=a:dir`
  endif
endfunction "}}}

function! s:apply(property) abort "{{{
  for [l:key, l:val] in items(a:property)
    try
      call editorconfig#{tolower(l:key)}#execute(l:val)
    catch /^Vim\%((\a\+)\)\=:E117/
      echohl WarningMsg | echomsg 'editorconfig: Unsupported property:' l:key | echohl NONE
    endtry
  endfor
endfunction "}}}

function! s:filter_matched(rule, path) abort "{{{
  let l:_ = {}
  call map(filter(copy(a:rule), 'a:path =~ s:regexp(v:val[0])'), "extend(l:_, v:val[1], 'keep')")
  return l:_
endfunction "}}}

function! s:regexp(pattern) abort "{{{
  let l:pattern = escape(a:pattern, '.\')
  for l:rule in s:regexp_rules
    let l:pattern = substitute(l:pattern, l:rule[0], l:rule[1], 'g')
  endfor
  return '\<'. l:pattern . '$'
endfunction "}}}
let s:regexp_rules =
      \ [ ['\[!', '[^']
      \ , ['{\(\f\+\),\(\f\+\)}' ,'\\%(\1\\|\2\\)']
      \ , ['\*\{2}', '.\\{}']
      \ , ['\(\.\)\@<!\*', '[^\\/]\\{}']]
" 1}}}

let &cpo = s:save_cpo
unlet s:save_cpo
