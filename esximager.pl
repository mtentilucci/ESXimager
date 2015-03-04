#!/usr/bin/perl


##########################
#esximager.pl
#Version: 1.2
#Written By: Matt Tentilucci 
#
#A simple tool that automates the discovery, hashing, and copying of files from a 
#VMware ESXi hypervisor to be used for a forensics investigation.
#
#v1.1: Switching from using Net::SSH::Perl to use Net::OpenSSH. Net::OpenSSH is much easier to install and is apperently 
#better maintained then Net::SSH::Perl
#v1.2: Switching to utilize Net::SFTP::Foreign to transfer images across the network instead of piping DD to netcat as this was causing problems
#image is dd to a local storage on ESXi server then copied across the network to the acquiring computer via SFTP
#
#Usage: esximager.pl
##########################

#use Net::SSH::Perl;
use Net::OpenSSH;
use Net::SFTP::Foreign;

#Command Declaration
my $ls = '/bin/ls';
my $nc = '/usr/bin/nc';

my $esxIP = "192.168.100.141";
my $username = "root";
my $password = "netsys01";
my $netcatOutputDir;
my $netcatPort;
my $localIPAddress;

#Ask for ip address of ESX box and validates input if the $esxIP variable is undefined
if (undef == $esxIP)
{
	print "Enter ip, username, and password of ESXi box\n";
	while(1)
	{
		print "IP Address: ";
		$esxIP = <STDIN>;
		if(($esxIP =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/) && ($1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 ))
		{
	    	chomp $esxIP;
	    	last;
		}
		else
		{
	    	print "Enter a valid ip address. ex. 192.168.0.1\n\n";
		}
	}
}

#Ask for login credentials, if $username and $password variables are undef
if (undef == $username)
{
	print "Username: ";
	$username = <STDIN>;
	chomp $username;
}
if (undef == $password)
{
	print "Password: ";
	`stty -echo`;
	$password = <STDIN>;
	`stty echo`;
	chomp $password;
}

#Connect to target ESXi server
print "\n*Connection to $esxIP...";
#my $ssh = Net::SSH::Perl->new($esxIP, options => ["protocol 2,1"]);
#$ssh->login ($username, $password);
my $ssh = Net::OpenSSH->new("$username:$password\@$esxIP", master_opts => [ -o => "StrictHostKeyChecking=no"]);
$ssh->error and die "Could not connect to $esxIP" . $ssh->error;
print "done!\n";

#This seems to no longer apply to ESXi 5.5, making $vmstore = /vmfs/volumes/
my $stdout = $ssh->capture("ls -l /vmfs/volumes/Storage");
$stdout =~ m/-\>\s+/;

my $vmstore = "/vmfs/volumes/$'";
chomp $vmstore;
#print "$stdout";
#print "$'";

#find vms on datastore
my @vmxFound;
my @getVMs;
while(1)
{
  	 $stdout = $ssh->capture("find $vmstore -name \"*.vmx\"");
 	  @vmxFound = split(/\s+/, $stdout);
  	 print "Below is a list of associated .vmx files on the the ESX server.  Which of these virtual machines do you wish to acquire?\n\n";
  	 my $i = 0;
  	 foreach (@vmxFound)
   	{
   		print "\t$i\t$_\n";
   		$i++;
   	}
   	print "\nEnter a comma separated list (0,1,2,6...etc): ";
   	my $getVM = <STDIN>; chomp($getVM);
  	 # @getVMs = split(',',$getVM);
  	 print "You Selected:\n";
   	foreach (split(',',$getVM))
   	{
   		print "\t$vmxFound[$_]\n";
   		my @tmpDir = split('/', $vmxFound[$_]);
   		pop @tmpDir;
   		push (@getVMs, join('/', @tmpDir));
   	}
   	print "Correct? (y/n): ";
   	my $pickedRightVMs = <STDIN>; chomp $pickedRightVMs;
  	 last if ($pickedRightVMs =~ m/^y$/i);
}

#Ask which filetypes they wish to copy
my @fileTypes = (".vmx", ".vmxf", ".vmdk", ".vmem", ".nvram", ".vmss", ".vmsd", ".log");
my $i = 0;
print "Below is a list of file types associated with virtual machines.  Which types of files do you wish to recover?\n\n";
my $i = 0;
foreach (@fileTypes)
{
	print "\t$i\t$_\n";
   	$i++;
}
print "\nEnter a comma separated list (0,1,2,6...etc): ";
my $getType = <STDIN>; chomp($getType);
@getTypes = split(',',$getType);

#Ask for netcat paramaters
#my $netcatOutputDir = '';
#while($netcatOutputDir !~ m/^\//)
#{
#  	 print "Specify ABSOLUTE path to store images (ex. /home/usr1/Desktop) : ";
#  	 $netcatOutputDir = <STDIN>; chomp $netcatOutputDir;
#}

#system("/bin/mkdir $netcatOutputDir 2> /dev/null");
#if($? != 0){
#  	 `touch $netcatOutputDir/testtouch 2> /dev/null`;
#  	 if ($? != 0)
#   	{
#   		print "Cound not create or write to directory...exiting\n";
#   		exit 1;
#  	 }
#}else{`rm $netcatOutputDir/testtouch 2> /dev/null`;}

#print "What port should netcat lisiten on?: ";
#$netcatPort = <STDIN>;
#chomp $netcatPort;
#$localIPAddress= getLocalIPAddress();

#!!REMOVE THIS ONCE YOU FIGURE OUT HOW TO CHECK IF THE DIRECTORY EXISTS!!
$stdout = $ssh->capture("mkdir /vmfs/volumes/datastore1/ddimages");
#!!REMOVE THIS ONCE YOU FIGURE OUT HOW TO CHECK IF THE DIRECTORY EXISTS!!

foreach (@getVMs)
{
	my $thisVM = $_;
	# my @tmp = split ('/',$vmxFound[$_]);
	# my $count = @tmp;
	# $count--;
	# my $vmName = $tmp[$count];
	# print "naming $vmName";
	# my $r=<STDIN>;
	my @filesToGet;
	foreach (@getTypes)
	{
  		$stdout = $ssh->capture("find $thisVM -iname \"*$fileTypes[$_]\"");
  		push(@filesToGet, (split (/\s+/, $stdout)));
	}

	foreach (@filesToGet)
	{
  		my $fullESXPath = $_; chomp $fullESXPath;
  		my @filePathParts = split('/', $fullESXPath);
  		my $getFileName = pop(@filePathParts);
		print "full ESX path: $fullESXPath\n";
		print "files to get: $getFileName\n";

		#sub to dd target file to local ESXi storage /vmfs/volumes, calc before/after hashes too (absolute path target file, target file)
		my $targetImageFile = ddTargetFile($fullESXPath,$getFileName);
		#sub to sftp files from local ESXi storage to acqusition machine, cal hashes (esxi ip, target file(s), acqusition machine dest)
		print "Going to SFTP $targetImageFile to this computer\n";
		sftpTargetFileImage($esxIP,$targetImageFile);


		#my $netcatPID = "";
		#$netcatPID = findNetcatSessionsOnServer();
		#killNetcatSessionsOnServer($netcatPID) if ($netcatPID != "");
  		#createNetcatServer($netcatPort, $netcatOutputDir, "/$getFileName");
  		#ddFileFromTarget($fullESXPath, $localIPAddress, $netcatPort);
	
		#Calculate hashes after copy
		#my $tmp = $netcatOutputDir . "/$getFileName.dd";
		#$md5 = `md5sum $tmp`;
		#$sha1 = `sha1sum $tmp`;
		#print "Hashes After DD:\n\tMD5: $md5\tSHA1: $sha1\n";
	}
	
}

print "end";

#Set up the netcat listener on the local machine
sub createNetcatServer
{
	my $portToLisiten = $_[0];
	my $pathToStoreImage = $_[1];
	my $nameOfOutputFile = $_[2];

	my $ncPath = $pathToStoreImage . $nameOfOutputFile . ".dd";   

	print "\n*Creating netcat session on this computer...";
	system("nc -l $portToLisiten | dd of=$ncPath &");
	print "done!\n";
}

# Determine local IP address so we know the IP to copy to (incase there is more than one NIC)
sub getLocalIPAddress
{
	my $interfaces;
	my $ipChoice;

	while(1)
	{
    		$interfaces = `ifconfig | egrep 'inet|^[a-z]'`;
    		print "\n$interfaces\n";
   
    		print "Which IP address do you want to use?: ";
    		$ipChoice = <STDIN>;
    		chomp $ipChoice;
   
    		last if ($interfaces =~ m/$ipChoice/);
	}

	return $ipChoice;
}

sub findNetcatSessionsOnServer
{
	$stdout = $ssh->capture("ps | grep nc\$");
	my @netcatLine = split(/\s+/, $stdout);
	#print "netcat PID: $netcatLine[0]\n";
	return $netcatLine[0];
}

sub killNetcatSessionsOnServer
{
	my $ncPID = $_[0];
        #print "about to kill pid $netcatPID, continue?\n"; my $r=<STDIN>;
	$stdout = $ssh->capture("kill -9 $netcatPID");
}

#Calculate MD5 hash of file about to be copied on ESX server
sub calculateMD5HashOnESX
{
	my $fileToHash = $_[0];
	
	print "*Calculating md5 hash this may take a while be patient...";
	$stdout = $ssh->capture("md5sum $fileToHash");
	print "done!\n";
	chomp $stdout;
	return $stdout;   
}

# Calculate SHA1 hash of the file about to be copied on ESX server
sub calculateSHA1HashOnESX
{
	my $fileToHash = $_[0];
	
	print "*Calculating sha1 hash this may take a while be patient...";
	$stdout = $ssh->capture("sha1sum $fileToHash");
	print "done!\n";
	chomp $stdout;
	return $stdout;   
}

#Calculate MD5 hash of local file
sub calculateMD5HashLocal
{
	my $fileToHash = $_[0];
	
	print "*Calculating md5 hash this may take a while be patient...";
	$stdout = `md5sum $fileToHash`;
	#$stdout = $ssh->capture("md5sum $fileToHash");
	print "done!\n";
	chomp $stdout;
	return $stdout;   
}

# Calculate SHA1 hash of local file
sub calculateSHA1HashLocal
{
	my $fileToHash = $_[0];
	
	print "*Calculating sha1 hash this may take a while be patient...";
	$stdout = `sha1sum $fileToHash`;
	#$stdout = $ssh->capture("sha1sum $fileToHash");
	print "done!\n";
	chomp $stdout;
	return $stdout;   
}

#Runs DD on ESX server and pipes it to netcat pointed to local machine.
sub ddFileFromTarget
{
	my $fileToDD = $_[0];
	my $userLocalIP = $_[1];
	my $serverPort = $_[2];

	my $md5 = calculateMD5HashOnESX($fileToDD);
	my $sha1 = calculateSHA1HashOnESX($fileToDD);

	print "Hashes Before DD:\n \tMD5: $md5\n \tSHA1: $sha1\n";
	sleep(1);

	$stdout = $ssh->capture("dd if=$fileToDD | nc $userLocalIP $serverPort -w 3");

}

#Runs DD on ESXi server to create copy of target file, saves it on ESXi server in /vmfs/volumes/datastore1 (this will need to be dynamic later)
sub ddTargetFile
{

	#!!check to see if ddimages directory exists!! figure out later
	print "\n\n---------------------------\nCreating DD copy of target file\n";
	my $absolutePathFileToDD = $_[0];
	my $fileToDD = $_[1];
	my $fileToDDDestinationName  = $fileToDD;
	$fileToDDDestinationName =~ s/vmx/dd/;
	#print "dd destination name $fileToDDDestinationName\n";
	#my @fileToDDSplit = split('.',$fileToDD);

#print "0 ". $fileToDDSplit[0] . "1 " . $fileToDDSplit[1] . "\n";
	my $ddDestination = "/vmfs/volumes/datastore1/ddimages" . "/" . $fileToDDDestinationName;
#print "dd dest $ddDestination\n";
#my $s=<STDIN>;
	my $md5 = calculateMD5HashOnESX($absolutePathFileToDD);
	my $sha1 = calculateSHA1HashOnESX($absolutePathFileToDD);

	print "Hashes Before DD:\n \tMD5: $md5\n \tSHA1: $sha1\n";
	sleep(1);

	$stdout = $ssh->capture("dd if=$absolutePathFileToDD of=$ddDestination");
	
	my $pathToHash = $ddDestination;
	my $md5Check = calculateMD5HashOnESX($pathToHash);
	my $sha1Check = calculateSHA1HashOnESX($pathToHash);
	print "Hashes After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check\n";
	sleep(1);
	return $pathToHash;

}

#SFTPs target file to local machine
sub sftpTargetFileImage
{
	my $serverIP = $_[0];
	my $fileToSFTP = $_[1];

	my %args; #= ( user => 'root',password => 'netsys01');

	my $host= '192.168.100.141';
	my $sftp = Net::SFTP::Foreign->new($host,  user => 'root',password => 'netsys01');
	$sftp->die_on_error("SSH Connection Failed");
	
	my @filePathParts2 = split('/', $fileToSFTP);
	my $getFileName2 = pop(@filePathParts2);
	
	my $localDestination = "/home/matt/Desktop/" . $getFileName2;
	#print "This file will SFTP from $fileToSFTP to $localDestination\n";
	#my $f=<STDIN>;

	$sftp->get($fileToSFTP,$localDestination) or die "File transfer failed\n";

	my $md5Check = calculateMD5HashLocal($localDestination);
	my $sha1Check = calculateSHA1HashLocal($localDestination);
	print "Hashes After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check\n";
	sleep(1);

}

print " end end\n";
$sftp->disconnect;
#ensure all netcat lisitening sessions are dead before the script exits
#$stdout = `killall nc`;
