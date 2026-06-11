FROM python:3.12-slim

RUN pip install --no-cache-dir mem0ai fastapi "uvicorn[standard]" ollama

WORKDIR /app
COPY app.py .

ENV DATA_DIR=/data
EXPOSE 8765

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8765"]
