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
echo "Got ${#exp_match[*]} matches of regex #$exp_index from $exp_matchid"
printf -- "---\n%s\n" "${exp_match[@]}"
echo "Got ${#exp_match[*]} matches of regex #$exp_index from $exp_matchid"
exp_expect "\n([^\n]*┋)" || die "Expect error $exp_index"
echo "Got ${#exp_match[*]} matches of regex #$exp_index from $exp_matchid"
printf -- "---\n%s\n" "${exp_match[@]}"
exp_internal off
exp_close

exp_spawn bash -c 'echo "This is a test of single '\'' double \" curly { and \$woot! and \t escapes"'
exp_expect && echo "${exp_match[0]}"
exp_close

# the default exp_spawnid is now tty
exp_send "\nAnd your name is? "
if exp_expect -t10 "(?in)^\s*([a-z])\s*$" "(?in)([a-z]).*([a-z])"; then
    echo "Got ${#exp_match[*]} matches of regex #$exp_index from $exp_matchid"
    if (($exp_index)); then
        exp_send -d.05 "Hi, ${exp_match[1]^}-mumble-${exp_match[2]}!\n"
    else
        exp_send -d.05 "Hi, ${exp_match[1]^}!\n"
    fi
else
    exp_send -d.05 "\nToo slow! ($exp_index)\n"
fi
exp_expect -i tty -t0 || true

exp_spawn cat -sn
echo "Send lines to cat -sn..."
while true; do
    exp_expect -t60 -b -i tty -i $exp_spawnid || break
    exp_send -i $([[ $exp_matchid == tty ]] && echo $exp_spawnid || echo tty) -b ${exp_match[0]}
done
echo Bye!
