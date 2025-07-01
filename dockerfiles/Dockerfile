FROM python:3.12-slim-bookworm

COPY . /app
WORKDIR /app
RUN python -m pip install -e /app[dev] \
    && chmod +x /app/entrypoint.sh
EXPOSE 8000
ENTRYPOINT ["/app/entrypoint.sh"]