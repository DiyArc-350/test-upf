FROM python:3.14-slim
RUN pip install --no-cache-dir p4runtime-shell scapy
WORKDIR /app
COPY . .
CMD ["python", "-u", "main.py"]
