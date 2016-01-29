scriptencoding utf-8

" vimscript {{{1

function! editorconfig#local_vimrc#execute(value) abort
  let l:path = fnamemodify(a:value, ':p')

  if filereadable(l:path)
    source `=path`
  else
    if get(g:, 'editorconfig_verbose', 0)
      echoerr printf('editorconfig: unable to load: vimscript=%s', a:value)
    endif
  endif
endfunction

" 1}}}
