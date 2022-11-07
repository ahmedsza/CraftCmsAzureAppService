az login --tenant # set tenant if required
$subscription="<subscriptionId>" # add subscription here

az account set -s $subscription # ...or use 'az login'

$subscriptionid= az account show --query id --output tsv
echo $subscriptionid

$prefix='ahmsb'
$rgname=$prefix+'rg'
$location='westeurope'
$acrname=$prefix+'acr'
$buildid=1
$login='dbadmin'
$password='P2ssw0rd$$$$'
$sku="Standard_B1ms"
$tier="Burstable"
$mysqlServerName=$prefix+'mysql'
$containerprefix="craftrepo/craftcmsdemob:"

$startIp='0.0.0.0'
$endIp='0.0.0.0'

$dbname='craftdb'
echo $rgname
echo $acrname
 
az group create --name $rgname --location $location
az acr create --resource-group $rgname --name $acrname --sku Basic --admin-enabled true
az acr credential show --resource-group $rgname --name  $acrname
$acrusername=az acr credential show -n $acrname --query username -g $rgname -o tsv
$acrpassword=az acr credential show -n $acrname  -g $rgname  --query passwords[0].value -o tsv
echo $acrusername
echo $acrpassword



az mysql flexible-server create -g $rgname -n $mysqlServerName   --admin-user $login --admin-password $password   -l $location  --public-access $startIp    --version 5.7 -d $dbname
$craftDbHost = az mysql flexible-server show -g $rgname -n $mysqlServerName  --query "fullyQualifiedDomainName" -o tsv
echo $craftDbHost
az mysql flexible-server parameter set --name require_secure_transport --resource-group $rgname --server-name $mysqlServerName --value OFF


$fullstring= "mysql -h $mysqlServerName.mysql.database.azure.com -u $login -p craftdb < seed.sql"
echo $fullstring
# in cloud shell
rm seed.sql
wget https://raw.githubusercontent.com/craftcms/spoke-and-chain/stable/seed.sql 
sed -i 's/MyISAM/INNODB/g' seed.sql 
take output of $fullstring and run it example 
    mysql -h ahmsbmysql.mysql.database.azure.com -u dbadmin  -p  craftdb < seed.sql










git clone https://github.com/craftcms/spoke-and-chain.git --single-branch  --depth 1 
cd spoke-and-chain 
$containername=$containerprefix + $buildid
echo $containername
az acr build -t $containername -g $rgname -r $acrname .


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
