# Kubernetes OCR Job Queue

Simple OCR job queue on Kubernetes. This job queue utilizes Google Cloud Storage buckets to store input and output data. To start processing documents, copy PDF files to the input bucket. The OCR deployment on Kubernetes will be notified and start processing the document with [DocTR](https://github.com/mindee/doctr). After some time, the processed documents will be saved to the output bucket as JSON.

## Installation

```bash
curl -L https://github.com/pckhoi/k8s-ocr-jobqueue/releases/latest/download/install.sh -o install.sh
install.sh PROJECT_ID INPUT_BUCKET OUTPUT_BUCKET
```

### Synopsis

```
install.sh PROJECT_ID INPUT_BUCKET OUTPUT_BUCKET
    [-s SERVICE_ACCOUNT]
    [-n NAMESPACE]
    [-p POLL_INTERVAL]
```

### Arguments and Flags

| Argument/Flag     | Short flag | Description                                                                                       |
| ----------------- | ---------- | ------------------------------------------------------------------------------------------------- |
| PROJECT_ID        |            | Google Cloud project id to create buckets and service account under                               |
| INPUT_BUCKET      |            | The bucket to store input PDF files                                                               |
| OUTPUT_BUCKET     |            | The bucket to store OCR results as JSON files                                                     |
| --help            | -h         | Print help message and exit                                                                       |
| --verbose         | -v         | Print script debug info                                                                           |
| --service-account | -s         | Service account that will be created to read and write to buckets, defaults to 'k8s-ocr-jobqueue' |
| --namespace       | -n         | Kubernetes namespace to install this jobqueue, defaults to 'k8s-ocr-jobqueue'                     |
| --poll-interval   | -p         | Number of seconds to wait before job queue poll for updates, defaults to 300                      |

## Uninstallation

```bash
curl -L https://github.com/pckhoi/k8s-ocr-jobqueue/releases/latest/download/uninstall.sh -o
uninstall.sh PROJECT_ID -i INPUT_BUCKET -o OUTPUT_BUCKET
```

### Synopsis

```
uninstall.sh PROJECT_ID
    [-i INPUT_BUCKET]
    [-o OUTPUT_BUCKET]
    [-s SERVICE_ACCOUNT]
    [-n NAMESPACE]
```

### Arguments and Flags

| Argument/Flag     | Short flag | Description                                                                          |
| ----------------- | ---------- | ------------------------------------------------------------------------------------ |
| PROJECT_ID        |            | Google Cloud project id to remove the job queue from                                 |
| --help            | -h         | Print help message and exit                                                          |
| --verbose         | -v         | Print script debug info                                                              |
| --input-bucket    | -i         | Remove input bucket. Note that this also delete all data.                            |
| --output-bucket   | -o         | Remove output bucket. Note that this also delete all data.                           |
| --service-account | -s         | Service account created to read and write to buckets, defaults to 'k8s-ocr-jobqueue' |
| --namespace       | -n         | Kubernetes namespace that houses the jobqueue, defaults to 'k8s-ocr-jobqueue'        |
