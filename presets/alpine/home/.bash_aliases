alias HEAD='curl -I'
alias haed=head
alias diff-y='___diffy() { unset -f ___diffy ; if [ -z "$PAGER" ] ; then PAGER='less' ; fi ; diff -y -W `tput cols` "$1" "$2" | "$PAGER" ; } ; ___diffy'
alias +++='cd; history -c; exit'
