#!/bin/bash -u

die() { echo "$*" >&2; exit; }

(($# < 3)) && die "Usage: lsftp.sh server user pass [directory]"

server=${1?} user=${2?} pass=${3?} dir=${4:-}

# source expect.sh from same directory as this script
source ${0%/*}/expect.sh || exit

echo "Connecting to $server..."
# Directory listings could be 32KB?
exp_spawn -n 32768 ftp -p $server || die "exp_spawn failed"
exp_expect -t10 "Name.*:" "ftp>"
(($exp_index)) && die "Connect failed"
exp_send "$user\n"
exp_expect "Password:" "ftp>"
(($exp_index)) && die "Username failed"
exp_send "$pass\n"
exp_expect "530 Login incorrect" "ftp>"
(($exp_index)) || die "Login failed"
exp_expect -t0 # flush buffer

if [[ $dir ]]; then
    exp_send "cd \"$dir\"\n"
    # "250 Directory successfully changed." or "550 Failed to change directory."
    exp_expect "^(250|550)" || die "cd failed"
    [[ ${exp_match[1]} == 550 ]] && die "No such directory '$dir'"
fi

exp_send "ls -al\n"
# 150 Here comes the directory listing.
# <lines we want to see>
# 226 Directory send OK.
exp_expect "150[^\n]+\n(.+\n)226" || die "ls failed (increase exp_spawn -s?)"
echo "Contents of directory '${dir:-.}':"
echo "${exp_match[1]}"
