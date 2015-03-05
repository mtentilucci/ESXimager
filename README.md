# ESXimager
Create secure digital forensic images of virtual machines running on VMware ESXi Hypervisors.

## Overview
ESXimager securely images selected virtual machine files running on VMware ESXi and ensures image integrity through the entire imaging process. Written in Perl and utilizing Tk, the tool makes use of an ESXi server’s ability to execute shell commands. Bit-stream copies are created using the dd command, image integrity is verified using the MD5 and SHA1 hashing algorithms, and images are securely transferred to an external imaging machine with SFTP. 

While this entire process can be done manually, why not write a tool to do it for you. I have not been able to find any other tool that has this specific type of functionality. 

At the end of the imaging process, you end up with a RAW image in a .dd format which can then be loaded into a computer forensics program for analysis. 

## About Me
I am not a programmer. I am a security engineere, sys/net admin at heart. Perl is my go to language and I consider myself to be an intermediate to advanced user, but by no means an expert. Did I make some programming no-no's in this code, maybe. Could it be witten better and more efficiently, probably.  But that is why this is open source. My hope is that others will contribute to make this tool even better. 

## License
This program is licenced under the Artistic License 2.0 see the LICENSE file. 
