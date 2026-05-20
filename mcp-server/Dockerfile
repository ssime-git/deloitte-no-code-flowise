FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV UV_SYSTEM_PYTHON=1

WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN uv pip install --system -r /app/requirements.txt
COPY server.py /app/server.py

EXPOSE 8000

CMD ["python", "/app/server.py"]
