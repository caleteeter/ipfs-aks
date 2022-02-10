| spec topic              | author      | type                      | status    |
| ----------------------- | ----------- | ------------------------- | --------- |
| IPFS Network Management | Cale Teeter | architecture requirements | draft 0.1 |

|

# Purpose

Using AKS on Azure for the private IPFS networks automates the deployment of the solution, however a few things are required to properly enable network management of these networks. For example, creating a new network is less complex than joining an existing network. The components for the application (IPFS) are well understood and can be shared for joining, however there are some core infrastructure details that need to be considered.

- New networks establish node(s) that run the IPFS service.

- New networks establish a new swarm key that is shared with any nodes that participate in this network.

- Joining the network requires a few things

  - Swarm key for the IPFS network. This is a 64 character alphanumeric string that is unique to the network.

  - Boot node IP address. This is a node that is running with this swarm key that the new node will communicate with.

  - IP Addresss space. Using AKS, which uses Azure Virtual Network, requires unique address spaces when using vnet peering to connect networks. These cannot overlap.

# Goals

| Goal                       | Timeline (needed by) |
| -------------------------- | -------------------- |
| **Enable network joining** | July 2021 Sprint     |

# Requirements

| Requirement                                                |
| ---------------------------------------------------------- |
| **P0** - Update template to allow joining existing network |

## Core spec

The core changes here will be to the following:

- Update the bicep definition to include 2 new parameters.

  - Add a required parameter that will have 2 options (a) create new network and (b) join existing network

  - Add an required parameter, when joining a network, to include invitation string.

The first new parameter will be used to let the template know that a new swarm key will not be required and that another parameter, the invitation string, will be used for provisioning.

The second new parameter will be used to communicate the following the joining member:

- The swarm key that will be used to join the network. This was generated by the member that invited the new member.

- The address range to use to avoid conflicts that will allow vnet peering, which will be required for operation.

- The boot node ip that will be used to establish the connection to the network.

The invitation string mentioned above will be generated by the member inviting the new member. The swarm key and boot node ip are static for the network. The address range usage will change as members join the network. To avoid using additional technology to store the state required to ensure non-conflicting network address spaces, the IPFS network can be used to store this state.

### IPFS state storage

IPFS provides a simple interface to store data in immutable form, in the simpliest form, a file can be sent to IPFS and a content hash returned to retrieve the data. For the network management in this spec, the desire would be to have the hash stay the same as the content is updated. IPFS provides support for MFS (Mutable File System), which will allow the same immutable storage, but presented via a Unix file system like interface. This allows storage of the state needed to be accessed like a file.

## Invitation interface

The invitation interface will be provided by an extension to the Azure CLI tools. Using the Azure CLI tools will enable easier interaction with the Azure assets used here. Primarily, when inviting the new member, a security principal will need to be created that will allow the invited user access to peer the networks.