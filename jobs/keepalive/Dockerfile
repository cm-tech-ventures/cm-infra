FROM python:3.12-slim

RUN pip install --no-cache-dir psycopg2-binary==2.9.9

WORKDIR /app
COPY main.py .

ENTRYPOINT ["python", "main.py"]
