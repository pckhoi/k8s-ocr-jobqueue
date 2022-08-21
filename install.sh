#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
version=%%version%%
declare -a executables=("gcloud" "gsutil" "kustomize" "docker" "curl" "kubectl")

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v]
    [-s service_account] [-n namespace] [-p poll_interval]
    project_id input_bucket output_bucket
Install an OCR jobqueue based on DocTR in your K8s cluster
Available options:
-h, --help              Print this help and exit
-v, --verbose           Print script debug info
-s, --service-account   Service account that will be created
                        to read and write to buckets, defaults
                        to 'k8s-ocr-jobqueue'
-n, --namespace         Kubernetes namespace to install this jobqueue,
                        defaults to 'k8s-ocr-jobqueue'
-p, --poll-interval     Number of seconds to wait before job queue poll
                        for updates, defaults to 300
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  [[ -n "$tmp_dir"  ]] && cd && rm -rf $tmp_dir
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
  poll_interval=300

  while :; do
case "${1-}" in
-h | --help) usage ;;
-v | --verbose) set -x ;;
--no-color) NO_COLOR=1 ;;
-s | --service-account)
  service_account="${2-}"
  shift
  ;;
-n | --namespace)
  namespace="${2-}"
  shift
  ;;
-p | --poll-interval)
  poll_interval="${2-}"
  shift
  ;;
-?*) die "Unknown option: " ;;
*) break ;;
esac
shift
  done

  args=("$@")

  # check required params and arguments
  [[ $poll_interval != +([[:digit:]]) ]] && die "poll_interval must be integer"
  [[ ${#args[@]} -lt 3 ]] && die "Wrong number of script arguments: ${#args[@]} < 3"

  project_id="${args[0]}"
  input_bucket="${args[1]}"
  output_bucket="${args[2]}"

  return 0
}

download_assets() {
  echo "Downloading assets..."
  tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
  cd $tmp_dir
  local assets_dir=installation-assets
  local FILE=$assets_dir.tar.gz
  local URL=https://github.com/pckhoi/k8s-ocr-jobqueue/releases/download/$version/$FILE
  echo "Downloading:" $URL
  curl -A "k8s-ocr-jobqueueu-installer" -fsL "$URL" > "$FILE"
  tar zxf "$FILE"
  cd $assets_dir
}

create_buckets() {
  echo "Creating buckets..."
  gsutil mb -p $project_id gs://$input_bucket
  gsutil mb -p $project_id gs://$output_bucket
  gsutil iam ch allUsers:objectViewer gs://$output_bucket
  gsutil notification create \
    -t $input_bucket -f json \
    -e OBJECT_FINALIZE gs://$input_bucket
}

create_service_account() {
  echo "Creating service account..."
  key_file=key.json
  gcloud iam service-accounts create $service_account \
    --description="Read/write OCR data to storage buckets" \
    --display-name="OCR docs admin" \
    --project $project_id
  gcloud projects add-iam-policy-binding $project_id \
    --member="serviceAccount:$service_account@$project_id.iam.gserviceaccount.com" \
    --role="roles/pubsub.subscriber"
  gsutil iam ch \
    serviceAccount:$service_account@$project_id.iam.gserviceaccount.com:admin \
    gs://$input_bucket gs://$output_bucket
  gcloud iam service-accounts keys create $key_file \
    --iam-account=$service_account@$project_id.iam.gserviceaccount.com
}

push_image() {
  echo "Pushing image..."
  docker build -t doctr image
  img_id=$(docker images --format '{{.ID}}' doctr:latest)
  docker tag doctr:latest gcr.io/$project_id/doctr:$img_id
  docker push gcr.io/$project_id/doctr:$img_id
}

apply_k8s_resources() {
  echo "Applying Kubernetes resources..."
  kustomize edit set namespace $namespace
  kustomize edit set image doctr=gcr.io/$project_id/doctr:$img_id
  kustomize edit add configmap doctr-config \
    --from-literal=SOURCE_BUCKET=$input_bucket \
    --from-literal=SINK_BUCKET=$output_bucket \
    --from-literal=POLL_INTERVAL=$poll_interval
  kustomize edit add secret service-account-key --from-file=key.json=$key_file
  kustomize build . | kubectl apply -f -
  echo 'OCR resources installed in namespace "'$namespace'"'
}

parse_params "$@"
check_executables
setup_colors

download_assets
create_buckets
create_service_account
push_image
apply_k8s_resources
