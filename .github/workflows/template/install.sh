#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
version=%%version%%
declare -a executables=("gcloud" "gsutil" "git")

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v]
    [-i input_bucket]
    [-o output_bucket]
    [-s service_account]
    -p project_id
    {--install|--uninstall}
Install an OCR jobqueue based on DocTR in your K8s cluster
Available options:
-h, --help              Print this help and exit
-v, --verbose           Print script debug info
-i, --input-bucket      Storage bucket that keep input PDF,
                        defaults to 'ocr-docs'
-o, --output-bucket     Storage bucket that keep OCR results,
                        defaults to 'ocr-results'
-s, --service-account   Service account that will be created
                        to read and write to buckets, defaults
                        to 'ocr-docs-admin'
-p, --project-id        Google cloud project id
--install               Install OCR jobqueue
--uninstall             Uninstall OCR jobqueue
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

check_executables() {
  for cmd in "${executables[@]}"
  do
    command -v $cmd >/dev/null 2>&1 || die "$cmd could not be found"
  done
}

parse_params() {
  # default values of variables set from params
  input_bucket='ocr-docs'
  output_bucket='ocr-results'
  service_account='ocr-docs-admin'
  install=0
  uninstall=0
  project_id=''

  while :; do
case "${1-}" in
-h | --help) usage ;;
-v | --verbose) set -x ;;
--no-color) NO_COLOR=1 ;;
--install) install=1 ;;
--uninstall) uninstall=1 ;;
-i | --input-bucket)
  input_bucket="${2-}"
  shift
  ;;
-o | --output-bucket)
  output_bucket="${2-}"
  shift
  ;;
-s | --service-account)
  service_account="${2-}"
  shift
  ;;
-p | --project-id)
  project_id="${2-}"
  shift
  ;;
-?*) die "Unknown option: " ;;
*) break ;;
esac
shift
  done

  args=("$@")

  # check required params and arguments
  [[ -z "${project_id-}" ]] && die "Missing required parameter: project_id"
  [[ $install -eq 0 && $uninstall -eq 0 ]] && die "Must either use flag --install, or --uninstall"

  return 0
}

parse_params "$@"
check_executables
setup_colors

if [[ $install -eq 1 ]]
then
  do_install
 
elif [[ $uninstall -eq 1 ]]
then
  do_uninstall

fi

msg "REDRead parameters:NOFORMAT"
msg "- flag: flag"
msg "- param: param"
msg "- arguments: ${args[*]-}"
