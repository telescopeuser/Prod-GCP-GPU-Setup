echo "Fast.ai v2 virtual machine instance setup on Google Cloud Platform. Requires Google Cloud SDK to be already installed."
echo ""
echo "Obtaining your current Google Cloud project settings..."

$account=gcloud config get-value core/account
$projectId=gcloud config get-value core/project
$addressName="fastai-ip-address-"
$instanceName="fastai-instance-"

If($LASTEXITCODE -eq 0){
	If($account -eq $null -or $projectId -eq $null){
		echo "Unable to obtain project settings. Please run 'gcloud init' then re-run this script."
	}
	Else{
		$projectName=gcloud projects list --filter="project_id=$projectId" --format="value(name)"
		$region=gcloud config get-value compute/region
		$zone=gcloud config get-value compute/zone

		echo "Project ID: $projectId"
		echo "Project Name: $projectName"
		echo "Zone: $zone"
		echo ""

		$gpuZones=gcloud compute accelerator-types list --filter="name:('nvidia-tesla-k80')" --format="table(zone:sort=1)"

		If ($gpuZones -notcontains $zone){
			echo "Your current Compute Engine zone $zone does not support NVIDIA K80 GPU instances. Only the following zones are supported:"
			echo $gpuZones
			echo ""
			echo "Please run 'gcloud init' to configure your Compute Engine zone, then re-run this script."	
		}
		Else{
			echo "Checking your region limit for NVIDIA K80 GPU instances..."
			$regionInfo = gcloud compute regions list --filter="name=($region)" --format='json' | ConvertFrom-Json
			$k80 = $regionInfo.quotas | where {$_.metric -eq "NVIDIA_K80_GPUS"}
			echo "The NVIDIA K80 GPU quota limit for $region is $($k80.limit) and you have used $($k80.usage)."
			echo "" 

			# Check quota limit 
			If ([int]$k80.usage -eq [int]$k80.limit){
				echo "You have reached your NVIDIA K80 GPU quota limit for your current region $region." 
				echo "Please visit https://console.cloud.google.com/iam-admin/quotas to request for a quota increase, then re-run this script."
			}
			Else{
				echo "Checking your region limit for static IP addresses..."
				$staticIP=$regionInfo.quotas | where {$_.metric -eq "STATIC_ADDRESSES"}
				echo "The static IP address quota limit for $region is $($staticIP.limit) and you have used $($staticIP.usage)."
				echo ""

				If([int]$staticIP.usage -eq [int]$staticIP.limit){
					echo "You have reached your Static IP Address quota limit for your current region $region. Please release a static IP address or request for a quota increase, then re-run this script."
				}
				Else{
					$addresses=gcloud compute addresses list --format="table(name)"
					$x=1
					while ($addresses -contains $addressName+$x){
						$x+=1
					}
					$addressName+=$x
					echo "Attempting to obtain static IP address..."
					gcloud compute --project $projectId addresses create $addressName --region $region
					
					If($LASTEXITCODE -eq 0){
						gcloud compute addresses list --filter="name=($addressName)"
						$ipAddress=gcloud compute addresses describe $addressName --region=$region --format='value(address)'
						echo ""

						$instances=gcloud compute instances list --format="table(name)"
						$x=1
						while ($instances -contains $instanceName+$x){
							$x+=1
						}
						$instanceName+=$x
						echo "Attempting to create instance in $zone on Ubuntu 16.04 LTS/ 4-vCPU/ 26GB RAM/ 50GB SSD/ Tesla K80 GPU..."
						gcloud compute --project $projectId instances create $instanceName --zone $zone --address=$ipAddress --machine-type "n1-highmem-4" --subnet "default" --maintenance-policy "TERMINATE" --service-account default --scopes default --accelerator type=nvidia-tesla-k80,count=1 --min-cpu-platform "Intel Broadwell" --tags "jupyter","http-server","https-server" --image "ubuntu-1604-xenial-v20171212" --image-project "ubuntu-os-cloud" --boot-disk-size "50" --boot-disk-type "pd-ssd" --boot-disk-device-name $instanceName

						If(-Not $LASTEXITCODE -eq 0){
							echo ""
							echo "Failed to create instance. Releasing static IP address..."
							gcloud compute addresses delete $addressName
						}
						Else{
							gcloud compute addresses list --filter="name=($addressName)"
							echo ""
							echo "Obtaining pre-existing firewall rules..."
							echo ""
							$firewallInfo=gcloud compute firewall-rules list --format="json" | ConvertFrom-Json
							$http=$false
							$https=$false
							$jupyter=$false

							$firewallInfo.allowed | foreach { $rule=$_;
								If ($($rule.IPProtocol) -eq "tcp" -and $($rule.ports) -eq '80'){
									$http=$true
									echo "Found pre-existing rule: Allow tcp/80 (http). Please check in the console that the rule applies to all instances or instances with the 'http' tag."
									echo ""
								}
								ElseIf ($($rule.IPProtocol) -eq "tcp" -and $($rule.ports) -eq '443'){
									$https=$true
									echo "Found pre-existing rule: Allow tcp/443 (https). Please check in the console that the rule applies to all instances or instances with the 'https-server' tag."
									echo ""
								}
								ElseIf ($($rule.IPProtocol) -eq "tcp" -and $($rule.ports) -like '*8888*'){
									$jupyter=$true
									echo "Found existing rule: Allow tcp/8888 (jupyter). Please check in the console that the rule applies to all instances or instances with the 'jupyter' tag."
									echo ""
								}
							}
							If(-Not $http){
								gcloud compute --project=$projectId firewall-rules create default-allow-http --network=default --action=ALLOW --rules=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=http-server
							}
							If(-Not $https){
								gcloud compute --project=$projectId firewall-rules create default-allow-https --network=default --action=ALLOW --rules=tcp:443 --source-ranges=0.0.0.0/0 --target-tags=https-server
							}
							If(-Not $jupyter){
								gcloud compute --project=$projectId firewall-rules create default-allow-jupyter --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:8888 --source-ranges=0.0.0.0/0 --target-tags=jupyter
							}
							echo "# Connect to your instance:" >> $instanceName-commands.txt
							echo "gcloud compute --project $projectId ssh --zone $zone $instanceName" >> $instanceName-commands.txt
							echo "" >> $instanceName-commands.txt
							echo "# Alternative command to connect (using your default project and zone):" >> $instanceName-commands.txt
							echo "gcloud compute ssh $instanceName" >> $instanceName-commands.txt
							echo "" >> $instanceName-commands.txt
							echo "# Stop your instance: :" >> $instanceName-commands.txt
							echo "gcloud compute instances stop $instanceName"  >> $instanceName-commands.txt
							echo "" >> $instanceName-commands.txt
							echo "# Start your instance:" >> $instanceName-commands.txt
							echo "gcloud compute instances start $instanceName"  >> $instanceName-commands.txt
							echo "" >> $instanceName-commands.txt
							echo "# Reboot your instance:" >> $instanceName-commands.txt
							echo "gcloud compute instances reset $instanceName"  >> $instanceName-commands.txt
							echo "" >> $instanceName-commands.txt
							echo "# Address for Jupyter notebook in your browser:" >> $instanceName-commands.txt
							echo "IP Address: $ipAddress" >> $instanceName-commands.txt

							echo "gcloud compute firewall-rules delete default-allow-jupyter" >> $instanceName-remove.ps1
							echo "gcloud compute instances delete $instanceName" >> $instanceName-remove.ps1
							echo "gcloud compute addresses delete $addressName" >> $instanceName-remove.ps1

							echo ""
							echo "All done. Find the commands to connect in the $instanceName-commands.txt file. To remove the stack run $instanceName-remove.ps1"
							echo ""

							echo "To connect to your instance: gcloud compute ssh $instanceName"
							echo ""
							echo "Launching Google Cloud online console in browser..."

							Invoke-Expression "cmd.exe /C start https://console.cloud.google.com/compute/instances?project=$projectId"
						}
				
					}

				}
				
			}
		}	
	}
} 

Write-Host "Press any key to continue ....."
$x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")	

	
