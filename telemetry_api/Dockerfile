FROM python:3.9-slim-buster

WORKDIR /app

COPY requirements.txt .

RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

VOLUME /app/data

EXPOSE 8000

CMD ["uvicorn", "restapi:app", "--host", "0.0.0.0", "--port", "8000"]

