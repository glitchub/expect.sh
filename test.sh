#!/bin/bash -ue
trap 'echo Fail line $LINENO' ERR

die() { echo "$*" >&2; exit 1; }

source expect.sh

# exp_internal on
exp_spawn cat -n
exp_send 'Here'\''s a back\\slash\n'
exp_send <<EOT
WOO This is a test.
   This   is   ONLY   ...
      A ...
          TEST!

Box drawing alignment tests:                                          █
                                                                      ▉
  ╔══╦══╗  ┌──┬──┐  ╭──┬──╮  ╭──┬──╮  ┏━━┳━━┓  ┎┒┏┑   ╷  ╻ ┏┯┓ ┌┰┐    ▊ ╱╲╱╲╳╳╳
  ║┌─╨─┐║  │╔═╧═╗│  │╒═╪═╕│  │╓─╁─╖│  ┃┌─╂─┐┃  ┗╃╄┙  ╶┼╴╺╋╸┠┼┨ ┝╋┥    ▋ ╲╱╲╱╳╳╳
  ║│╲ ╱│║  │║   ║│  ││ │ ││  │║ ┃ ║│  ┃│ ╿ │┃  ┍╅╆┓   ╵  ╹ ┗┷┛ └┸┘    ▌ ╱╲╱╲╳╳╳
  ╠╡ ╳ ╞╣  ├╢   ╟┤  ├┼─┼─┼┤  ├╫─╂─╫┤  ┣┿╾┼╼┿┫  ┕┛┖┚     ┌┄┄┐ ╎ ┏┅┅┓ ┋ ▍ ╲╱╲╱╳╳╳
  ║│╱ ╲│║  │║   ║│  ││ │ ││  │║ ┃ ║│  ┃│ ╽ │┃  ░░▒▒▓▓██ ┊  ┆ ╎ ╏  ┇ ┋ ▎
  ║└─╥─┘║  │╚═╤═╝│  │╘═╪═╛│  │╙─╀─╜│  ┃└─╂─┘┃  ░░▒▒▓▓██ ┊  ┆ ╎ ╏  ┇ ┋ ▏
  ╚══╩══╝  └──┴──┘  ╰──┴──╯  ╰──┴──╯  ┗━━┻━━┛           └╌╌┘ ╎ ┗╍╍┛ ┋  ▁▂▃▄▅▆▇█
EOT
exp_expect "no match" "[ \t]+[0-9][ \t]+((T.*) ONLY).+(T.*T)" ".+" || die "Expect error $exp_index"
echo "Got ${#exp_match[*]} matches from regex #$exp_index"
printf -- "---\n%s\n" "${exp_match[@]}"
exp_expect "\n([^\n]*┋)" || die "Expect error $exp_index"
echo "Got ${#exp_match[*]} matches from regex #$exp_index"
printf -- "---\n%s\n" "${exp_match[@]}"
exp_internal off
exp_close

log=
if [[ $TMPDIR ]]; then log=$TMPDIR/test.sh.log; exp_log $log; fi

exp_spawn bash -c 'echo "This is a test of single '\'' double \" curly { and \$woot! and \t escapes"'
exp_expect && echo "${exp_match[0]}"
exp_close

# the default exp_spawnid is tty
exp_send "\nAnd your name is? "
if exp_expect -t10 "(?in)^\s*([a-z])\s*$" "(?in)([a-z]).*([a-z])"; then
    echo "Got ${#exp_match[*]} matches from regex #$exp_index"
    if (($exp_index)); then
        exp_send "Hi, ${exp_match[1]^}-mumble-${exp_match[2]}!\n"
    else
        exp_send "Hi, ${exp_match[1]^}!\n"
    fi
else
    exp_send "\nToo slow! ($exp_index)\n"
fi

if [[ $log ]]; then
    exp_log
    echo $log contains:
    awk '{print "  " $0 }' $log
    echo >> $log
fi
