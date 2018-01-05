$name="fast-ai"
$cidr="0.0.0.0/0"
$ami="ami-bc508adc"
$instanceType="p2.xlarge"

$vpcId=aws ec2 create-vpc --cidr-block 10.0.0.0/28 --query 'Vpc.VpcId' --output text
aws ec2 create-tags --resources $vpcId --tags --tags Key=Name,Value=$name
aws ec2 modify-vpc-attribute --vpc-id $vpcId --enable-dns-support '{\"Value\":true}'
aws ec2 modify-vpc-attribute --vpc-id $vpcId --enable-dns-hostnames '{\"Value\":true}'
$internetGatewayId=aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text
aws ec2 create-tags --resources $internetGatewayId --tags --tags Key=Name,Value=$name-gateway
aws ec2 attach-internet-gateway --internet-gateway-id $internetGatewayId --vpc-id $vpcId
$subnetId=aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.0.0.0/28 --query 'Subnet.SubnetId' --output text
aws ec2 create-tags --resources $subnetId --tags --tags Key=Name,Value=$name-subnet
$routeTableId=aws ec2 create-route-table --vpc-id $vpcId --query 'RouteTable.RouteTableId' --output text
aws ec2 create-tags --resources $routeTableId --tags --tags Key=Name,Value=$name-route-table
$routeTableAssoc=aws ec2 associate-route-table --route-table-id $routeTableId --subnet-id $subnetId --output text
aws ec2 create-route --route-table-id $routeTableId --destination-cidr-block 0.0.0.0/0 --gateway-id $internetGatewayId
$securityGroupId=aws ec2 create-security-group --group-name $name-security-group --description "SG for fast.ai machine" --vpc-id $vpcId --query 'GroupId' --output text
aws ec2 authorize-security-group-ingress --group-id $securityGroupId --protocol tcp --port 22 --cidr $cidr
aws ec2 authorize-security-group-ingress --group-id $securityGroupId --protocol tcp --port 8888-8898 --cidr $cidr
if(!(Test-Path ~\.ssh)){mkdir ~\.ssh}
if(!(Test-Path ~\.ssh\aws-key-$name.pem)){aws ec2 create-key-pair --key-name aws-key-$name --query 'KeyMaterial' --output text | out-file -encoding ascii -filepath ~\.ssh\aws-key-$name.pem}
sp ~\.ssh\aws-key-$name.pem IsReadOnly $true
$instanceId=aws ec2 run-instances --image-id $ami --count 1 --instance-type $instanceType --key-name aws-key-$name --security-group-ids $securityGroupId --subnet-id $subnetId --associate-public-ip-address --block-device-mapping '[ { \"DeviceName\": \"/dev/sda1\", \"Ebs\": { \"VolumeSize\": 128, \"VolumeType\": \"gp2\" } } ]' --query 'Instances[0].InstanceId' --output text
aws ec2 create-tags --resources $instanceId --tags --tags Key=Name,Value=$name-gpu-machine
$allocAddr=aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text
echo "Waiting for instance start..."
aws ec2 wait instance-running --instance-ids $instanceId
sleep 10
$assocId=aws ec2 associate-address --instance-id $instanceId --allocation-id $allocAddr --query 'AssociationId' --output text
$instanceUrl=aws ec2 describe-instances --instance-ids $instanceId --query 'Reservations[0].Instances[0].PublicDnsName' --output text
aws ec2 reboot-instances --instance-ids $instanceId
echo "# Connect to your instance:" > $name-commands.txt
echo "ssh -i ~/.ssh/aws-key-$name.pem ubuntu@$instanceUrl" >> $name-commands.txt
echo "# Stop your instance: :" >> $name-commands.txt
echo "aws ec2 stop-instances --instance-ids $instanceId"  >> $name-commands.txt
echo "# Start your instance:" >> $name-commands.txt
echo "aws ec2 start-instances --instance-ids $instanceId"  >> $name-commands.txt
echo "# Reboot your instance:" >> $name-commands.txt
echo "aws ec2 reboot-instances --instance-ids $instanceId"  >> $name-commands.txt
echo ""
echo "instanceId=$instanceId" >> $name-commands.txt
echo "subnetId=$subnetId" >> $name-commands.txt
echo "securityGroupId=$securityGroupId" >> $name-commands.txt
echo "instanceUrl=$instanceUrl" >> $name-commands.txt
echo "routeTableId=$routeTableId" >> $name-commands.txt
echo "name=$name" >> $name-commands.txt
echo "vpcId=$vpcId" >> $name-commands.txt
echo "internetGatewayId=$internetGatewayId" >> $name-commands.txt
echo "subnetId=$subnetId" >> $name-commands.txt
echo "allocAddr=$allocAddr" >> $name-commands.txt
echo "assocId=$assocId" >> $name-commands.txt
echo "routeTableAssoc=$routeTableAssoc" >> $name-commands.txt

echo "aws ec2 disassociate-address --association-id $assocId" >> $name-remove.ps1
echo "aws ec2 release-address --allocation-id $allocAddr" >> $name-remove.ps1
echo "aws ec2 terminate-instances --instance-ids $instanceId" >> $name-remove.ps1
echo "aws ec2 wait instance-terminated --instance-ids $instanceId" >> $name-remove.ps1
echo "aws ec2 delete-security-group --group-id $securityGroupId" >> $name-remove.ps1
echo "aws ec2 disassociate-route-table --association-id $routeTableAssoc" >> $name-remove.ps1
echo "aws ec2 delete-route-table --route-table-id $routeTableId" >> $name-remove.ps1
echo "aws ec2 detach-internet-gateway --internet-gateway-id $internetGatewayId --vpc-id $vpcId" >> $name-remove.ps1
echo "aws ec2 delete-internet-gateway --internet-gateway-id $internetGatewayId" >> $name-remove.ps1
echo "aws ec2 delete-subnet --subnet-id $subnetId" >> $name-remove.ps1
echo "aws ec2 delete-vpc --vpc-id $vpcId" >> $name-remove.ps1
echo "echo 'If you want to delete the key-pair, please do it manually.'" >> $name-remove.ps1

echo "All done. Find all you need to connect in the $name-commands.txt file and to remove the stack call $name-remove.ps1"
echo "Connect to your instance: ssh -i ~/.ssh/aws-key-$name.pem ubuntu@$instanceUrl"