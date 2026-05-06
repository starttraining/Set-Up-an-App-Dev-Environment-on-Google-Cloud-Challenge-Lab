# Set Up an App Dev Environment on Google Cloud: Challenge Lab 

##Google Lab: https://www.skills.google/course_templates/637/labs/592550

### Run the following Commands in CloudShell

```
export USER_2=
export ZONE=
export TOPIC=
export FUNCTION=
gcloud config set project <project id>

gcloud beta services identity create \
  --service=pubsub.googleapis.com \
  --project=<project id>

```
```
curl -LO https://raw.githubusercontent.com/starttraining/Set-Up-an-App-Dev-Environment-on-Google-Cloud-Challenge-Lab/main/gsp315.sh

sudo chmod +x gsp315.sh

./gsp315.sh
```
 
 
