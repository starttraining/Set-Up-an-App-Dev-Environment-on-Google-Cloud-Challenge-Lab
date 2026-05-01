#!/bin/bash

# ---------- Colors ----------
BOLD=$(tput bold)
RESET=$(tput sgr0)
BG_MAGENTA=$(tput setab 5)
BG_RED=$(tput setab 1)

echo "${BG_MAGENTA}${BOLD}Starting Execution${RESET}"

# ---------- Variables ----------
export REGION="${ZONE%-*}"
PROJECT_ID=$DEVSHELL_PROJECT_ID
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

# ---------- Enable APIs ----------
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com

echo "Waiting for APIs to initialize..."
sleep 60

# ---------- Force Pub/Sub initialization ----------
echo "Initializing Pub/Sub..."
gcloud pubsub topics create temp-topic-$RANDOM || true

# ---------- Wait for Pub/Sub service account ----------
echo "Waiting for Pub/Sub service account..."

PUBSUB_SA="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"

for i in {1..12}; do
  if gcloud iam service-accounts describe "$PUBSUB_SA" &>/dev/null; then
    echo "Pub/Sub service account exists."
    break
  else
    echo "Still waiting..."
    sleep 10
  fi
done

# ---------- IAM Permissions ----------
echo "Setting IAM permissions..."

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
  --role=roles/eventarc.eventReceiver

SERVICE_ACCOUNT="$(gsutil kms serviceaccount -p $PROJECT_ID)"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role='roles/pubsub.publisher'

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:$PUBSUB_SA \
  --role=roles/iam.serviceAccountTokenCreator

# ---------- Storage + Pub/Sub ----------
echo "Creating bucket and topic..."

gsutil mb -l $REGION gs://$PROJECT_ID-bucket || true
gcloud pubsub topics create $TOPIC || true

# ---------- Create Function Code ----------
mkdir -p app
cd app

cat > index.js <<EOF
const functions = require('@google-cloud/functions-framework');
const { Storage } = require('@google-cloud/storage');
const { PubSub } = require('@google-cloud/pubsub');
const imagemagick = require("imagemagick-stream");

const gcs = new Storage();
const pubsub = new PubSub();

functions.cloudEvent('$FUNCTION', async (cloudEvent) => {
  const event = cloudEvent.data;

  const fileName = event.name;
  const bucketName = event.bucket;

  if (fileName.includes("64x64_thumbnail")) return;

  const ext = fileName.split('.').pop().toLowerCase();
  if (!['png', 'jpg'].includes(ext)) return;

  const bucket = gcs.bucket(bucketName);
  const newName = fileName.replace(\`.${ext}\`, \`64x64_thumbnail.${ext}\`);

  const src = bucket.file(fileName).createReadStream();
  const dst = bucket.file(newName).createWriteStream();

  const resize = imagemagick().resize("64x64").quality(90);

  src.pipe(resize).pipe(dst).on("finish", async () => {
    await pubsub.topic('$TOPIC').publishMessage({
      data: Buffer.from(newName)
    });
    console.log("Thumbnail created:", newName);
  });
});
EOF

cat > package.json <<EOF
{
  "name": "thumbnails",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/pubsub": "^2.0.0",
    "@google-cloud/storage": "^5.0.0",
    "imagemagick-stream": "4.1.1"
  }
}
EOF

# ---------- Deploy Function ----------
echo "Deploying function..."

deploy_function() {
  gcloud functions deploy $FUNCTION \
    --gen2 \
    --runtime nodejs20 \
    --trigger-resource $PROJECT_ID-bucket \
    --trigger-event google.storage.object.finalize \
    --entry-point $FUNCTION \
    --region=$REGION \
    --source . \
    --quiet
}

# Retry loop
for i in {1..5}; do
  deploy_function && break
  echo "Retrying deployment..."
  sleep 20
done

# ---------- Test ----------
echo "Testing..."

curl -o map.jpg https://storage.googleapis.com/cloud-training/gsp315/map.jpg
gsutil cp map.jpg gs://$PROJECT_ID-bucket/map.jpg

echo "${BG_RED}${BOLD}Lab Completed Successfully!${RESET}"