import logging
import sys
import json
import os
import re
from time import time
import signal

import stackless
from requests import Session
from google.cloud.storage import Client
from google.api_core.exceptions import PreconditionFailed
from doctr.io import DocumentFile
from doctr.models import ocr_predictor

logging.basicConfig(
    stream=sys.stdout,
    format="%(levelname)s %(asctime)s - %(message)s",
    level=logging.INFO,
)
logging.root.handlers[0].setLevel(logging.INFO)


class Ticker:
    def __init__(self):
        self._funcs = []
        self._time = time()
        t = stackless.tasklet(self._run)
        t()
        self._tasklets = [t]

    def _run_func(self, ch, func):
        while True:
            ch.receive()
            func()

    def schedule(self, func, interval):
        run_ch = stackless.channel()
        t = stackless.tasklet(self._run_func)
        t(run_ch, func)
        self._tasklets.append(t)
        self._funcs.append((time() + interval, run_ch, interval))
        self._funcs.sort()

    def _run(self):
        while True:
            now = time()
            for idx, item in enumerate(self._funcs):
                next_time, ch, interval = item
                if next_time > now:
                    break
                ch.send(None)
                self._funcs[idx] = (now + interval, ch, interval)
            stackless.schedule()

    def stop(self):
        for t in self._tasklets:
            t.kill()


class Source:
    def __init__(self, client, ticker, bucket_name, poll_interval) -> None:
        self._client = client
        self._ticker = ticker
        self._bucket_name = bucket_name
        self._poll_interval = poll_interval
        self._md5_set = set()
        self.c = stackless.channel(100)
        self._t = stackless.tasklet(self._run)
        self._t()

    def _send(self, blob):
        if not blob.name.endswith(".pdf") or blob.md5_hash in self._md5_set:
            return
        self._md5_set.add(blob.md5_hash)
        logging.info("inserting blob %s (%s)" % (json.dumps(blob.name), blob.md5_hash))
        self.c.send(blob)

    def _fetch_objects(self):
        logging.info("listing blobs from %s" % json.dumps(self._bucket_name))
        blobs = self._client.list_blobs(self._bucket_name)
        for blob in blobs:
            self._send(blob)

    def _fetch_updates(self):
        logging.info("fetching notifications from %s" % json.dumps(self._bucket_name))
        bucket = self._client.bucket(self._bucket_name)
        notifications = bucket.list_notifications()
        for notification in notifications:
            name = notification.custom_attributes["objectId"]
            if not name.endswith(".pdf"):
                continue
            blob = bucket.get_blob(name)
            self._send(blob)
            stackless.tasklet(notification.delete)()

    def _run(self):
        self._fetch_objects()
        # self._ticker.schedule(self._fetch_updates, self._poll_interval)

    def stop(self):
        logging.info("stopping source")
        self._t.kill()
        self.c.close()


class Predictor:
    def __init__(self, blob_chan):
        self._blob_chan = blob_chan
        self.c = stackless.channel(10)
        stackless.tasklet(self._run)()

    def _run(self):
        predictor = ocr_predictor(pretrained=True)
        for blob in self._blob_chan:
            logging.info(
                "processing blob %s (%s)" % (json.dumps(blob.name), blob.md5_hash)
            )
            with blob.open("rb") as f:
                content = f.read()
            doc = DocumentFile.from_pdf(content)
            self.c.send((blob.md5_hash, predictor(doc)))
            stackless.tasklet(blob.delete)()
        self.c.close()


def serialize_document(doc):
    return {
        "pages": [
            {
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
            for page in doc.pages
        ]
    }


class Sink:
    def __init__(self, client, bucket_name, ocr_result_chan):
        self._result_chan = ocr_result_chan
        self._client = client
        self._bucket_name = bucket_name
        self._t = stackless.tasklet(self._run)
        self._t()

    def _run(self):
        for md5_hash, result in self._result_chan:
            logging.info("saving ocr result %s.json" % md5_hash)
            blob = self._client.bucket(self._bucket_name).blob("%s.json" % md5_hash)
            try:
                blob.upload_from_string(
                    json.dumps(serialize_document(result)),
                    content_type="application/json",
                    if_generation_match=0,
                )
            except PreconditionFailed:
                pass

    @property
    def is_alive(self):
        return self._t.alive


class FakeServerSession(Session):
    def __init__(self, url=None, *args, **kwargs):
        super(FakeServerSession, self).__init__(*args, **kwargs)
        self._url = url
        self.is_mtls = False

    def request(self, method, url, *args, **kwargs):
        url = re.sub(r"^https?://[^/]+", self._url, url)
        return super(FakeServerSession, self).request(method, url, *args, **kwargs)


if __name__ == "__main__":
    ticker = Ticker()
    if os.getenv("FAKE_GCS_SERVER") != "":
        from google.auth.credentials import AnonymousCredentials

        creds = AnonymousCredentials()
        _http = FakeServerSession(os.environ["FAKE_GCS_SERVER"])
    else:
        creds = os.environ["GOOGLE_AUTH_CREDENTIALS"]
        _http = None
    client = Client(os.environ["PROJECT_ID"], credentials=creds, _http=_http)
    src = Source(
        client,
        ticker,
        os.environ["SOURCE_BUCKET"],
        poll_interval=int(os.getenv("POLL_INTERVAL", "300")),
    )
    predictor = Predictor(src.c)
    sink = Sink(client, os.environ["SINK_BUCKET"], predictor.c)

    def _stop():
        logging.info("received stop signal, cleaning up")
        ticker.stop()
        src.stop()
        while True:
            if not sink.is_alive:
                logging.info("stopping application")
                return
            stackless.schedule()

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    stackless.run()
