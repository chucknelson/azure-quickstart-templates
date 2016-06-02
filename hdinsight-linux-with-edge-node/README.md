# Create HDInsight Linux Cluster with Edge Node

Create HDInsight Linux Cluster with Edge Node:

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fchucknelson%2Fazure-quickstart-templates%2Fedgenode-script-testing%2Fhdinsight-linux-with-edge-node%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fchucknelson%2Fazure-quickstart-templates%2Fedgenode-script-testing%2Fhdinsight-linux-with-edge-node%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

Template creates an HDInsight Linux cluster in a virtual network with a Linux VM as an edge node that is bootstrapped with the cluster's Hadoop/HDP configurations.

***Note***: This branch is for testing a rewritten edge node setup script.

This deployment template has been tested successfully with HDI 3.4 clusters, but does not yet work with Spark cluster types.




