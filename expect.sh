# shellcheck shell=bash

# This file is sourced by another bash script to provide expect functionality, see
# https://github.com/glitchub/expect.sh for more details, examples, and the latest code.

# Released by the author into the public domain, do whatever you want with it.

declare -g _exp_stdout _exp_stdin _exp_prog exp_spawnid exp_index exp_match

_exp_die() { echo "${FUNCNAME[1]}@${BASH_LINENO[1]}: $*" >&2; exit 1; }

# Initialize and start the expect coprocess
# shellcheck disable=SC2120
_exp_start() {
    local out in script
    [[ ${_exp_prog:-} ]] && _exp_die "expect.sh is already sourced?"
    _exp_prog=$(type -pf expect 2>/dev/null) || { _exp_die "expect.sh requires expect"; }
    exp_spawnid="tty" # default to tty before spawn
    exp_index=-3
    exp_match=()
    if [[ ${1:-} == trace ]]; then
        # If argument "trace" if specified show coprocess I/O on stderr
        out='proc out {s} {puts stderr "[clock milliseconds] OUT: $s"; puts $s}'
        in='puts stderr "[clock milliseconds] IN : $line"'
    else
        out='proc out {s} {puts $s}'
        in=''
    fi
    # write script to temp pipe
    exec {script}<<EOT
        log_user 0
        set stty_init -echo
        $out
        proc encode {s} {binary encode base64 [encoding convertto utf-8 \$s]}
        proc decode {s} {encoding convertfrom utf-8 [binary decode base64 \$s]}
        while {[gets stdin line] >= 0} {$in; eval \$line}
EOT
    # XXX get rid of stdbuf
    coproc _exp_coproc { stdbuf -oL $_exp_prog -f /dev/fd/$script; }
    exec {script}<&- {_exp_stdout}<&"${_exp_coproc[0]}" {_exp_stdin}>&"${_exp_coproc[1]}"
}
_exp_start

# These are used in conjunction with the expect encode/decode proc's defined above to pass literal
# strings between bash and expect without quoting/whitespace issues.
_exp_encode () { $_exp_prog -c 'fconfigure stdin -translation binary; puts -nonewline [binary encode base64 [encoding convertto utf-8 [read stdin]]]; flush stdout'; }
_exp_decode () { $_exp_prog -c 'fconfigure stdout -translation binary; puts -nonewline [encoding convertfrom utf-8 [binary decode base64 [read stdin]]]; flush stdout'; }

# _exp_write [string]
# Write string or stdin to expect coprocess.
# Each line must be a complete tcl expression!
_exp_write() {
    if (($#)); then
        printf "%s\n" "$*"  >&$_exp_stdin || exp_die "coprocess write error"
    else
        cat >&$_exp_stdin || exp_die "coprocess write error"
    fi
}

# _exp_read [timeout]
# Read a line from expect coprocess to variable $REPLY and return 0 on success, 1 if timeout
# Default timeout is 60 seconds!
_exp_read() {
    IFS= read -r -t ${1:-60} <&$_exp_stdout
    local xs=$?
    ((xs > 128)) && return 1
    ((!xs)) || _exp_die "coprocess read error"
}

# The rest are user functions, see the README.

# exp_spawn [options] [--] program [args...]
exp_spawn() {
    local opt OPTIND chars=1000 args
    while getopts ":n:" opt; do case $opt in
        n) chars=$OPTARG; [[ $chars =~ ^[1-9][0-9]*$ ]] || _exp_die "invalid buffer chars" ;;
        *) _exp_die "invalid param" ;;
    esac; done
    shift $((OPTIND-1))
    (($#)) || _exp_die "missing program"
    readarray -t args < <(for a in "$@"; do printf "%s" "$a" | _exp_encode; echo; done)
    _exp_write "if [catch {if [spawn -noecho {*}[lmap b64 { ${args[*]} } { binary decode base64 \$b64 } ]] {out \$spawn_id} {out {}}}] {puts stderr \"exp_spawn: \$::errorInfo\"; out {}}"
    _exp_read || _exp_die "stalled"
    [[ $REPLY ]] || return 1
    exp_spawnid=$REPLY
    _exp_write "match_max $chars"
}

# exp_close [options]
exp_close() {
    local opt OPTIND spawnid=$exp_spawnid
    while getopts ":i:" opt; do case $opt in
        i) spawnid=$OPTARG ;;
        *) _exp_die "invalid param" ;;
    esac; done
    [[ $spawnid =~ ^[a-z0-9]+$ ]] || _exp_die "invalid spawn id"
    _exp_write "if [catch {close -i $spawnid; wait -nowait -i $spawnid}] {puts stderr \"exp_close: \$::errorInfo\"; out 1} {out 0}"
    _exp_read || _exp_die "stalled"
    [[ $spawnid == "$exp_spawnid" ]] && exp_spawnid="tty"
    return $REPLY
}

# exp_send [options] [--] [string]
exp_send() {
    local opt OPTIND spawnid=$exp_spawnid cmd
    while getopts ":i:" opt; do case $opt in
        i) spawnid=$OPTARG ;;
        *) _exp_die "invalid param" ;;
    esac; done
    shift $((OPTIND-1))
    [[ $spawnid =~ ^[a-z0-9]+$ ]] || _exp_die "invalid spawn id"
    [[ $spawnid == tty ]] && cmd="send_tty" || cmd="send -i $spawnid"
    if (($#)); then
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
    local OPTIND opt spawnid=$exp_spawnid timeout=2
    while getopts ":i:t:" opt; do case $opt in
        i) spawnid=$OPTARG ;;
        t) timeout=$OPTARG; [[ $timeout =~ ^(0|[1-9][0-9])*$ ]] || _exp_die "invalid timeout" ;;
        *) _exp_die "invalid param" ;;
    esac; done
    shift $((OPTIND-1))
    (($#)) || set -- .+
    local arg cmd index=0
    [[ $spawnid =~ ^[a-z0-9]+$ ]] || _exp_die "invalid spawn id"
    [[ $spawnid == tty ]] && cmd="expect_tty" || cmd="expect -i $spawnid"
    cmd+=" -timeout $timeout"
    for arg in "$@"; do cmd+=" -regex [decode $(printf "%b" "$arg" | _exp_encode)] {set result $((index++))}"; done
    cmd+=" timeout {set result -1} eof {set result -2}"
    _exp_write <<EOT
        if [catch { \
           array unset expect_out; \
           $cmd; \
           if {\$result >= 0} { \
                set matches [llength [lsearch -all [array names expect_out] *string]]; \
                out "\$result \$matches"; \
                for {set i 0} {\$i < \$matches} {incr i} {out [encode \$expect_out(\$i,string)]}; \
           } else { out \$result } \
        }] { puts stderr "exp_expect: \$::errorInfo"; out -3 }
EOT
    exp_match=()
    _exp_read ${timeout}.5 || _exp_die "stalled"
    exp_index=${REPLY% *}
    ((exp_index < 0)) && return 1
    # slurp specified number of matches
    local matches=${REPLY#* } m
    for ((m=1; m <= matches; m++)); do
        _exp_read .5 || die "missing match $m of $matches"
        # note bash process subst strips trailing \n's
        exp_match+=("$(echo $REPLY | _exp_decode)")
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

# exp_log [on|file]
exp_log() {
    local cmd
    case ${1:-} in
        on) cmd="log_file; log_file -noappend -a -leaveopen stderr" ;;
        "") cmd="log_file" ;;
        *) cmd="log_file; log_file -a $1" ;;
    esac
    _exp_write "if [catch {$cmd}] {puts stderr \"exp_log: $::errorInfo\"; out 1} {out 0}"
    _exp_read || die "stalled"
    return $REPLY
}
