$instanceName="fastai-instance"
$addressName="ip-address"
$projectId=gcloud config get-value core/project
$region=gcloud config get-value compute/region
$zone=gcloud config get-value compute/zone

echo "Creating static IP address..."
gcloud compute --project $projectId addresses create $addressName --region $region

$ipAddress=gcloud compute addresses describe $addressName --region=$region --format='value(address)'

echo "Creating virtual machine in $zone operating Ubuntu 16.04 LTS, 32GB RAM / 128GB SSD / Tesla K80 GPU..."
gcloud compute --project $projectId instances create $instanceName --zone $zone --address=$ipAddress --machine-type "custom-1-32768-ext" --subnet "default" --maintenance-policy "TERMINATE" --no-service-account --no-scopes --accelerator type=nvidia-tesla-k80,count=1 --min-cpu-platform "Intel Broadwell" --tags "http-server","https-server","jupyter" --image "ubuntu-1604-xenial-v20171212" --image-project "ubuntu-os-cloud" --boot-disk-size "128" --boot-disk-type "pd-ssd" --boot-disk-device-name $instanceName

gcloud compute --project=$projectId firewall-rules create default-allow-http --network=default --action=ALLOW --rules=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=http-server

gcloud compute --project=$projectId firewall-rules create default-allow-https --network=default --action=ALLOW --rules=tcp:443 --source-ranges=0.0.0.0/0 --target-tags=https-server

gcloud compute --project=$projectId firewall-rules create default-allow-jupyter --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:8888-8898 --source-ranges=0.0.0.0/0 --target-tags=jupyter

echo "# Connect to your instance:" >> $instanceName-commands.txt
echo "gcloud compute --project $projectId ssh --zone $zone $instanceName" >> $instanceName-commands.txt
echo "# Stop your instance: :" >> $instanceName-commands.txt
echo "gcloud compute instances stop $instanceName"  >> $instanceName-commands.txt
echo "# Start your instance:" >> $instanceName-commands.txt
echo "gcloud compute instances start $instanceName"  >> $instanceName-commands.txt
echo "# Reboot your instance:" >> $instanceName-commands.txt
echo "gcloud compute instances reset $instanceName"  >> $instanceName-commands.txt
echo "# Address for Jupyter notebook in your browser:" >> $instanceName-commands.txt
echo "IP Address: $ipAddress" >> $instanceName-commands.txt

echo "gcloud compute firewall-rules delete default-allow-jupyter" >> $instanceName-remove.ps1
echo "gcloud compute firewall-rules delete default-allow-https" >> $instanceName-remove.ps1
echo "gcloud compute firewall-rules delete default-allow-http" >> $instanceName-remove.ps1
echo "gcloud compute instances delete $instanceName" >> $instanceName-remove.ps1
echo "gcloud compute addresses delete $addressName" >> $instanceName-remove.ps1

echo "All done. Find all you need to connect in the $instanceName-commands.txt file and to remove the stack call $instanceName-remove.ps1"
echo "Connect to your instance: gcloud compute --project $projectId ssh --zone $zone $instanceName"
