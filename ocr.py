import logging
import logging.config
import json
import os
import re

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

    def __init__(self, client, source_bucket, sink_bucket) -> None:
        self._client = client
        self._source_bucket = source_bucket
        self._sink_bucket = sink_bucket
        self._pages = dict()

    def _copy_blob(self, blob):
        source = self._client.bucket(self._source_bucket)
        sink = self._client.bucket(self._sink_bucket)
        try:
            source.copy_blob(blob, sink, blob.name, if_generation_match=0)
        except PreconditionFailed:
            pass
        logger.info(f"copied blob {blob.name} to gs://{self._sink_bucket}")

    def fetch_pdf_pages(self):
        logger.info("listing blobs from gs://%s" % self._source_bucket)

        for blob in self._client.list_blobs(self._source_bucket):
            pdf_name, page_file = os.path.split(blob.name)
            pageno, _ = os.path.splitext(page_file)
            if pageno == "count":
                self._copy_blob(blob)
                continue
            self._pages.setdefault(pdf_name, dict())[pageno] = blob

        for blob in self._client.list_blobs(self._sink_bucket):
            pdf_name, page_file = os.path.split(blob.name)
            pageno, _ = os.path.splitext(page_file)
            if pageno == "count":
                continue
            if pdf_name in self._pages:
                self._pages[pdf_name].pop(pageno, None)

        for pdf_name in list(self._pages.keys()):
            if len(self._pages[pdf_name]) == 0:
                yield (pdf_name, None)
            for blob in list(self._pages[pdf_name].values()):
                yield (pdf_name, blob)

    def process_pdf_pages(self, pdf_pages):
        predictor = ocr_predictor(pretrained=True)
        for pdf_name, blob in pdf_pages:
            if blob is None:
                yield (pdf_name, None, None)
            logger.info("processing blob %s" % (json.dumps(blob.name),))
            with blob.open("rb") as f:
                content = f.read()
            doc = DocumentFile.from_images(content)
            yield (pdf_name, blob.name, predictor(doc))

    def save_processed_pages(self, processed_pages):
        bucket = self._client.bucket(self._sink_bucket)
        for pdf_name, name, result in processed_pages:
            if name is None:
                yield (pdf_name, None)
            name, _ = os.path.splitext(name)
            _, pageno = os.path.split(name)
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
            yield (pdf_name, pageno)

    def _drop_pdf(self, pdf_name):
        logger.info(
            "dropping blobs with prefix %s from gs://%s"
            % (json.dumps(pdf_name), self._source_bucket)
        )
        for blob in self._client.list_blobs(self._source_bucket, prefix=pdf_name):
            blob.delete()
        self._pages.pop(pdf_name, None)

    def cleanup_source_bucket(self, finished_pages):
        for pdf_name, pageno in finished_pages:
            if pageno is None:
                self._drop_pdf(pdf_name)
                continue

            self._pages[pdf_name].pop(pageno, None)
            if len(self._pages[pdf_name]) == 0:
                self._drop_pdf(pdf_name)


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
    source_bucket = os.environ["SOURCE_BUCKET"]
    sink_bucket = os.environ["SINK_BUCKET"]
    manager = Manager(client, source_bucket, sink_bucket)
    manager.cleanup_source_bucket(
        manager.save_processed_pages(
            manager.process_pdf_pages(manager.fetch_pdf_pages())
        )
    )
