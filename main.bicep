@description('Azure region that will be targeted for resources.')
param location string = resourceGroup().location

@description('Member id')
param memberId int = 1

@description('Shared swarm key value')
param swarmKeyValue string = ''

var aksUserRoleId = '4abbcc35-e782-43d8-92c5-2d3f1bd2253f'
var storageContribRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var persistentDiskName = '${uniqueString(resourceGroup().id)}dsk'
var fileShareName = '${uniqueString(resourceGroup().id)}shr'

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: '${uniqueString(resourceGroup().id)}str'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'

  resource fileService 'fileServices' = {
    name: 'default'

    resource fileShare 'shares' = {
      name: fileShareName
    }
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${uniqueString(resourceGroup().id)}mi'
  location: location
}

resource aksVirtualNetwork 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: '${uniqueString(resourceGroup().id)}${memberId}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.${memberId}.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.${memberId}.${memberId}.0/24'
        }
      }
    ]
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2021-03-01' = {
  name: '${uniqueString(resourceGroup().id)}aks'
  location: location
  dependsOn: [
    aksVirtualNetwork
  ]
  properties: {
    dnsPrefix: '${uniqueString(resourceGroup().id)}aks'
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 1
        vmSize: 'Standard_DS2_v2'
        mode: 'System'
        vnetSubnetID: resourceId('Microsoft.Network/virtualNetworks/subnets/', aksVirtualNetwork.name, 'default')
      }
    ]
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

resource aksRoleAssignment 'Microsoft.Authorization/roleAssignments@2021-04-01-preview' = {
  name: '${guid(uniqueString(resourceGroup().id), 'aks')}'
  dependsOn: [
    managedIdentity
    aks
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', aksUserRoleId)
    description: 'Assign the cluster user-defined managed identity contributor role on the resource group.'
    principalId: '${reference(managedIdentity.id).principalId}'
    scope: resourceGroup().id
    principalType: 'ServicePrincipal'
  }
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2021-04-01-preview' = {
  name: '${guid(uniqueString(resourceGroup().id), 'storage')}'
  dependsOn: [
    managedIdentity
    storageAccount
  ]
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageContribRoleId)
    description: 'Assign the storage user-defined managed identity contributor role on the resource group.'
    principalId: '${reference(managedIdentity.id).principalId}'
    scope: resourceGroup().id
    principalType: 'ServicePrincipal'
  }
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${uniqueString(resourceGroup().id)}dpy'
  location: location
  dependsOn: [
    aks
  ]
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    arguments: '${managedIdentity.id} ${aks.name} ${resourceGroup().name} ${storageAccount.name} ${fileShareName} ${persistentDiskName} ${swarmKeyValue}'
    forceUpdateTag: '1'
    containerSettings: {
      containerGroupName: '${uniqueString(resourceGroup().id)}ci1'
    }
    primaryScriptUri: 'https://raw.githubusercontent.com/caleteeter/ipfs-aks/master/scripts/deploy.sh'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    azCliVersion: '2.9.1'
    retentionInterval: 'P1D'
  }
}

output result object = reference('${uniqueString(resourceGroup().id)}dpy').outputs
