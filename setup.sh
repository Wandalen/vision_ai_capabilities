#!/usr/bin/env wrun

OWNER_PREFIX=${OWNER_PREFIX:-wan}
PROJECT_NAME=${PROJECT_NAME:-vission-simple}
PROJECT_ID="${PROJECT_ID:-"${OWNER_PREFIX}-${PROJECT_NAME}"}"
DEFAULT_PROJECT_ID="${DEFAULT_PROJECT_ID:-"${OWNER_PREFIX}-default"}"

# = create a new project for this

if gcloud projects describe $PROJECT_ID > /dev/null 2>&1
then
  echo "Project $PROJECT_ID exists"
else
  gcloud projects create $PROJECT_ID --name $PROJECT_NAME
fi

gcloud config set project $PROJECT_ID

# = find out URL of the API
# gcloud services list --available | grep vision

# = enable API

gcloud services enable vision.googleapis.com
gcloud services enable visionai.googleapis.com
gcloud services enable storage-api.googleapis.com
gcloud services enable storage-component.googleapis.com
gcloud services enable storage-component.googleapis.com
gcloud services enable cloudbilling.googleapis.com
gcloud services enable translate.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable pubsublite.googleapis.com

# = set billing account for the project if it's not set yet

local billing_account="$( gcloud beta billing projects describe $PROJECT_ID --format="value(billingAccountName.basename())" )"
if [[ -z $billing_account ]]
then
  GOOGLE_BILLING_ACCOUNT="${GOOGLE_BILLING_ACCOUNT:-"$( gcloud beta billing projects describe $DEFAULT_PROJECT_ID --format="value(billingAccountName.basename())" )"}"
  gcloud beta billing projects link $PROJECT_ID --billing-account=$GOOGLE_BILLING_ACCOUNT
fi

# = create 2 buckets

TOPIC_INPUT=${TOPIC_INPUT:-${PROJECT_ID}-input}
BUCKET_INPUT=${BUCKET_INPUT:-gs://$TOPIC_INPUT}
if gsutil ls $BUCKET_INPUT &>/dev/null
then
  echo "Bucket $BUCKET_INPUT exists"
else
  echo "Bucket $BUCKET_INPUT does not exist"
  gcloud storage buckets create $BUCKET_INPUT
fi

TOPIC_OUTPUT=${TOPIC_OUTPUT:-${PROJECT_ID}-output}
BUCKET_OUTPUT=${BUCKET_OUTPUT:-gs://$TOPIC_OUTPUT}
if gsutil ls $BUCKET_OUTPUT &>/dev/null
then
  echo "Bucket $BUCKET_OUTPUT exists"
else
  echo "Bucket $BUCKET_OUTPUT does not exist"
  gcloud storage buckets create $BUCKET_OUTPUT
fi

# = create pub/sub topics

local exist="$( gcloud pubsub topics list --filter=name:${TOPIC_INPUT} )"
if [ -z "$exist" ]
then
  gcloud pubsub topics create ${TOPIC_INPUT}
  echo "Topic '${TOPIC_INPUT}' created."
else
  echo "Topic '${TOPIC_INPUT}' already exists."
fi

local exist="$( gcloud pubsub topics list --filter=name:${TOPIC_OUTPUT} )"
if [ -z "$exist" ]
then
  gcloud pubsub topics create ${TOPIC_OUTPUT}
  echo "Topic '${TOPIC_OUTPUT}' created."
else
  echo "Topic '${TOPIC_OUTPUT}' already exists."
fi

# = clone repo

local tmp_dir && tmp_dir="$(mktemp -d)"
cd $tmp_dir
# git clone https://github.com/linuxacademy/content-gc-functions-deepdive repo
git clone git@github.com:Wandalen/vision_ai_capabilities.git repo
cd repo
ls -al

# = update functions

gcloud config set functions/region us-east1

gcloud functions deploy ${PROJECT_ID}-process-image \
  --region=us-east1 \
  --runtime=python39 \
  --source=./ \
  --entry-point=process_image \
  --trigger-event="google.storage.object.finalize" \
  --trigger-resource="$BUCKET_INPUT" \

gcloud functions deploy ${PROJECT_ID}-translate-text \
  --region=us-east1 \
  --runtime=python39 \
  --source=. \
  --entry-point=translate_text \
  --trigger-event="providers/cloud.pubsub/eventTypes/topic.publish" \
  --trigger-resource="$TOPIC_INPUT"

gcloud functions deploy ${PROJECT_ID}-save-result \
  --region=us-east1 \
  --runtime=python39 \
  --source=. \
  --entry-point=save_result \
  --trigger-event="providers/cloud.pubsub/eventTypes/topic.publish" \
  --trigger-resource="$TOPIC_OUTPUT"

# = upload files to the bucket

local name='cat.jpg'
local url='https://i.pinimg.com/736x/21/10/10/211010ae2843472089e2a42a24e5ad5a--goldfish-funny-cats.jpg'
curl \
  --silent \
  --show-error \
  --location \
  "$url" \
  | gsutil cp - "$BUCKET_INPUT/$name"

# = upload files to process them

set -x
gsutil ls $BUCKET_INPUT
gsutil cp -r "./images" $BUCKET_INPUT
gsutil ls $BUCKET_OUTPUT

# =
