FROM python:3.10-slim

# Set up a new user named "user" with UID 1000
RUN useradd -m -u 1000 user

WORKDIR /code

# Copy requirements.txt and install dependencies
COPY --chown=user:user ./requirements.txt /code/requirements.txt
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

# Copy application files
COPY --chown=user:user . /code

# Set user to "user" (required for Hugging Face Spaces security)
USER user

# Hugging Face Spaces run on port 7860 by default
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
