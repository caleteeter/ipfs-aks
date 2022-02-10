#!/bin/bash

managedIdentity=$1
aksClusterName=$2
resourceGroupName=$3
storageAccountName=$4
fileShareName=$5
persistentDiskName=$6
swarmKeyValue=$7

# install the k8s tools
az aks install-cli

# login
az login --identity --username $managedIdentity

# get k8s credentials for deployment
az aks get-credentials --name $aksClusterName --resource-group $resourceGroupName

# Create a folder to store the credentials for this storage account and
# any other that you might set up.
credentialRoot="/etc/smbcredentials"
mkdir -p "/etc/smbcredentials"

# Get the storage account key for the indicated storage accout
# You must be logged in with az login and your user identity must have
# permissions to list the storage account keys for this command to work.
storageAccountKey=$(az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query "[0].value" | tr -d '"')

# Create the credential file for this individual storage account
smbCredentialFile="$credentialRoot/$storageAccountName.cred"
if [ ! -f $smbCredentialFile ]; then
    echo "username=$storageAccountName" | tee $smbCredentialFile > /dev/null
    echo "password=$storageAccountKey" | tee -a $smbCredentialFile > /dev/null
else
    echo "The credential file $smbCredentialFile already exists, and was not modified."
fi

# Change permissions on the credential file so only root can read or modify the password file.
chmod 600 $smbCredentialFile

mntRoot="/mount"
mntPath="$mntRoot/$storageAccountName/$fileShareName"
mkdir -p $mntPath

httpEndpoint=$(az storage account show --resource-group $resourceGroupName --name $storageAccountName --query "primaryEndpoints.file" | tr -d '"')
smbPath=$(echo $httpEndpoint | cut -c7-$(expr length $httpEndpoint))$fileShareName

mount -t cifs $smbPath $mntPath -o username=$storageAccountName,password=$storageAccountKey,serverino

# generate swarm key
echo "/key/swarm/psk/1.0.0/" > swarm.key
echo "/base16/" >> swarm.key
if [ ! $swarmKeyValue ]; then
    swarmKeyValue=$(echo -e "`tr -dc 'a-f0-9' < /dev/urandom | head -c64`")
    echo $swarmKeyValue >> swarm.key
else
    echo -e $swarmKeyValue >> swarm.key
fi

# persist the key to storage for use by k8s
cp swarm.key $mntPath/

# get the k8s ipfs deployment configuration
wget https://raw.githubusercontent.com/caleteeter/ipfs-aks/master/k8s/ipfs-pv.yaml
wget https://raw.githubusercontent.com/caleteeter/ipfs-aks/master/k8s/ipfs-pvc.yaml
wget https://raw.githubusercontent.com/caleteeter/ipfs-aks/master/k8s/ipfs.yaml
wget https://raw.githubusercontent.com/caleteeter/ipfs-aks/master/k8s/ipfs-service.yaml

echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
apk update
apk add yq

managedResourceGroup=$(az aks show --resource-group $resourceGroupName --name $aksClusterName --query nodeResourceGroup --output tsv) 
diskId=$(az disk create --resource-group $managedResourceGroup --name $persistentDiskName --size-gb 20 --query id --output tsv)
export MANAGED_DISK_ID=$diskId

# patch ipfs manifest
yq eval '.spec.template.spec.volumes[1].azureDisk.diskURI = "'$MANAGED_DISK_ID'"' -i ipfs.yaml
yq eval '.spec.template.spec.volumes[1].azureDisk.diskName = "'$persistentDiskName'"' -i ipfs.yaml
cat ipfs-service.yaml >> ipfs.yaml
cp ipfs.yaml $mntPath/

# patch filename
yq eval '.spec.azureFile.shareName = "'$fileShareName'"' -i ipfs-pv.yaml

# add secret to allow storage integration to Azure
kubectl create secret generic azure-secret --from-literal=azurestorageaccountname=$storageAccountName --from-literal=azurestorageaccountkey=$storageAccountKey

# run deployment
kubectl apply -f ipfs-pv.yaml
kubectl apply -f ipfs-pvc.yaml
kubectl apply -f ipfs.yaml

# get the ip
internalIp=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[1].address}")
ipfsPort=$(kubectl get svc ipfs-internal -o=jsonpath='{.spec.ports[?(@.port==4001)].nodePort}')
httpPort=$(kubectl get svc ipfs-internal -o=jsonpath='{.spec.ports[?(@.port==5001)].nodePort}')
jq -n --arg intIp $internalIp --arg skey $swarmKeyValue --arg intPort $ipfsPort --arg htPort $httpPort '{"internalIp": $intIp, "swarmKey": $skey, "ipfsPort": $intPort, "httpPort": $htPort }' > $AZ_SCRIPTS_OUTPUT_PATH