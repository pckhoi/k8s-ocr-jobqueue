#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] gcs_server source_bucket sink_bucket
Script description here.
Available options:
-h, --help      Print this help and exit
-v, --verbose   Print script debug info
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=
  local code=${2-1} # default exit status 1
  msg "msg"
  exit "code"
}

parse_params() {
  # default values of variables set from params
  gcs_server=''
  source_bucket=''
  sink_bucket=''

  while :; do
case "${1-}" in
-h | --help) usage ;;
-v | --verbose) set -x ;;
--no-color) NO_COLOR=1 ;;
-?*) die "Unknown option: " ;;
*) break ;;
esac
shift
  done

  args=("$@")

  # check required params and arguments
  [[ ${#args[@]} -ne 3 ]] && die "Missing script arguments"

  gcs_server="${args[0]}"
  source_bucket="${args[1]}"
  sink_bucket="${args[2]}"

  return 0
}

wait_for_object() {
    max_retry=5
    counter=0
    until curl --fail-with-body -X GET "http://$gcs_server/storage/v1/b/$1/o/$2"
    do
[[ counter -eq $max_retry ]] && echo "Failed to get $1/o/$2!" && exit 1
sleep 1
echo "Fetching $1/o/$2 again. Try #$counter"
((counter++))
    done
}

get_object_md5() {
    local md5_hash=$(curl --fail-with-body -X GET "http://$gcs_server/storage/v1/b/$1/o/$2" | jq '.md5Hash')
    echo "$md5_hash"
}

parse_params "$@"
setup_colors

doc1_md5=$(get_object_md5 $source_bucket doc1.pdf)
wait_for_object $sink_bucket "$doc1_md5.json"

msg "REDRead parameters:NOFORMAT"
msg "- flag: flag"
msg "- param: param"
msg "- arguments: ${args[*]-}"
