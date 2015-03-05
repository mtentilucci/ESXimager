ESXi Forensics Imaging
Matt Tentilucci and Jon Pucila
mjt4509@rit.edu jxp8004@rit.edu
Rochester Institute of Technology
*You must enable remote SSH support on your ESXi server for this to work* 
*See wiki on our souceforge page for more info on how to use the program https://sourceforge.net/p/esxiimaging/wiki/How-To/*

Current Version:
esximager1.1.pl
-Now using Net::OpenSSH module
-Fixed bug that would cause files to not be copied from esx server
-Added some error checking to ensure there are no netcat sessions running on the esx server
-Small code fixes

Previous Versions:
esximager.pl

Supported Operating Systems:
-CentOS 5.6
-Ubuntu 12.10
-Other Linux versions will probably work but we have not tested them

Supported ESXi Servers:
-VMware ESXi 4.1.0  

