# shellcheck shell=bash

# This file is sourced by another bash script to provide expect functionality, see
# https://github.com/glitchub/expect.sh for more details, examples, and the latest code.

# Released by the author into the public domain, do whatever you want with it.

_exp_die() { read c0l _ < <(caller); read c1l _ c1f < <(caller 1); printf "%s: line %s: %s (%s)\n" "$c1f" "$c1l" "$*" "$c0l" >&2; exit 1; }

# true if arg is an int
_exp_is_int() { [[ $* =~ ^(0|[1-9][0-9]*)$ ]]; }

# true if arg is non-zero float
_exp_is_float() { [[ $* =~ ^(([1-9][0-9]*(\.0*)?)|((0*|[1-9][0-9]*)\.0*[1-9][0-9]*))$ ]]; }

# true if arg is alnum
_exp_is_alnum() { [[ $* =~ ^[0-9A-Za-z]+$ ]]; }

# true if arg is (maybe) base64
_exp_is_b64() { [[ $* =~ ^[0-9A-Za-z+/=]+$ ]]; }


# These are used in conjunction with the expect encode/decode proc's defined above to pass literal
# strings between bash and expect without quoting/whitespace issues.
_exp_encode () { $_exp_prog -c 'fconfigure stdin -translation binary; puts -nonewline [binary encode base64 [encoding convertto utf-8 [read stdin]]]; flush stdout'; }
_exp_decode () { $_exp_prog -c 'fconfigure stdout -translation binary; puts -nonewline [encoding convertfrom utf-8 [binary decode base64 [read stdin]]]; flush stdout'; }

# Write given string or stdin to expect coprocess.
# Each line must be a complete tcl expression!
_exp_write() {
    if (($#)); then
        printf "%s\n" "$*"  >&$_exp_stdin || exp_die "coprocess write error"
    else
        cat >&$_exp_stdin || exp_die "coprocess write error"
    fi
}

# Given optional timeout, read a line from expect coprocess to variable $REPLY and return 0 on
# success, 1 if timeout. Default timeout is 60 seconds!
_exp_read() {
    IFS= read -r -t ${1:-60} <&$_exp_stdout
    local xs=$?
    ((xs > 128)) && return 1
    ((!xs)) || _exp_die "coprocess read error"
}

# Initialize and start the expect coprocess. Argument 'trace' will write coprocess IN and OUT to
# stderr.
# shellcheck disable=SC2120
_exp_start() {
    declare -g _exp_stdout _exp_stdin _exp_prog exp_spawnid exp_index exp_match exp_matchid
    [[ ${_exp_prog:-} ]] && _exp_die "expect.sh is already sourced?"
    _exp_prog=$(type -pf expect 2>/dev/null) || { _exp_die "expect.sh requires expect"; }
    exp_index=-3
    exp_match=()
    exp_spawnid="tty"
    exp_matchid="tty"
    local out in script
    if [[ ${1:-} == trace ]]; then
        out='proc out {s} {puts stderr "[clock milliseconds] OUT: $s"; puts $s}'
        in='puts stderr "[clock milliseconds] IN : $line"'
    else
        out='interp alias {} out {} puts'
        in=''
    fi
    # write script to temp pipe
    exec {script}<<EOT
        log_user 0
        set stty_init -echo
        $out
        proc encode {s} {binary encode base64 [encoding convertto utf-8 \$s]}
        proc decode {s} {encoding convertfrom utf-8 [binary decode base64 \$s]}
        proc checkid {s} {if [catch {if {\$s != $::tty_spawn_id} error() {}}] {return \$s} {return "tty"}}
        while {[gets stdin line] >= 0} {$in; eval \$line}
EOT
    # XXX get rid of stdbuf
    coproc _exp_coproc { stdbuf -oL $_exp_prog -f /dev/fd/$script; }
    exec {script}<&- {_exp_stdout}<&"${_exp_coproc[0]}" {_exp_stdin}>&"${_exp_coproc[1]}"
}
_exp_start

# The rest are user functions, see the README.

# exp_spawn [options] [--] program [args...]
exp_spawn() {
    local opt OPTIND size=1000 args
    while getopts ":n:" opt; do case $opt in
        n) size=$OPTARG; _exp_is_int $size && (($size)) || _exp_die "invalid size" ;;
        *) _exp_die "invalid param" ;;
    esac; done
    shift $((OPTIND-1))
    (($#)) || _exp_die "missing program"
    readarray -t args < <(for a in "$@"; do printf "%s" "$a" | _exp_encode; echo; done)
    _exp_write "if [catch {if [spawn -noecho {*}[lmap b64 { ${args[*]} } { binary decode base64 \$b64} ]] {match_max -i \$spawn_id $size; out \$spawn_id} {out {}}}] {puts stderr \"exp_spawn: \$::errorInfo\"; out {}}"
    _exp_read || _exp_die "stalled"
    [[ $REPLY ]] || return 1
    exp_spawnid=$REPLY
}

# exp_close [options]
exp_close() {
    local opt OPTIND spawnid=$exp_spawnid
    while getopts ":i:" opt; do case $opt in
        i) spawnid=$OPTARG ;;
        *) _exp_die "invalid param" ;;
    esac; done
    [[ $spawnid == "tty" ]] && return 0 # refuse successfully
    _exp_is_alnum $spawnid || _exp_die "invalid spawn id"
    _exp_write "if [catch {close -i $spawnid; wait -nowait -i $spawnid}] {puts stderr \"exp_close: \$::errorInfo\"; out 1} {out 0}"
    _exp_read || _exp_die "stalled"
    [[ $spawnid == "$exp_spawnid" ]] && exp_spawnid="tty"
    return $REPLY
}

# exp_send [options] [--] [string]
exp_send() {
    local opt OPTIND spawnid=$exp_spawnid cmd="" delay="" b64=0
    while getopts ":bd:i:" opt; do case $opt in
        b) b64=1 ;;
        d) delay=$OPTARG; _exp_is_float $delay || _exp_die "invalid delay" ;;
        i) spawnid=$OPTARG ;;
        *) _exp_die "invalid param" ;;
    esac; done
    shift $((OPTIND-1))
    [[ $delay ]] && cmd="set send_slow {1 $delay}; "
    _exp_is_alnum $spawnid || _exp_die "invalid spawn id"
    [[ $spawnid == "tty" ]] && spawnid="\$tty_spawn_id"
    cmd+="send -i $spawnid"
    [[ $delay ]] && cmd+=" -s"
    cmd+=" --"
    if ((b64)); then
        (($#)) || _exp_die "missing base64"
        _exp_is_b64 "$*" || "invalid base64"
        cmd+=" [decode $1]"
    elif (($#)); then
        # unescape "\n" etc
        cmd+=" [decode $(printf "%b" "$*" | _exp_encode)]"
    else
        # slurp stdin
        cmd+=" [decode $(_exp_encode)]"
    fi
    _exp_write "if [catch {$cmd}] {puts stderr \"exp_send: \$::errorInfo\"; out 1} {out 0}"
    _exp_read || _exp_die "stalled"
    return $REPLY
}

# exp_expect [options] [--] [regex [...regex]]
exp_expect() {
    local OPTIND opt spawnids=() timeout=2 b64=0
    while getopts ":bi:t:" opt; do case $opt in
        b) b64=1 ;;
        i) spawnids+=("$OPTARG") ;;
        t) timeout=$OPTARG; _exp_is_int $timeout || _exp_die "invalid timeout" ;;
        *) _exp_die "invalid param" ;;
    esac; done
    shift $((OPTIND-1))
    (($#)) || set -- .+
    ((${#spawnids[*]})) || spawnids=("$exp_spawnid")
    local arg index=0 cmd="expect -i [list"
    for arg in "${spawnids[@]}"; do
        _exp_is_alnum "$arg" || _exp_die "invalid spawn id"
        [[ $arg == "tty" ]] && arg="\$tty_spawn_id"
        cmd+=" $arg"
    done
    cmd+="] -timeout $timeout"
    for arg in "$@"; do cmd+=" -regex [decode $(printf "%b" "$arg" | _exp_encode)] {set result $((index++))}"; done
    cmd+=" timeout {set result -1} eof {set result -2}"
    _exp_write <<EOT
        if [catch { \
           array unset expect_out; \
           $cmd; \
           if {\$result >= 0} { \
                set matches [llength [lsearch -all [array names expect_out] *string]]; \
                out "\$result [checkid \$expect_out(spawn_id)] \$matches" ; \
                for {set i 0} {\$i < \$matches} {incr i} {out [encode \$expect_out(\$i,string)]}; \
           } elseif {\$result == -2} { \
                out "\$result [checkid \$expect_out(spawn_id)] 0" ; \
           } else { out "\$result 0 0" } \
        }] { puts stderr "exp_expect: \$::errorInfo"; out -3 }
EOT
    exp_match=()
    _exp_read ${timeout}.5 || _exp_die "stalled"
    local matches m
    # shellcheck disable=SC2034
    read exp_index exp_matchid matches <<<$REPLY
    ((exp_index < 0)) && return 1
    # slurp specified number of matches
    for ((m = 1; m <= matches; m++)); do
        _exp_read .5 || die "missing match $m of $matches"
        if ((b64)); then
            exp_match+=("$REPLY")
        else
            # note bash process subst strips trailing \n's
            exp_match+=("$(echo $REPLY | _exp_decode)")
        fi
    done
}

# exp_internal [on]
exp_internal() {
    local cmd
    [[ ${1:-} == on ]] && cmd="exp_internal 1" || cmd="exp_internal 0"
    _exp_write "if [catch {$cmd}] {puts stderr \"exp_internal: $::errorInfo\"; out 1} {out 0}"
    _exp_read || die "stalled"
    return $REPLY
}

# exp_log [options] [file|on]
exp_log() {
    local OPTIND opt append="-noappend"
    while getopts ":a" opt; do case $opt in
        a) append="" ;;
        *) _exp_die "invalid param" ;;
    esac; done
    shift $((OPTIND-1))
    local cmd="log_file;"
    case "$*" in
        on) cmd+="log_file -a -leaveopen stderr" ;;
        "") ;;
        *) cmd+="log_file -a $append $*" ;;
    esac
    _exp_write "if [catch {$cmd}] {puts stderr \"exp_log: $::errorInfo\"; out 1} {out 0}"
    _exp_read || die "stalled"
    return $REPLY
}
