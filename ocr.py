import logging
import logging.config
import json
import os
import re
import signal

import stackless
from requests import Session
import google.auth
from google.cloud.storage import Client
from google.api_core.exceptions import PreconditionFailed
from doctr.io import DocumentFile
from doctr.models import ocr_predictor

logging.config.dictConfig(
    {
        "version": 1,
        "formatters": {"long": {"format": "%(levelname)s - %(asctime)s - %(message)s"}},
        "handlers": {
            "console": {
                "class": "logging.StreamHandler",
                "formatter": "long",
                "level": "INFO",
                "stream": "ext://sys.stdout",
            }
        },
        "loggers": {
            "jq": {"level": "INFO", "handlers": ["console"], "propagate": False}
        },
        "incremental": False,
        "disable_existing_loggers": True,
    }
)
logger = logging.getLogger("jq")


class Manager:
    """Decides which page need to be OCRed, which file is fully OCRed and can be removed."""

    def __init__(self, client, source_bucket, sink_bucket, finished_page_c) -> None:
        self._client = client
        self._source_bucket = source_bucket
        self._sink_bucket = sink_bucket
        self._pages = dict()
        self.page_c = stackless.channel(100)
        self._finished_page_c = finished_page_c
        self.copy_blob_c = stackless.channel(100)
        self._send_blobs_t = stackless.tasklet(self._fetch_pdf_pages)
        self._send_blobs_t()
        self._cleanup_source_bucket_t = stackless.tasklet(self._cleanup_source_bucket)
        self._cleanup_source_bucket_t()

    def _fetch_pdf_pages(self):
        logger.info("listing blobs from gs://%s" % self._source_bucket)

        for blob in self._client.list_blobs(self._source_bucket):
            pdf_name, page_file = os.path.split(blob.name)
            pageno, _ = os.path.splitext(page_file)
            if pageno == "count":
                self.copy_blob_c.send(blob)
            self._pages.setdefault(pdf_name, dict())[pageno] = blob

        for blob in self._client.list_blobs(self._sink_bucket):
            pdf_name, page_file = os.path.split(blob.name)
            pageno, _ = os.path.splitext(page_file)
            if pageno == "count":
                continue
            if pdf_name in self._pages:
                self._pages[pdf_name].pop(pageno, None)

        for pdf_name in list(self._pages.keys()):
            for blob in list(self._pages[pdf_name].values()):
                self.page_c.send(blob)

    def _cleanup_source_bucket(self):
        for pdf_name, pageno in self._finished_page_c:
            self._pages[pdf_name].pop(pageno, None)
            if len(self._pages[pdf_name]) == 0:
                logger.info(
                    "dropping blobs with prefix %s from gs://%s"
                    % (json.dumps(pdf_name), self._source_bucket)
                )
                for blob in self._client.list_blobs(
                    self._source_bucket, prefix=pdf_name
                ):
                    blob.delete()
                self._pages.pop(pdf_name, None)

    def stop(self):
        logger.info("stopping manager")
        self._send_blobs_t.kill()
        self._cleanup_source_bucket_t.kill()
        self.page_c.close()
        self.copy_blob_c.close()


class Predictor:
    def __init__(self, blob_chan):
        self._blob_chan = blob_chan
        self.c = stackless.channel(10)
        stackless.tasklet(self._run)()

    def _run(self):
        predictor = ocr_predictor(pretrained=True)
        for blob in self._blob_chan:
            logger.info("processing blob %s" % (json.dumps(blob.name),))
            with blob.open("rb") as f:
                content = f.read()
            doc = DocumentFile.from_images(content)
            self.c.send((blob.name, predictor(doc)))
        self.c.close()


def serialize_document(doc):
    page = doc.pages[0]
    return {
        "blocks": [
            {
                "lines": [
                    {
                        "words": [
                            {
                                "value": word.value,
                                "confidence": word.confidence,
                                "geometry": word.geometry,
                            }
                            for word in line.words
                        ],
                        "geometry": line.geometry,
                    }
                    for line in block.lines
                ],
                "artefacts": [
                    {
                        "artefact_type": artefact.artefact_type,
                        "confidence": artefact.confidence,
                        "geometry": artefact.geometry,
                    }
                    for artefact in block.artefacts
                ],
                "geometry": block.geometry,
            }
            for block in page.blocks
        ],
        "page_idx": page.page_idx,
        "dimensions": page.dimensions,
        "orientation": page.orientation,
        "language": page.language,
    }


class Sink:
    def __init__(
        self,
        client,
        source_bucket,
        sink_bucket,
        ocr_result_chan,
        finished_page_c,
        copy_blob_c,
    ):
        self._result_chan = ocr_result_chan
        self._client = client
        self._source_bucket = source_bucket
        self._sink_bucket = sink_bucket
        self._finished_page_c = finished_page_c
        self._copy_blob_c = copy_blob_c
        self._save_processed_pages_t = stackless.tasklet(self._save_processed_pages)
        self._save_processed_pages_t()
        self._copy_blobs_t = stackless.tasklet(self._copy_blobs)
        self._copy_blobs_t()

    def _save_processed_pages(self):
        bucket = self._client.bucket(self._sink_bucket)
        for name, result in self._result_chan:
            name, _ = os.path.splitext(name)
            pdf_name, pageno = os.path.split(name)
            name = name + ".json"
            blob = bucket.blob(name)
            try:
                blob.upload_from_string(
                    json.dumps(serialize_document(result)),
                    content_type="application/json",
                    if_generation_match=0,
                )
            except PreconditionFailed:
                pass
            logger.info(
                "saved ocr result %s to gs://%s" % (json.dumps(name), self._sink_bucket)
            )
            self._finished_page_c.send((pdf_name, pageno))

    def _copy_blobs(self):
        source = self._client.bucket(self._source_bucket)
        sink = self._client.bucket(self._sink_bucket)
        for blob in self._copy_blob_c:
            try:
                source.copy_blob(blob, sink, blob.name, if_generation_match=0)
            except PreconditionFailed:
                pass
            logger.info(f"copied blob {blob.name} to gs://{self._sink_bucket}")

    @property
    def is_alive(self):
        return self._save_processed_pages_t.alive


class FakeServerSession(Session):
    def __init__(self, url=None, *args, **kwargs):
        super(FakeServerSession, self).__init__(*args, **kwargs)
        self._url = url
        self.is_mtls = False

    def request(self, method, url, *args, **kwargs):
        url = re.sub(r"^https?://[^/]+", self._url, url)
        return super(FakeServerSession, self).request(method, url, *args, **kwargs)


if __name__ == "__main__":
    if "FAKE_GCS_SERVER" in os.environ:
        from google.auth.credentials import AnonymousCredentials

        credentials = AnonymousCredentials()
        project = os.getenv("PROJECT_ID", "test")
        _http = FakeServerSession(os.environ["FAKE_GCS_SERVER"])
    else:
        credentials, project = google.auth.default()
        _http = None
    client = Client(project, credentials=credentials, _http=_http)
    finished_page_c = stackless.channel(100)
    source_bucket = os.environ["SOURCE_BUCKET"]
    sink_bucket = os.environ["SINK_BUCKET"]
    manager = Manager(client, source_bucket, sink_bucket, finished_page_c)
    predictor = Predictor(manager.page_c)
    sink = Sink(
        client,
        source_bucket,
        sink_bucket,
        predictor.c,
        finished_page_c,
        manager.copy_blob_c,
    )

    def _stop():
        logger.info("received stop signal, cleaning up")
        manager.stop()
        while True:
            if not sink.is_alive:
                logger.info("stopping application")
                return
            stackless.schedule()

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    stackless.run()
