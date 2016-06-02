#!/usr/bin/env bash

### Shell script for copying Hadoop-related configuration from an HDI cluster to an edge node.
### Tested with an HDI 3.4 version cluster and Ubuntu 12.04 Linux VM as the edge node.

### Script variables
clusterName=$1
clusterSshUser=$2
clusterSshPw=$3

### Install sshpass for passing remote commands through to the cluster.
echo "Installing sshpass"
apt-get -y -qq install sshpass

### Adding HDI cluster to the VM's known hosts so we can SSH without warnings
clusterSshHostName="$clusterName-ssh.azurehdinsight.net"
echo "Adding cluster host's ($clusterSshHostName) public key to VM's known hosts if it does not exist"
knownHostKey=$(ssh-keygen -H -F $clusterSshHostName 2>/dev/null)
if [ -z "$knownHostKey" ];
  then
    echo "Cluster host's public key not found on this edge node. Adding to known_hosts"
    ssh-keyscan -H $clusterSshHostName >> ~/.ssh/known_hosts
  else
    echo "Cluster is already a known host."
fi

### Prepare local and remote (cluster) temp file paths for resources to be copied from the cluster
tmpFilePath=~/tmpHDIResources
rm -r $tmpFilePath #cleanup if necessary
mkdir -p $tmpFilePath
tmpRemoteFolderName=tmpEdgeNode
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "rm -rf ~/$tmpRemoteFolderName" #cleanup if necessary
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "mkdir ~/$tmpRemoteFolderName"

### Zip and transfer HDP tools, including all symbolic links (want to mirror HDI cluster so everything works as expected) 
#TODO - /usr/hdp (everything), /usr/bin, /usr/lib, /usr/lib/python2.7/dist-packages, /etc, /var/lib

zipRemoteDirectory() {
  echo "Zipping remote directory $1 from cluster"
  sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName 'tar -vczf ~/'$tmpRemoteFolderName'/'$2' '$1' &>/dev/null'
  echo "Directory $1 from cluster zipped to ~/$tmpRemoteFolderName/$2"
}

# Zips relevant directories and files on the cluster that we want to copy for HDI and HDP purposes on the edge node
zipRemoteFiles() { # expects a path (e.g., /usr/bin, /usr/lib) and output zip filename (e.g., hdi-usr-bin.tar.gz)
  echo "Zipping relevant HDI and HDP files from cluster for path $1"
  sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName 'find '$1' -maxdepth 1 -regextype posix-egrep -regex ".*(accumulo|ambari|atlas|failover|falcon|flume|hadoop|hbase|hdinsight|hive|kafka|knox|livy|mahout|oozie|phoenix|pig|ranger|slider|spark|sqoop|storm|tez|zeppelin|zookeeper|hdinsight).*" -o -lname "*/hdp*" | sort | tar -vczf ~/'$tmpRemoteFolderName'/'$2' --files-from -' &>$tmpFilePath/$2.zip.log #redirect stdout and stderr to a log file for review if errors occur
  echo "HDI and HDP files from cluster in $1 zipped to ~/$tmpRemoteFolderName/$2"
}

copyRemoteFile() { # expects a file name (e.g., hdi-usr-lib.tar.gz)
  echo "Copying zipped file $1 from the cluster to $tmpFilePath"
  sshpass -p $clusterSshPw scp $clusterSshUser@$clusterSshHostName:"~/$tmpRemoteFolderName/$1" "$2/$1" &>$tmpFilePath/$1.copy.log
  echo "$1 copied from cluster to $2/$1"
}

unzipFile() { # expects a filename and destination path
  echo "Unzipping $1 locally into $2"
  tar -vxzf $2/$1 -C $2 &>$tmpFilePath/$1.unzip.log
  echo "$1 unzipped to $2"
}

echo "Starting HDI and HDP resource copy from cluster"

echo "Copying HDP from cluster"
hdpFileName=hdi-usr-hdp.tar.gz
zipRemoteDirectory /usr/hdp $hdpFileName
copyRemoteFile $hdpFileName $tmpFilePath
unzipFile $hdpFileName $tmpFilePath

RESOURCEPATHS=(/usr/bin /usr/lib /usr/lib/python2.7/dist-packages /etc /var/lib)
for path in "${RESOURCEPATHS[@]}"
do
	resourceFileName=hdi-$(echo $path | sed 's:/::; s:/:-:g').tar.gz
  zipRemoteFiles $path $resourceFileName
  copyRemoteFile $resourceFileName $tmpFilePath
  unzipFile $resourceFileName $tmpFilePath
done

echo "Done for testing"
exit 1;

# HDP (/usr/hdp)
echo "Zipping HDP (/usr/hdp) on the cluster"
hdiHDPFileName=hdi-hdp.tar.gz
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "tar -vczf ~/$tmpRemoteFolderName/$hdiHDPFileName /usr/hdp &>/dev/null"

echo "Copying zipped HDP file from the cluster to $tmpFilePath"
sshpass -p $clusterSshPw scp $clusterSshUser@$clusterSshHostName:"~/$tmpRemoteFolderName/$hdiHDPFileName" "$tmpFilePath/$hdiHDPFileName"

echo "Unzipping HDP tools locally into $tmpFilePath"
tar -vxzf $tmpFilePath/$hdiHDPFileName -C $tmpFilePath

echo "Copying HDP tools to final destination (/usr/hdp)"
cp -r $tmpFilePath/usr /

echo "Cleaning up temporary files on locally and on the cluster"
rm -f $tmpFilePath/$hdiHDPFileName
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "rm -rf ~/$tmpRemoteFolderName"

echo "Done"

exit 1; #force exit for testing





########### TO IMPLEMENT

### Copy specific binaries from the cluster
echo "Copying specific HDP/Hadoop binaries from the cluster to $tmpFilePath"
mkdir -p "$tmpFilePath/usr/bin"
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "find /usr/bin -readable -lname '/usr/hdp/*' -exec test -e {} \; -print" | while read fileName ; do sshpass -p $clusterSshPw scp $clusterSshUser@$clusterSshHostName:$fileName "$tmpFilePath$fileName" ; done

### Copy cluster configurations
echo "Copying configuration and Ambari scripts from the cluster to $tmpFilePath"
RESOURCEPATHS=(/etc/hadoop/conf /etc/hive/conf /var/lib/ambari-server/resources/scripts)
for path in "${RESOURCEPATHS[@]}"
do
	mkdir -p "$tmpFilePath/$path"
	sshpass -p $clusterSshPw scp -r $clusterSshUser@$clusterSshHostName:"$path/*" "$tmpFilePath$path"
done

# Copy the storage key decryption utilities from the cluster
wasbDecryptScript=$(grep "shellkeyprovider" -A1 ${tmpFilePath}/etc/hadoop/conf/core-site.xml | perl -ne "s/<\/?value>//g and print" | sed 's/^[ \t]*//;s/[ \t]*$//')
decryptUtils=$(dirname $wasbDecryptScript)
echo "Copying Azure Blob Storage (wasb://) key decryption utilities from $decryptUtils on the cluster to $tmpFilePath"
mkdir -p "$tmpFilePath/$decryptUtils"
sshpass -p $clusterSshPw scp -r $clusterSshUser@$clusterSshHostName:"$decryptUtils/*" "$tmpFilePath$decryptUtils"

# Copy all HDP tools and HDI logging utilities from the cluster
binariesLocation=$(grep HADOOP_HOME "$tmpFilePath/usr/bin/hadoop" -m 1 | sed 's/.*:-//;s/\(.*\)hadoop}/\1/;s/\(.*\)\/.*/\1/')
echo "Cluster's physical HDP/Hadoop location found in: $binariesLocation"

echo "Zipping HDP tools and HDI logging utilities on the cluster"
bitsFileName=hdpBits.tar.gz
loggingBitsFileName=loggingBits.tar.gz

sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "mkdir ~/$tmpRemoteFolderName"
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "tar -cvzf ~/$tmpRemoteFolderName/$bitsFileName $binariesLocation &>/dev/null"
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "tar -cvzf ~/$tmpRemoteFolderName/$loggingBitsFileName /usr/lib/hdinsight-logging &>/dev/null"

echo "Copying binaries from the cluster"
sshpass -p $clusterSshPw scp $clusterSshUser@$clusterSshHostName:"~/$tmpRemoteFolderName/$bitsFileName" .
sshpass -p $clusterSshPw scp $clusterSshUser@$clusterSshHostName:"~/$tmpRemoteFolderName/$loggingBitsFileName" .

echo "Unzipping binaries locally"
tar -xhzvf $bitsFileName -C /
tar -xhzvf $loggingBitsFileName -C /

echo "Cleaning up temporary files on the cluster and locally"
rm -f $bitsFileName
sshpass -p $clusterSshPw ssh $clusterSshUser@$clusterSshHostName "rm -rf ~/$tmpRemoteFolderName"



echo "Done"