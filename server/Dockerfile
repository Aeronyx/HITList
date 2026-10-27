FROM python:3.12-alpine
WORKDIR /app
COPY server.py .
ENV HITLIST_DATA_DIR=/data PORT=8787
EXPOSE 8787
VOLUME ["/data"]
HEALTHCHECK --interval=60s --timeout=5s CMD wget -qO- http://127.0.0.1:8787/health || exit 1
USER nobody
CMD ["python3", "-u", "server.py"]
