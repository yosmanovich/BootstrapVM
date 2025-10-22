
## I just want to get this running

### Open a Cloudshell in the Azure Portal

Log into Azure via the portal. 
Once in, open a Cloud Shell - this can be done by clicking the cloudshell button on the upper bar.

At the Welcome to Azure Cloud Shell message, click *PowerShell* 

At the Getting started screen, select *No storage account required*, click *Apply*

Azure will provision a cloud shell and you will soon have a prompt.

### Clone the repository and Deploy the resources
Running the 
   ```bash
   git clone https://github.com/yosmanovich/BootstrapVM.git
   cd BootstrapVM/DeploymentScripts
   .\Deploy.ps1
   ```
For Azure Deployments
You *must* configure all the properties

Once the VM deploys, run the Bootstrap twice. The first time Bootstrap runs, it will install WSL and restart. The second time Bootstrap runs, it will install all the other required software and reboot the VM again.

Connect to the VM and open VS Code and the WSL terminal. Follow the instructions of logging into Azure Portal and connecting to Git Hub. 

Configure the env file and run the make deploy. Once the verification check for the network connections opens, before you hit y run the CreatePeerting.ps1 script.

   ```bash
   cd BootstrapVM/DeploymentScripts
   .\CreatePeerting.ps1
   ```

This will create a VNet peering and set the DNS to point to the private DNS on the Info Assist Vnet.

Once this script completes, you may continue with the deployment process.
