# Kubernetes OCR Job Queue

Simple OCR job queue on Kubernetes. This job queue utilizes Google Cloud Storage buckets to store input and output data. To start processing documents, copy PDF files to the input bucket. The OCR deployment on Kubernetes will be notified and start processing the document with [DocTR](https://github.com/mindee/doctr). After some time, the processed documents will be saved to the output bucket as JSON.

## Installation

```bash
curl -L https://github.com/pckhoi/k8s-ocr-jobqueue/releases/latest/download/install.sh -o install.sh
chmod +x install.sh
./install.sh PROJECT_ID INPUT_BUCKET OUTPUT_BUCKET
```

### Synopsis

```
install.sh [-h] [-v] [-s SERVICE_ACCOUNT]
    [-n NAMESPACE] [-p POLL_INTERVAL]
    PROJECT_ID INPUT_BUCKET OUTPUT_BUCKET
```

### Arguments and Flags

| Argument/Flag     | Short flag | Description                                                                                       |
| ----------------- | ---------- | ------------------------------------------------------------------------------------------------- |
| --help            | -h         | Print help message and exit                                                                       |
| --verbose         | -v         | Print script debug info                                                                           |
| --service-account | -s         | Service account that will be created to read and write to buckets, defaults to 'k8s-ocr-jobqueue' |
| --namespace       | -n         | Kubernetes namespace to install this jobqueue, defaults to 'k8s-ocr-jobqueue'                     |
| --poll-interval   | -p         | Number of seconds to wait before job queue poll for updates, defaults to 300                      |
| PROJECT_ID        |            | Google Cloud project id to create buckets and service account under                               |
| INPUT_BUCKET      |            | The bucket to store input PDF files                                                               |
| OUTPUT_BUCKET     |            | The bucket to store OCR results as JSON files                                                     |

## Uninstallation

```bash
curl -L https://github.com/pckhoi/k8s-ocr-jobqueue/releases/latest/download/uninstall.sh -o uninstall.sh
chmod +x uninstall.sh
./uninstall.sh -i INPUT_BUCKET -o OUTPUT_BUCKET PROJECT_ID
```

### Synopsis

```
uninstall.sh [-h] [-v] [-i INPUT_BUCKET] [-o OUTPUT_BUCKET]
    [-s SERVICE_ACCOUNT] [-n NAMESPACE]
    PROJECT_ID
```

### Arguments and Flags

| Argument/Flag     | Short flag | Description                                                                          |
| ----------------- | ---------- | ------------------------------------------------------------------------------------ |
| --help            | -h         | Print help message and exit                                                          |
| --verbose         | -v         | Print script debug info                                                              |
| --input-bucket    | -i         | Remove input bucket. Note that this also delete all data.                            |
| --output-bucket   | -o         | Remove output bucket. Note that this also delete all data.                           |
| --service-account | -s         | Service account created to read and write to buckets, defaults to 'k8s-ocr-jobqueue' |
| --namespace       | -n         | Kubernetes namespace that houses the jobqueue, defaults to 'k8s-ocr-jobqueue'        |
| PROJECT_ID        |            | Google Cloud project id to remove the job queue from                                 |

## Check job queue status

```bash
$ kubectl get pod -n k8s-ocr-jobqueue -w
NAME                     READY   STATUS    RESTARTS   AGE
doctr-677955b7bd-b4xzv   1/1     Running   3          25m

$ kubectl logs -n k8s-ocr-jobqueue doctr-677955b7bd-b4xzv -f
INFO - 2022-08-21 11:11:46,342 - listing blobs from "k8s-ocr-jobqueue-input-bucket"
INFO - 2022-08-21 11:11:46,525 - inserting blob "raw_minutes/carencro/cfpcsb/Agenda-Oct2012-CSB-mtg.pdf" (md5:17ec09dc9e6c05372a2ecf62ec1634fc)
/usr/local/lib/python3.7/site-packages/torchvision/models/_utils.py:136: UserWarning: Using 'weights' as positional parameter(s) is deprecated since 0.13 and will be removed in 0.15. Please use keyword parameter(s) instead.
  f"Using {sequence_to_str(tuple(keyword_only_kwargs.keys()), separate_last='and ')} as positional "
/usr/local/lib/python3.7/site-packages/torchvision/models/_utils.py:223: UserWarning: Arguments other than a weight enum or `None` for 'weights' are deprecated since 0.13 and will be removed in 0.15. The current behavior is equivalent to passing `weights=None`.
  warnings.warn(msg)
INFO - 2022-08-21 11:11:50,407 - processing blob "raw_minutes/carencro/cfpcsb/Agenda-Oct2012-CSB-mtg.pdf" (md5:17ec09dc9e6c05372a2ecf62ec1634fc)
INFO - 2022-08-21 11:12:05,641 - saving ocr result raw_minutes/carencro/cfpcsb/Agenda-Oct2012-CSB-mtg.pdf.json
INFO - 2022-08-21 11:12:05,828 - inserting blob "raw_minutes/carencro/cfpcsb/Appeal-Posting-Notice-Conrad-Callegari-May-7-2019.pdf" (md5:3d4e3e42c8efcd97274fbdc5a6cd56e2)
INFO - 2022-08-21 11:12:05,829 - processing blob "raw_minutes/carencro/cfpcsb/Appeal-Posting-Notice-Conrad-Callegari-May-7-2019.pdf" (md5:3d4e3e42c8efcd97274fbdc5a6cd56e2)
...
```
