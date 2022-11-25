az login --tenant # set tenant if required
$subscription="<subscriptionId>" # add subscription here

az account set -s $subscription # ...or use 'az login'










$dbname='craftdb'
echo $rgname
echo $acrname
 
# create resource group and base variables 
$subscriptionid= az account show --query id --output tsv
echo $subscriptionid
$prefix='ahmsc'
$rgname=$prefix+'rg'
$location='westeurope'
az group create --name $rgname --location $location

# end create resource group

# setup acr
$acrname=$prefix+'acr'
az acr create --resource-group $rgname --name $acrname --sku Basic --admin-enabled true
az acr credential show --resource-group $rgname --name  $acrname
$acrusername=az acr credential show -n $acrname --query username -g $rgname -o tsv
$acrpassword=az acr credential show -n $acrname  -g $rgname  --query passwords[0].value -o tsv
echo $acrusername
echo $acrpassword

# end setup acr


# setup mysql
$mysqlServerName=$prefix+'mysql'
$login='dbadmin'
$password='password'  #put in your password here.There are issues on encoding password with dollars in container apps, so rather not have it
$sku="Standard_B1ms"
$tier="Burstable"
$startIp='0.0.0.0'
$endIp='0.0.0.0'


az mysql flexible-server create -g $rgname -n $mysqlServerName   --admin-user $login --admin-password $password   -l $location  --public-access $startIp    --version 5.7 -d $dbname
$craftDbHost = az mysql flexible-server show -g $rgname -n $mysqlServerName  --query "fullyQualifiedDomainName" -o tsv
echo $craftDbHost
az mysql flexible-server parameter set --name require_secure_transport --resource-group $rgname --server-name $mysqlServerName --value OFF
$fullstring= "mysql -h $mysqlServerName.mysql.database.azure.com -u $login -p craftdb < seed.sql"
echo $fullstring
# in cloud shell, need to import data

rm seed.sql
wget https://raw.githubusercontent.com/craftcms/spoke-and-chain/stable/seed.sql 
sed -i 's/MyISAM/INNODB/g' seed.sql 
take output of $fullstring and run it example 
    mysql -h ahmsbmysql.mysql.database.azure.com -u dbadmin  -p  craftdb < seed.sql


# end setup mysql





# clone repo and build container
$buildid=1
$containerprefix="craftrepo/craftcmsdemob:"
git clone https://github.com/craftcms/spoke-and-chain.git --single-branch  --depth 1 
cd spoke-and-chain 
$containername=$containerprefix + $buildid
echo $containername
az acr build -t $containername -g $rgname -r $acrname .


# end build container


#  if you want to deploy  to container apps

az extension add --name containerapp --upgrade
az provider register --namespace Microsoft.App --wait

$laworkspacename=$prefix+'logs'
$containerappnameenv=$prefix+'-caenv'
$containerappname=$prefix+'-cacms'
$containerimagename=$acrname + ".azurecr.io/" + $containername
echo $containerimagename

az monitor log-analytics workspace create   --resource-group $rgname  --workspace-name $laworkspacename
$LOG_ANALYTICS_WORKSPACE_CLIENT_ID=az monitor log-analytics workspace show --query customerId -g $rgname -n $laworkspacename --out tsv
$LOG_ANALYTICS_WORKSPACE_CLIENT_SECRET=az monitor log-analytics workspace get-shared-keys --query primarySharedKey -g $rgname -n $laworkspacename --out tsv
echo $LOG_ANALYTICS_WORKSPACE_CLIENT_ID
echo $LOG_ANALYTICS_WORKSPACE_CLIENT_SECRET

az containerapp env create  --name $containerappnameenv -g $rgname --logs-workspace-id $LOG_ANALYTICS_WORKSPACE_CLIENT_ID  --logs-workspace-key $LOG_ANALYTICS_WORKSPACE_CLIENT_SECRET  --location $location
echo $containerappname
echo $containerappnameenv
$fullacrname=$acrname+".azurecr.io"
echo $fullacrname
$IDENTITY=$prefix+"caidentity"
az identity create --name $IDENTITY  --resource-group $rgname
$IDENTITY_ID=az identity show --name $IDENTITY --resource-group $rgname --query id
echo $IDENTITY_ID
echo $containerappname


az containerapp create  --name $containerappname -g $rgname --environment $containerappnameenv `
  --image $containerimagename --target-port 8080  --ingress external  --registry-server $fullacrname `
  --user-assigned $IDENTITY_ID --registry-identity $IDENTITY_ID 

  az containerapp show --resource-group $rgname --name $containerappname
$site=az containerapp show --resource-group $rgname --name $containerappname --query properties.configuration.ingress.fqdn -o tsv
$site_url="https://" + $site
echo $site_url
echo $craftDbHost
echo $password
# this line is there are dollars in password. You need double dollar for each dollar. Not needed if no dollar
$passwordescaped=$password  # just use this if no dollar
$passwordescaped='passwordescaped'
echo $passwordescaped

  az containerapp update  --name $containerappname --resource-group $rgname `
  --set-env-vars CRAFT_DB_DATABASE="craftdb" `
  CRAFT_DB_DRIVER="mysql" `
  CRAFT_ENVIRONMENT="dev" `
  CRAFT_DB_PASSWORD=$passwordescaped `
  CRAFT_DB_PORT=3306 `
  CRAFT_DB_SCHEMA="user" `
  CRAFT_DB_SERVER=$craftDbHost `
  CRAFT_DB_USER=$login `
  CRAFT_SECURITY_KEY="temp123234" `
  DEFAULT_SITE_URL=$site_url

echo $site_url
  Start-Process $site_url
# end container apps


# if you want to deploy to appservice

$planName=$prefix+ "craftplan"
az appservice plan create -n $planName -g $rgname      -l $location --is-linux --sku S1
$appName=$prefix + "craftcms"

$containerimagename=$acrname + ".azurecr.io/" + $containername
echo $containerimagename
az webapp create -n $appName -g $rgname   --plan $planName --deployment-container-image-name $containerimagename
$principalid=az webapp identity assign --resource-group $rgname --name $appName --query principalId --output tsv
echo $principalid

echo /subscriptions/$subscriptionid/resourceGroups/$rgname/providers/Microsoft.ContainerRegistry/registries/$acrname
# Wait for awhile. Maybe 30 seconds

az role assignment create --assignee $principalid --scope /subscriptions/$subscriptionid/resourceGroups/$rgname/providers/Microsoft.ContainerRegistry/registries/$acrname --role "AcrPull"


$site = az webapp show -n $appName -g $rgName   --query "defaultHostName" -o tsv
echo $site


$site_url="https://" + $site
echo $site_url

# configure web app settings (container environment variables)
az webapp config appsettings set `
    -n $appName -g $rgname --settings `
    CRAFT_DB_DATABASE="craftdb" `
    CRAFT_DB_DRIVER="mysql" `
    CRAFT_ENVIRONMENT="dev" `
    CRAFT_DB_PASSWORD=$password `
    CRAFT_DB_PORT=3306 `
    CRAFT_DB_SCHEMA="user" `
    CRAFT_DB_SERVER=$craftDbHost `
    CRAFT_DB_USER=$login `
    CRAFT_ENVIRONMENT="dev" `
    CRAFT_SECURITY_KEY="temp123234" `
    DEFAULT_SITE_URL=$site_url


  
    az webapp stop -n $appName -g $rgname
    az webapp start -n $appName -g $rgname
    az webapp config appsettings list  -n $appName -g $rgname

Start-Process $site_url

# end app Service
