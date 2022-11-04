FROM python:3.9-bullseye

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    ffmpeg \
    libsm6 \
    libxext6 \
    dpkg-dev \
    gcc \
    gnupg dirmngr \
    libbluetooth-dev \
    libbz2-dev \
    libc6-dev \
    libexpat1-dev \
    libffi-dev \
    libgdbm-dev \
    liblzma-dev \
    libncursesw5-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    make \
    tk-dev \
    uuid-dev \
    wget \
    xz-utils \
    zlib1g-dev \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONUNBUFFERED 1
ENV PYTHONDONTWRITEBYTECODE 1

ADD requirements.txt /tmp/requirements.txt

RUN pip3 install --upgrade pip setuptools wheel \
    && pip3 install -r /tmp/requirements.txt \
    && pip3 cache purge \
    && rm -rf /root/.cache/pip

ENV USE_TORCH 1
ENV SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt

RUN python3 -c "from doctr.models import ocr_predictor; ocr_predictor(pretrained=True)"

ADD ocr.py /ocr.py

CMD [ "python3", "/ocr.py" ]
