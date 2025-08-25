# Use a modern Python runtime (aligns with GA libraries like google-genai)
FROM python:3.12-slim

# Set the working directory in the container
WORKDIR /app

# Ensure stdout/stderr are unbuffered for Cloud Run logs
ENV PYTHONUNBUFFERED=1 \
	PIP_NO_CACHE_DIR=1 \
	PORT=8080

# Copy the dependencies file to the working directory
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the content of the local src directory to the working directory
COPY . .

# Command to run the application
# Use exec form so signals are forwarded, and add basic logging
CMD ["gunicorn", "main:app", "--bind", ":${PORT}", "--workers", "1", "--worker-class", "uvicorn.workers.UvicornWorker", "--threads", "8", "--log-level", "info", "--access-logfile", "-"]
