FROM python:3-slim

WORKDIR /app

COPY requirements.txt .


ENV VIRTUAL_ENV=/opt/venv
RUN python -m venv $VIRTUAL_ENV 
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN --mount=type=cache,target=/root/.cache pip install --upgrade pip \
    && pip install -r ./requirements.txt 

COPY . .

VOLUME /app/data

EXPOSE 8000

CMD ["uvicorn", "restapi:app", "--host", "0.0.0.0", "--port", "8000"]

