FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/app
COPY pyproject.toml ./
ENV UV_PROJECT_ENVIRONMENT=/opt/venv
RUN pip install --no-cache-dir uv \
    && uv sync --no-dev

ENV PATH="/opt/venv/bin:${PATH}"
ENTRYPOINT ["dbt"]

