#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
declare -a executables=("gcloud" "gsutil" "kubectl")

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v]
    [-i input_bucket] [-o output_bucket]
    [-s service_account] [-n namespace]
    project_id
Uninstall OCR job queue
Available options:
-h, --help              Print this help and exit
-v, --verbose           Print script debug info
-i, --input-bucket      Remove input bucket. Note that this also
                        delete all data.
-o, --output-bucket     Remove output bucket. Note that this also
                        delete all data.
-s, --service-account   Service account created to read and write to buckets,
                        defaults to 'k8s-ocr-jobqueue'
-n, --namespace         Kubernetes namespace that houses the jobqueue,
                        defaults to 'k8s-ocr-jobqueue'
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
  local msg=$1
  local code=${2:-1} # default exit status 1
  msg "Error: $msg"
  exit "$code"
}

check_executables() {
  for cmd in "${executables[@]}"
  do
    command -v $cmd >/dev/null 2>&1 || die "$cmd could not be found"
  done
}

parse_params() {
  # default values of variables set from params
  project_id=''
  input_bucket=''
  output_bucket=''
  service_account='k8s-ocr-jobqueue'
  namespace='k8s-ocr-jobqueue'

  while :; do
case "${1-}" in
-h | --help) usage ;;
-v | --verbose) set -x ;;
--no-color) NO_COLOR=1 ;;
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
-n | --namespace)
  namespace="${2-}"
  shift
  ;;
-?*) die "Unknown option: " ;;
*) break ;;
esac
shift
  done

  args=("$@")

  # check required params and arguments
  [[ ${#args[@]} -ne 1 ]] && die "Wrong number of script arguments"

  project_id="${args[0]}"

  return 0
}

uninstall() {
    kubectl delete namespace $namespace --ignore-not-found=true
    gcloud iam service-accounts delete --quiet \
        $service_account@$project_id.iam.gserviceaccount.com
    [[ ! -z "$input_bucket" ]] \
        && gsutil notification delete gs://$input_bucket \
        && gsutil rm -r gs://$input_bucket
    [[ ! -z "$output_bucket" ]] \
        && gsutil rm -r gs://$output_bucket
}

parse_params "$@"
check_executables
setup_colors

uninstall
