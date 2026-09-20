FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    FLASK_ENV=production

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# SQLite 数据目录 (docker volume 挂载点) 与运行用户
RUN chmod +x docker-entrypoint.sh \
    && useradd --create-home --shell /bin/bash appuser \
    && mkdir -p /data /app/instance \
    && chown -R appuser:appuser /data /app

USER appuser

EXPOSE 5000

HEALTHCHECK --interval=15s --timeout=5s --start-period=25s --retries=5 \
    CMD python -c "import sys,urllib.request;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/api/meta/health', timeout=4).status == 200 else 1)"

ENTRYPOINT ["./docker-entrypoint.sh"]
