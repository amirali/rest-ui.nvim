if exists("b:current_syntax")
  finish
endif

let s:cpo_save = &cpo
set cpo&vim

syn match RestUIAll /.*/
syn match RestUIFiles /^  \- .*/
syn match RestUICollections /.*[\-\+]$/
syn match RestUIHelps /^ \*.*/

hi def link RestUIFiles String
hi def link RestUIHelps Comment
hi def link RestUICollections Function
hi def link RestUIAll Comment

let b:current_syntax = "restui"

let &cpo = s:cpo_save
unlet s:cpo_save
