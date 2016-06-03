#!/usr/bin/env bash

### Shell script for copying configuration, supporting libraries and binaries from a Microsoft Azure HDInsight (HDI) cluster to an edge node.
### Tested with an HDI 3.4 version cluster and Ubuntu 12.04 Linux VM as the edge node.

### Usage: sudo -EH bash hdiEdgeNodeSetup.sh <clustername> <sshuser> '<sshpassword in single quotes>'

### Script variables
clusterName=$1
clusterSshUser=$2
clusterSshPw=$3

### Install sshpass for passing remote commands through to the cluster.
echo "Installing sshpass"
apt-get -y -qq install sshpass

### Install Java, it's required for Hadoop and its related projects'
echo "Installing Java OpenJDK 7 (openjdk-7-jdk)"
apt-get -y -qq install openjdk-7-jdk

### Add edge node machine name to /etc/hosts or many Hadoop operations will complain and/or fail
echo "Adding edge node machine name/host name to /etc/hosts - some Hadoop command complain and/or fail without it"
sed -i "s/127.0.0.1 localhost$/127.0.0.1 localhost $HOSTNAME/" /etc/hosts

### Adding HDI cluster to the VM's known hosts so we can SSH without warnings
# NOTE: The sudo -H option enforces the root user's' home directory (where .ssh/known_hosts is stored) to allow sshpass to work as expected.
clusterSshHostName="$(echo $clusterName-ssh.azurehdinsight.net | tr '[:upper:]' '[:lower:]')" # enforce lowercase for ssh-keyscan / known_hosts compatibility
echo "Adding cluster host's ($clusterSshHostName) public key to VM's known hosts if it does not exist"
knownHostKey=$(ssh-keygen -H -F $clusterSshHostName 2>/dev/null)
if [ -z "$knownHostKey" ];
  then
    echo "Cluster host's public key not found on this edge node. Adding to known_hosts"
    ssh-keyscan -H $clusterSshHostName >> ~/.ssh/known_hosts
  else
    echo "Cluster is already a known host."
fi

### Prepare local and remote (cluster) temporary file paths for resources to be copied from the cluster
tmpFilePath=~/tmpHDIResources
rm -r $tmpFilePath #cleanup if necessary
mkdir -p $tmpFilePath
mkdir -p $tmpFilePath/logs
tmpRemoteFolderName=tmpEdgeNode
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "rm -rf ~/$tmpRemoteFolderName" #cleanup if necessary
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "mkdir ~/$tmpRemoteFolderName"

### Zip and transfer HDI and HDP resources, including all symbolic links (want to mirror HDI cluster so everything works as expected)
# Helper functions below to help reduce code duplication and (hopefully) errors

# Zip an entire remote directory into the remote temporary file directory.
zipRemoteDirectory() {
  echo "Zipping remote directory $1 from cluster"
  sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName 'tar -vczf ~/'$tmpRemoteFolderName'/'$2' '$1' &>/dev/null'
  echo "Directory $1 from cluster zipped to ~/$tmpRemoteFolderName/$2"
}

# Zip relevant HDI and HDP directories and files into the remote temporary file directory.
zipRemoteFiles() { # expects a path (e.g., /usr/bin, /usr/lib) and output zip filename (e.g., hdi-usr-bin.tar.gz)
  echo "Zipping relevant HDI and HDP files from cluster for path $1"
  sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName 'find '$1' -maxdepth 1 -regextype posix-egrep -regex ".*(accumulo|ambari|atlas|failover|falcon|flume|hadoop|hbase|hdinsight|hive|kafka|knox|livy|mahout|oozie|phoenix|pig|ranger|slider|spark|sqoop|storm|tez|zeppelin|zookeeper|hdinsight).*" -o -lname "*/hdp*" | sort | tar -vczf ~/'$tmpRemoteFolderName'/'$2' --files-from -' &>$tmpFilePath/logs/$2.zip.log #redirect stdout and stderr to a log file for review if errors occur
  echo "HDI and HDP files from cluster in $1 zipped to ~/$tmpRemoteFolderName/$2"
}

# Copy zipped up files to the temporary directory on the edge node.
copyRemoteFile() { # expects a file name (e.g., hdi-usr-lib.tar.gz)
  echo "Copying zipped file $1 from the cluster to $tmpFilePath"
  sshpass -p $clusterSshPw scp $clusterSshUser@$clusterSshHostName:"~/$tmpRemoteFolderName/$1" "$2/$1" &>$tmpFilePath/logs/$1.copy.log
  echo "$1 copied from cluster to $2/$1"
}

# Unzip files on the edge node into its temporary directory.
unzipFile() { # expects a filename and destination path
  echo "Unzipping $1 locally into $2"
  tar -vxzf $2/$1 -C $2 &>$tmpFilePath/logs/$1.unzip.log
  echo "$1 unzipped to $2"
}

echo "Starting HDI and HDP resource copy from cluster"

echo "Copying HDP from cluster"
hdpFileName=hdi-usr-hdp.tar.gz
zipRemoteDirectory /usr/hdp $hdpFileName
copyRemoteFile $hdpFileName $tmpFilePath
unzipFile $hdpFileName $tmpFilePath

echo "Copying various HDI and HDP resource paths, many required due to symlinks"
RESOURCEPATHS=(/usr/bin /usr/lib /usr/lib/python2.7/dist-packages /etc /var/lib) # Known binary, library and configuration paths for HDI and HDP
for path in "${RESOURCEPATHS[@]}"
do
	resourceFileName=hdi-$(echo $path | sed 's:/::; s:/:-:g').tar.gz
  zipRemoteFiles $path $resourceFileName
  copyRemoteFile $resourceFileName $tmpFilePath
  unzipFile $resourceFileName $tmpFilePath
done

echo "Finished HDI and HDP resource copy from cluster"

echo "Copying HDI and HDP resources to final destination on edge node (/etc, /usr, /var)"
cp -r $tmpFilePath/{etc,usr,var} /
echo "HDI and HDP resources have been copied/installed."

### Cleanup
echo "Moving HDI and HDP resource zip, copy, unzip logs to ${HOME} for review (if needed)"
mv $tmpFilePath/logs ~/

echo "Cleaning up temporary files locally and on the cluster"
rm -r $tmpFilePath
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "rm -rf ~/$tmpRemoteFolderName" #cleanup if necessary

### Done!
echo "Edge Node setup complete"