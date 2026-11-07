"""
lnu-notes: Azure adaptation for 2DV705, Assignment 2.

The application uses:
  * MariaDB for storing notes
  * Azure Blob Storage for storing images
  * Managed Identity for secure storage access

Configuration is provided through environment variables.
"""

import os
import uuid
from datetime import datetime

import pymysql
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings
from azure.core.exceptions import AzureError
from flask import Flask, redirect, render_template, request, url_for, Response

app = Flask(__name__)

# ---------------------------------------------------------------- configuration
DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_USER = os.environ.get("DB_USER", "lnu")
DB_PASS = os.environ.get("DB_PASS", "")
DB_NAME = os.environ.get("DB_NAME", "lnunotes")
AZURE_STORAGE_ACCOUNT = os.environ.get("AZURE_STORAGE_ACCOUNT", "")
AZURE_BLOB_CONTAINER = os.environ.get("AZURE_BLOB_CONTAINER", "images")
AZURE_REGION = os.environ.get("AZURE_REGION", "swedencentral")
MAX_UPLOAD_MB = int(os.environ.get("MAX_UPLOAD_MB", "5"))

app.config["MAX_CONTENT_LENGTH"] = MAX_UPLOAD_MB * 1024 * 1024

# Authenticate using Azure Managed Identity on the VM.
# No storage account keys are stored in the application.
blob_service = None

if AZURE_STORAGE_ACCOUNT:
    blob_service = BlobServiceClient(
        account_url=f"https://{AZURE_STORAGE_ACCOUNT}.blob.core.windows.net",
        credential=DefaultAzureCredential()
    )


def db():
    """Open a new database connection."""
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, user=DB_USER, password=DB_PASS, database=DB_NAME,
        connect_timeout=4, cursorclass=pymysql.cursors.DictCursor, autocommit=True,
    )


def ensure_schema():
    """Create the notes table if it does not exist."""
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """CREATE TABLE IF NOT EXISTS notes (
                   id         INT AUTO_INCREMENT PRIMARY KEY,
                   title      VARCHAR(120) NOT NULL,
                   body       TEXT,
                   image_key  VARCHAR(255),
                   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
               )"""
        )


_schema_ready = False


def schema_once():
    """Make sure the table exists before the first request that uses it."""
    global _schema_ready
    if not _schema_ready:
        ensure_schema()
        _schema_ready = True


# ---------------------------------------------------------------------- routes
@app.route("/")
def index():
    schema_once()
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM notes ORDER BY id DESC LIMIT 50")
        notes = cur.fetchall()

    for note in notes:
        note["image_url"] = (
            url_for("show_image", key=note["image_key"])
            if note["image_key"] else None
        )

    return render_template("index.html", notes=notes, bucket=AZURE_BLOB_CONTAINER, region=AZURE_REGION)



@app.route("/notes", methods=["POST"])
def create_note():
    title = (request.form.get("title") or "").strip()[:120]
    body = (request.form.get("body") or "").strip()

    if not title:
        return redirect(url_for("index"))

    schema_once()
    image_key = None
    upload = request.files.get("image")

    # Only upload if the user selected an image.
    if upload and upload.filename:
        if blob_service is None:
            raise RuntimeError("Azure Blob Storage is not configured")

        # Generate a unique filename.
        ext = os.path.splitext(upload.filename)[1].lower()[:10]
        image_key = f"uploads/{uuid.uuid4().hex}{ext}"

        # Upload the image to Azure Blob Storage.
        blob_client = blob_service.get_blob_client(
            container=AZURE_BLOB_CONTAINER,
            blob=image_key
        )

        blob_client.upload_blob(
            upload.stream,
            overwrite=False,
            content_settings=ContentSettings(
                content_type=upload.mimetype or "application/octet-stream"
            )
        )

    # Save the note in MariaDB.
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO notes (title, body, image_key) VALUES (%s, %s, %s)",
            (title, body, image_key)
        )

    return redirect(url_for("index"))



@app.route("/healthz")
def healthz():
    """Check MariaDB and Azure Blob Storage."""
    status = {
        "app": "ok",
        "time": datetime.utcnow().isoformat() + "Z",
        "region": AZURE_REGION,
        "container": AZURE_BLOB_CONTAINER,
        "db_host": DB_HOST,
    }

    try:
        with db() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
        status["database"] = "ok"
    except Exception as exc:
        status["database"] = f"FAIL: {type(exc).__name__}: {exc}"

    try:
        if blob_service is None:
            raise RuntimeError("Azure Blob Storage is not configured")

        container_client = blob_service.get_container_client(
            AZURE_BLOB_CONTAINER
        )
        container_client.get_container_properties()
        status["storage"] = "ok"
    except Exception as exc:
        status["storage"] = f"FAIL: {type(exc).__name__}: {exc}"

    ok = (
        status["database"] == "ok"
        and status["storage"] == "ok"
    )

    return status, (200 if ok else 503)



@app.route("/images/<path:key>")
def show_image(key):
    """Serve an image from a private Azure Blob container."""
    if not key.startswith("uploads/"):
        return "Invalid image path", 404

    if blob_service is None:
        return "Azure Blob Storage is not configured", 503

    try:
        blob_client = blob_service.get_blob_client(
            container=AZURE_BLOB_CONTAINER,
            blob=key
        )

        properties = blob_client.get_blob_properties()
        content_type = (
            properties.content_settings.content_type
            or "application/octet-stream"
        )

        if not content_type.startswith("image/"):
            return "Unsupported file type", 415

        image_data = blob_client.download_blob().readall()

        return Response(
            image_data,
            mimetype=content_type,
            headers={"Cache-Control": "no-store"}
        )

    except AzureError:
        app.logger.exception("Failed to retrieve image from Blob Storage")
        return "Image could not be retrieved", 502


if __name__ == "__main__":
    try:
        ensure_schema()
    except Exception as exc:
        print(
            f"Schema check failed ({exc}) - "
            "/healthz will show the problem"
        )

    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "8000")),
        debug=False
    )
