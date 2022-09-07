
# Startup Script used for the first-time initialization of GCP services.
# Reference: https://github.com/googleforgames/open-saves/blob/main/docs/deploying.md
# NOTE: This command was developed and tested within Google Cloud Shell.

# Enable GCP APIs
gcloud services enable  datastore.googleapis.com \
                        redis.googleapis.com \
                        run.googleapis.com \
                        storage-component.googleapis.com \
                        vpcaccess.googleapis.com

# Set environment variables
export OPEN_SAVES_GSA=~/secret-air-360419-a142fdcafd79.json
export GCP_PROJECT=$(gcloud config get-value project)
export GCP_REGION=us-central1
export GCP_ZONE=us-central1-c
export GCS_BUCKET="$GCP_PROJECT-open-saves"
export BUCKET_PATH="gs://$GCS_BUCKET"
export REDIS_ID=open-saves-redis
export REDIS_PORT="6379"
export REDIS_TIER="standard"    # basic or standard (HA with replication)
export REDIS_SIZE=5             # The memory size of the instance in GiB. If not provided, size of 1 GiB will be used.
export REDIS_READ_REPLICA_MODE=read-replicas-enabled    # read-replicas-disabled or read-replicas-enabled NOTE: Requires Size to be 5 (GB) or larger
export VPC_CONNECTOR=open-saves-vpc
export VPC_NETWORK="default"
export TAG=gcr.io/triton-for-games-dev/triton-server:testing
export SERVICE_NAME="open-saves"

##############################################
#
#   Memorystore (Redis)
#
##############################################

# Create a Redis instance by using Memorystore
gcloud redis instances create --size=$REDIS_SIZE --region=$GCP_REGION --tier=$REDIS_TIER $REDIS_ID

# Find and the private IP address of the Memorystore instance.
export REDIS_IP=$(gcloud redis instances describe --region=$GCP_REGION $REDIS_ID --format="value(host)")

# Check for network name consistency
echo Check to make sure networks match. Does $VPC_NETWORK == $(gcloud redis instances describe $REDIS_ID --region $GCP_REGION --format "value(authorizedNetwork)")?

##############################################
#
#   VPC
#
##############################################

# Create the VPC Connector
gcloud compute networks vpc-access connectors create $VPC_CONNECTOR \
--network $VPC_NETWORK \
--region $GCP_REGION \
--range 10.8.0.0/28

# Verify that your connector is in the READY state before using it
gcloud compute networks vpc-access connectors describe $VPC_CONNECTOR --region $GCP_REGION

##############################################
#
#   Datastore / Firestore
#
##############################################

# Create a Firestore DB (in Datastore mode)
read  -n 1 -p "Create a Firestore DB in Datastore mode, then press any key: " tmpvar1

# Deploy the Datastore index (from the root of the Open Saves repo)
gcloud datastore indexes create deploy/datastore/index.yaml

##############################################
#
#   Datastore / Firestore
#
##############################################
gsutil mb $BUCKET_PATH

##############################################
#
#   Deploy Application
#
##############################################
gcloud beta run deploy $SERVICE_NAME \
                  --platform=managed \
                  --region=$GCP_REGION \
                  --image=$TAG \
                  --set-env-vars="OPEN_SAVES_BUCKET="$BUCKET_PATH \
                  --set-env-vars="OPEN_SAVES_PROJECT="$GCP_PROJECT \
                  --set-env-vars="OPEN_SAVES_CACHE"=$REDIS_IP":"$REDIS_PORT \
                  --allow-unauthenticated \
                  --vpc-connector $VPC_CONNECTOR \
                  --use-http2

# Export Cloud Run Endpoint to Env Var
export ENDPOINT=$(\
gcloud run services list \
  --project=$GCP_PROJECT \
  --region=$GCP_REGION \
  --platform=managed \
  --format="value(status.address.url)" \
  --filter="metadata.name="$SERVICE_NAME)

ENDPOINT=${ENDPOINT#https://} && echo ${ENDPOINT}

##############################################
#
#   Test with Client
#
##############################################
go run examples/grpc-client/main.go -address=$ENDPOINT:443
