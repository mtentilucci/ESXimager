#!/usr/bin/perl
use strict;
use Tk;
use Tk::ProgressBar;
use Tk::MsgBox;
#use Tk::Text;
use Net::OpenSSH;
use Net::SFTP::Foreign;

########################
#ESXimager2.2.pl
#Matt Tentilucci	
#11-4-2014
#
#V2.1 - Adding in user confirmation of VM choices and passing them back to sshToESXi sub, removing lots of misc. lines from debugging/trial and error
#V2.2 - Redesign user selection of VMs window and switched from grid to pack geometry manager. Instead of having a sub window, 
# there will be a frame within main window that will be updated with the VM choices for the user to image. This should be a much
# cleaner look and prevent multiple windows from popping up. Also added configuration file and Tools->Settings menu bar for editing it
########################

#variable so ssh session to esxi can be accessible outside of sub
my $ssh;

#Variables for location of working directory, case directory, configuration file, and log file
my $configFileLocation = $ENV{"HOME"} . "/ESXimager/ESXimager.cfg";
my $ESXiWorkingDir;
my $ESXiCasesDir;
my $logFileDestination;
my $currentCaseName = "No Case Opened Yet";
my $currentCaseLocation;

#Creates main window
my $mw = MainWindow->new;
$mw->title("ESXimager 2.2");
#$mw->geometry("600x600");

#Create menu bar
$mw->configure(-menu => my $menubar = $mw->Menu);
my $file = $menubar->cascade(-label => '~File');
my $tools = $menubar->cascade(-label => '~Tools');
my $help = $menubar->cascade(-label => '~Help');

$file->command(-label => 'New Case', -underline => 0, -command => \&createNewCase);
$file->separator;
$file->command(-label => "Quit", -underline => 0, -command => \&exit);

$tools->command(-label => "Settings", -command => \&editSettings);

#console window
my $consoleLog = $mw->Text(-height => 10, -width => 125)->pack(-side => 'bottom', -fill => 'both');

#Creates a label in the top left display the case currently "open"
my $caseLabel = $mw->Label(-text => "Current Case: $currentCaseName Location: $currentCaseLocation")->pack;#(-side => 'left', -anchor => 'nw');

#Create top left frame for holding username, password, server IP, connect button widgets
my $connectionFrame = $mw->Frame(-borderwidth => 2, -relief => 'groove');
$connectionFrame->pack(-side => 'left', -anchor => 'nw');

#label for IP
$connectionFrame->Label(-text => "Server IP")->pack;
	
#entry for IP
my $ESXip = $connectionFrame->Entry( -width => 20, -text => "172.16.150.128")->pack;

#Label for user
$connectionFrame->Label(-text => "Username")->pack;

#entry for user
my $username = $connectionFrame->Entry( -width => 20,  -text => "root")->pack;

#label for pass
$connectionFrame->Label(-text => "Password")->pack;

#entry for pass
my $password = $connectionFrame->Entry( -width => 20, -show => "*",  -text => "Thewayiam10107")->pack;

#connect button, first calls sub to do input sanitization and checking on ip, username, and password boxes then 
#either falls out with an error, or another sub is called to connect to the ESXi server
$connectionFrame->Button(-text => "Connect", -command => \&sanitizeInputs )->pack;	
	
my $vmChoicesFrame = $mw->Frame(-borderwidth => 2, -relief => 'groove');
$vmChoicesFrame->pack(-side => 'right', -fill => 'both');
#$vmChoicesFrame->Label(-text => "Connect to an ESXi server")->pack;
	
#$consoleLog->insert('end',"\nfoo");
checkOS();
readConfigFile();

#Reads the configuration file for this program. It looks in /home/user/ESXimager/ESXimager.cfg
#If it does not find a config file it will prompt the user to create one, bringing them to the 
#configuration window. Otherwise, the config file is loaded and the storage locations defined in it are used
sub readConfigFile
{
	my $expectedConfigFileLoc = $ENV{"HOME"} . "/ESXimager/ESXimager.cfg";
	#if config file exists
	if (-e $expectedConfigFileLoc)
	{
		#my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "The config file does exist");
		#$error->Show;
		open (CONFIGFILE, $expectedConfigFileLoc); 
		while(<CONFIGFILE>)
		{
			chomp($_);
			if($_ =~ m/^WorkingDir=.+/)
			{
				my @configFileSplit = split(/=/);
				chomp($configFileSplit[1]);
				$ESXiWorkingDir = $configFileSplit[1];
			}
			elsif($_ =~ m/CaseDir=.+/)
			{
				my @configFileSplit = split(/=/);
				chomp($configFileSplit[1]);
				$ESXiCasesDir = $configFileSplit[1];
			}
			elsif($_ =~ m/LogFile=.+/)
			{
				my @configFileSplit = split(/=/);
				chomp($configFileSplit[1]);
				$logFileDestination = $configFileSplit[1];
			}
			else
			{
				$consoleLog->insert('end', "Misformated Config file, dont know what $_ is\n");
			}
		}
		close(CONFIGFILE);
	}
	#config file must not exist in the expected location
	else
	{
		#my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "The config file does not exist");
		#$error->Show;
		#$consoleLog->insert('end',"config file does not exist\n");
		my $message = $mw->MsgBox(-title => "Info", -type => "ok", -icon => "info", -message => "It appears this is the first time you are running this program, a configuration file could not be located. The following window will allow you to create a configuration file.");
		$message->Show;
		editSettings();
	}
}

#sanatizes and checks inputs with connect button is clicked, then presents and error or 
#calls another sub to connect to the ESXi server
sub sanitizeInputs
{
	my $ip = $ESXip->get;
	#$consoleLog->insert('end', "$ip\n");
	my $user = $username->get;
	#$consoleLog->insert('end', "$user\n");
	my $password = $password->get;
	$consoleLog->insert('end', "$ip $user $password\n");
	
	my $validInput = 0;
	
	#Check if the a valid IP address was entered
	if(($ip =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/) && ($1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 ))
	{ $validInput++; }
	else
	{
		my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "Please enter a valid ip address.");
		$error->Show;
		#print "Enter a valid ip address. ex. 192.168.0.1\n\n";
	}
	#checks to see if username field has something typed in
	if(length($user) > 0)
	{ $validInput++; }
	else
	{
		my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "Please enter a username.");
		$error->Show;
	}
	#checks to see if password field has something typed in
	if(length($password) > 0)
	{ $validInput++; }
	else
	{
		my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "Please enter a password.");
		$error->Show;
	}
	
	#Calls sub to connect only if input validation has passed
	if($validInput == 3)
	{
		sshToESXi($ip, $user, $password)
		#$consoleLog->insert('end',"going to try and connect\n");
	}
}

#connects to the ESXi server via SSH, may need to make $ssh global so commands can be run outside this sub
sub sshToESXi
{
	my $ip = $_[0];
	my $user = $_[1];
	my $password = $_[2];
	
	$consoleLog->insert('end', "\n*Connection to $ip...");
	$mw->update;
	$ssh = Net::OpenSSH->new("$user:$password\@$ip", master_opts => [ -o => "StrictHostKeyChecking=no"]);
	$ssh->error and die "Could not connect to $ip" . $ssh->error;
	$consoleLog->insert('end', "done!\n");
	$mw->update;
	
	#my $stdout = $ssh->capture("ls -l /vmfs/volumes/");
	#$consoleLog->insert('end', $stdout);
	
	#Are all vm's stored here? Investigate what path is used for each esxi host for iscsi or VMs on a SAN
	findVMs("/vmfs/volumes/", $ip);
}

#find VMs on ESXi server and allows the user to select which VM(s) they want to image
sub findVMs
{
	my @vmxFound;
	my @getVMs;
	my $vmstore = $_[0];
	my $ip = $_[1];
	
	# #creates sub window to display choices of VMs to acquire to user
	# my $subWindow = $mw->Toplevel;
	# $subWindow->title("Virtual Machines found on $ip");
	# my $checkFrame = $subWindow->Frame()->pack(-side => "top");
	# $checkFrame->Label(-text=>"Please select which virtual machines you want to image:")->pack(-side => "left")->pack();
	
	#my $subWindow = $mw->Toplevel;
	#$vmChoicesFrame->title("Virtual Machines found on $ip");
	my $checkFrame = $vmChoicesFrame->Frame()->pack(-side => "top");
	$checkFrame->Label(-text=>"Please select which virtual machines you want to image:")->pack(-side => "top")->pack();
	
	#finds anything with .vmx extenstion meaning it is a VM
	my $stdout = $ssh->capture("find $vmstore -name \"*.vmx\"");
	@vmxFound = split(/\s+/, $stdout);
	
	my @checkButtons;
	my @checkButtonValues;
	my $counter = 0;
	
	#Creates check buttons depending on how many VMs are found on the server
	foreach(@vmxFound)
	{
		$checkButtonValues[$counter] = '0';
		$checkButtons[$counter] = $checkFrame->Checkbutton(-text => $_,
									-onvalue => $_,
                                    -offvalue => '0',
									-variable => \$checkButtonValues[$counter])->pack();
		$counter++;
	}
	
	#Creates ok and cancel button to approve VM selections
	my $buttonFrame = $vmChoicesFrame->Frame()->pack(-side => "bottom");
	my $okButton = $buttonFrame->Button(-text => 'Image',
                                       -command => [\&confirmUserVMImageChoices, \@checkButtonValues]
									   )->pack(-side => "left");
	#my $cancelButton = $buttonFrame->Button(-text => "Cancel", -command => [$subWindow => 'destroy'])->pack();
}

#Confirms the users choices for which VMs they wish to acquire
sub confirmUserVMImageChoices
{
	$consoleLog->insert('end',"--$currentCaseLocation--\n");

	if(!($currentCaseLocation =~ m/[a-z]+|[A-Z]+/))
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "A case has not yet been opened. Open a case before imaging a VM. Current case location is $currentCaseLocation\n");
		$message->Show;
	}
	else
	{
		my $choicesRef = shift; #$_[0];
		my @VMsToImage;
		foreach(@$choicesRef)
		{
		
			#$consoleLog->insert('end',"**Working on --$_--\n");
			if($_ ne '0')
			{
				#$consoleLog->insert('end',"**--$_-- is not 0\n");
				push @VMsToImage, $_;
			}
			else
			{
				#$consoleLog->insert('end',"**--$_-- is 0\n");
			}
		}
		my @shortVMNames;
		foreach(@VMsToImage)
		{
			push @shortVMNames, "\n" .  getFileName($_);
		}
		#my $msgBox = $mw->MsgBox(-title => "Test", -type => "yesno", -icon => "question", -message => "Would you like to image the following VMs?: @shortVMNames");
		#$msgBox->Show;
		my $messageBoxAnswer = $mw->messageBox(-title => "Test", -type => "YesNo", -icon => "question", -message => "Would you like to image the following VMs?: @shortVMNames", -default => "yes");
		#my $messageBoxAnswer => $mw->Dialog(-title => "Test", -bitmap => "question", -text => "Would you like to image the following VMs?: @shortVMNames", -buttons => ['Yes', 'No'], -default_button => "Yes");
		$consoleLog->insert('end',"**Message box answer: --$messageBoxAnswer--\n");
		if ($messageBoxAnswer eq 'Yes')
		{
			$consoleLog->insert('end',"**Message box answer $messageBoxAnswer was yes\n");
			#$subWindow->destroy;
			foreach(@VMsToImage)
			{
				$consoleLog->insert('end',"Working on $_\n");
				my $targetImageFile = ddTargetFile($_, getFileName($_));
				#print "Going to SFTP $targetImageFile to this computer\n";
				my $ip = $ESXip->get;
				$consoleLog->insert('end',"Going to SFTP $targetImageFile to this computer from esxi server at IP $ip\n");
				$mw->update;
				sftpTargetFileImage($ip,$targetImageFile);
			}
		}
		else
		{
			$consoleLog->insert('end',"**Message box answer $messageBoxAnswer was no\n");
		}
	}
}

#DD target VMs, expects the absolute path and the filename 
sub ddTargetFile
{

	#!!check to see if ddimages directory exists!! figure out later
	#print "\n\n---------------------------\nCreating DD copy of target file\n";
	my $absolutePathFileToDD = $_[0];
	my $fileToDD = $_[1];
	my $fileToDDDestinationName  = $fileToDD;
	#This was a much easier solution to determining where to dd the file to
	my $ddDestination = $absolutePathFileToDD . ".dd";
	#$fileToDDDestinationName =~ s/vmx/dd/;
	#print "dd destination name $fileToDDDestinationName\n";
	#my @fileToDDSplit = split('.',$fileToDD);
	

#print "0 ". $fileToDDSplit[0] . "1 " . $fileToDDSplit[1] . "\n";
	#Took out datastore1 b/c with esxi4 does not have a datastore1, this may have to be changed depending on how it works with a NAS involved
	#my $ddDestination = "/vmfs/volumes/datastore1/ddimages" . "/" . $fileToDDDestinationName;
	#my $ddDestination = "/vmfs/volumes/ddimages" . "/" . $fileToDDDestinationName;
	#Instead, place the dd image file in the same directory as the orig. Could be changed
	#to "find" the storage directory and make a directory by splitting and poping the 
	#absolute path apart but this should work for now 

#print "dd dest $ddDestination\n";
#my $s=<STDIN>;
	my $md5 = calculateMD5HashOnESX($absolutePathFileToDD);
	my $sha1 = calculateSHA1HashOnESX($absolutePathFileToDD);

	#print "Hashes Before DD:\n \tMD5: $md5\n \tSHA1: $sha1\n";
	$consoleLog->insert('end',"Hashes Before DD:\n \tMD5: $md5\n \tSHA1: $sha1\n");
	$mw->update;
	sleep(1);

	my $stdout = $ssh->capture("dd if=$absolutePathFileToDD of=$ddDestination");
	
	my $pathToHash = $ddDestination;
	my $md5Check = calculateMD5HashOnESX($pathToHash);
	my $sha1Check = calculateSHA1HashOnESX($pathToHash);
	#print "Hashes After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check\n";
	$consoleLog->insert('end',"Hashes After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check\n");
	$mw->update;
	sleep(1);
	return $pathToHash;

}

#SFTP target VMs, expects esxi server IP and absolute path to target dd file
sub sftpTargetFileImage
{
	my $serverIP = $_[0];
	my $fileToSFTP = $_[1];

	my %args; #= ( user => 'root',password => 'netsys01');

	my $user = $username->get;
	#$consoleLog->insert('end', "$user\n");
	my $password = $password->get;
	my $host= '192.168.100.141';
	$consoleLog->insert('end', "Going to connect to $serverIP with credeitials $user and $password\n");
	$mw->update;
	my $sftp = Net::SFTP::Foreign->new($serverIP,  user => $user, password => $password);
	$sftp->die_on_error("SSH Connection Failed");
	
	my @filePathParts2 = split('/', $fileToSFTP);
	my $getFileName2 = pop(@filePathParts2);
	
	#Now that we have a cases directory, the images need to be saved to that directory
	#my $localDestination = "/home/matt/Desktop/" . $getFileName2;
	my $localDestination = $currentCaseLocation . "/" . $getFileName2;
	$consoleLog->insert('end', "Transfering file from:$fileToSFTP to:$localDestination\n");
	$mw->update;

	#print "This file will SFTP from $fileToSFTP to $localDestination\n";
	#my $f=<STDIN>;

	#Create progress bar to show user program is doing something
	my $percentDone = 0;
	my $subWindow = $mw->Toplevel;
	$subWindow->title("Transfering Image");
	$subWindow->geometry("300x30");
	my $progressBar = $subWindow->ProgressBar(-width => 30, -blocks => 50, -from => 0, -to => 100, -variable => \$percentDone)->pack(-fill => 'x');
	
	$sftp->get($fileToSFTP,$localDestination, callback => sub {
		my ($sftp, $data, $offset, $size) = @_;
		print "$offset of $size bytes read\n";
		$percentDone = ($offset / $size) * 100;
		$subWindow->update;
	
	}); #or die "File transfer failed\n";
	$subWindow->destroy;
	#With transfer complete, destroy the progress bar window
	
	my $md5Check = calculateMD5HashLocal($localDestination);
	my $sha1Check = calculateSHA1HashLocal($localDestination);
	#print "Hashes After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check\n";
	$consoleLog->insert('end',"Hashes After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check\n");
	sleep(1);
}

#Allows user to edit settings of program. Location where cases, log files, etc are stored. Maybe additional configurable options later
#Will be run from the Tools->Setttings menu bar or run from the readConfigFile sub if no configuration file is found
sub editSettings
{

	if (-e $configFileLocation)
	{
		#my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "The config file does exist");
		#$error->Show;
		#open (CFGFILE, $expectedConfigFileLoc); 
		open (CONFIGFILE, $configFileLocation); 
		while(<CONFIGFILE>)
		{
			chomp($_);
			if($_ =~ m/^WorkingDir=.+/)
			{
				my @configFileSplit = split(/=/);
				chomp($configFileSplit[1]);
				$ESXiWorkingDir = $configFileSplit[1];
			}
			elsif($_ =~ m/CaseDir=.+/)
			{
				my @configFileSplit = split(/=/);
				chomp($configFileSplit[1]);
				$ESXiCasesDir = $configFileSplit[1];
			}
			elsif($_ =~ m/LogFile=.+/)
			{
				my @configFileSplit = split(/=/);
				chomp($configFileSplit[1]);
				$logFileDestination = $configFileSplit[1];
			}
			else
			{
				$consoleLog->insert('end', "Misformated Config file, dont know what $_ is\n");
			}
		}
		close(CONFIGFILE);
	}
	#config file must not exist in the expected location
	else
	{
		$configFileLocation = $ENV{"HOME"} . "/ESXimager/ESXimager.cfg";
		$ESXiWorkingDir = $ENV{"HOME"} . "/ESXimager";
		$ESXiCasesDir = $ESXiWorkingDir . "/Cases/";
		$logFileDestination = $ESXiWorkingDir . "/ESXimager.log";
	}

	my $settingsWindow = $mw->Toplevel;
	$settingsWindow->title("Settings");
	
	#label for configuration file location
	$settingsWindow->Label(-text => "Configuration File Location: $configFileLocation")->grid(-row => 0, -column => 0);
	
	#label for working directory location
	$settingsWindow->Label(-text => "ESXimager Working Directory: ")->grid(-row => 1, -column => 0, -sticky => "e");
	#entry for working directory location
	my $workingDirLocation = $settingsWindow->Entry( -width => 40, -text => $ESXiWorkingDir)->grid(-row => 1, -column => 1);
	
	#label for cases location
	$settingsWindow->Label(-text => "Cases Directory: ")->grid(-row => 2, -column => 0, -sticky => "e");
	#entry for cases location
	my $caseLocation = $settingsWindow->Entry( -width => 40, -text => $ESXiCasesDir)->grid(-row => 2, -column => 1);
	
	#label for log file location
	$settingsWindow->Label(-text => "Log File: ")->grid(-row => 3, -column => 0, -sticky => "e");
	#entry for log file location
	my $logFileLocation = $settingsWindow->Entry( -width => 40, -text => $logFileDestination)->grid(-row => 3, -column => 1);

	#connect button, calls sub to update the configuration file (or create it if it does not exist yet)
	#puts the buttons in a frame at the bottom of the window
	my $settingsWindowBottomFrame = $settingsWindow->Frame;
	$settingsWindowBottomFrame->grid(-row => 4, -column => 0, -columnspan => 2);
	#$settingsWindowBottomFrame->Button(-text => "Save", -command => \&saveConfigFile )->pack(-side => "left");	
	$settingsWindowBottomFrame->Button(-text => "Save", -command => sub {
		$ESXiWorkingDir = $workingDirLocation->get;
		$ESXiCasesDir = $caseLocation->get;
		$logFileDestination = $logFileLocation->get;
		#checks to see if working directory structure exists then creates it if necessary
		unless (-e $ESXiWorkingDir or mkdir($ESXiWorkingDir, 0755))
		{die "Unable to create $ESXiWorkingDir";}
		open (CONFIGFILE, ">$configFileLocation");
		print CONFIGFILE "WorkingDir=$ESXiWorkingDir\n";
		print CONFIGFILE "CaseDir=$ESXiCasesDir\n";
		print CONFIGFILE "LogFile=$logFileDestination\n";
		close(CONFIGFILE);
		$consoleLog->insert('end', "Config File Saved\n");
	})->pack(-side => "left");	
	my $cancelButton = $settingsWindowBottomFrame->Button(-text => "Exit", -command => [$settingsWindow => 'destroy'])->pack(-side => "left");
}

#sub to create a new case, esentially all it does is create a directory under whatever $ESXiCasesDir is and updates the label in $mw
sub createNewCase
{
	my $createCaseWindow = $mw->Toplevel;
	$createCaseWindow->title("Create New Case");
	
	#label for configuration file location
	$createCaseWindow->Label(-text => "Case Directory Location: $ESXiCasesDir")->grid(-row => 0, -column => 0);
	
	#label for working directory location
	$createCaseWindow->Label(-text => "Case Name: ")->grid(-row => 1, -column => 0, -sticky => "e");
	#entry for working directory location
	my $newCaseName = $createCaseWindow->Entry( -width => 40)->grid(-row => 1, -column => 1);
	
	my $createCaseWindowBottomFrame = $createCaseWindow->Frame;
	$createCaseWindowBottomFrame->grid(-row => 2, -column => 0, -columnspan => 2);
	#$settingsWindowBottomFrame->Button(-text => "Save", -command => \&saveConfigFile )->pack(-side => "left");	
	$createCaseWindowBottomFrame->Button(-text => "Create", -command => sub {
		$currentCaseName = $newCaseName->get;
		my $newCaseDirPath = $ESXiCasesDir . $currentCaseName;
		#checks to see if cases directory structure exists then creates it if necessary
		unless (-e $ESXiCasesDir or mkdir($ESXiCasesDir, 0755))
		{die "Unable to create $ESXiCasesDir";}
		
		#Checks to see if case name user wants to make already exists
		if (-e $newCaseDirPath)
		{
			my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "The case name: $currentCaseName already exists. Please use another case name.");
			$error->Show;
		}
		else
		{
			mkdir ($newCaseDirPath, 0755);
			$currentCaseLocation = $newCaseDirPath;
			$consoleLog->insert('end', "Created new case: $currentCaseName Location: $currentCaseLocation\n");
			$caseLabel->configure(-text => "Current Case: $currentCaseName Location: $currentCaseLocation");
		}
		
	})->pack(-side => "left");	
	my $cancelButton = $createCaseWindowBottomFrame->Button(-text => "Exit", -command => [$createCaseWindow => 'destroy'])->pack(-side => "left");
}

#***********************************************************************************************************************************#
#******Start of Commonly Used Subs to Make Life Better******************************************************************************#
#***********************************************************************************************************************************#

#Sub is passed long absolute path of a file and returns the file name and extenstion
#ex. sub is passed /var/storage/foo/bar.vmx and returns bar.vmx
sub getFileName
{
	my $absolutePath = $_[0];
	my $fileName;

	my @fileNameParts = split('/',$absolutePath);
	$fileName = pop @fileNameParts;
	return $fileName;
}

#Calculate MD5 hash of file about to be copied on ESX server
sub calculateMD5HashOnESX
{
	my $fileToHash = $_[0];
	
	#print "*Calculating md5 hash this may take a while be patient...";
	$consoleLog->insert('end',"*Calculating md5 hash this may take a while be patient...");
	my $stdout = $ssh->capture("md5sum $fileToHash");
	#print "done!\n";
	$consoleLog->insert('end',"done!\n");
	chomp $stdout;
	return $stdout;   
}

# Calculate SHA1 hash of the file about to be copied on ESX server
sub calculateSHA1HashOnESX
{
	my $fileToHash = $_[0];
	
	#print "*Calculating sha1 hash this may take a while be patient...";
	$consoleLog->insert('end',"Calculating sha1 hash this may take a while be patient...");
	my $stdout = $ssh->capture("sha1sum $fileToHash");
	#print "done!\n";
	$consoleLog->insert('end',"done!\n");
	chomp $stdout;
	return $stdout;   
}

#Calculate MD5 hash of local file
sub calculateMD5HashLocal
{
	my $fileToHash = $_[0];
	my $operatingSystem = checkOS();
	
	#print "*Calculating md5 hash this may take a while be patient...";
	$consoleLog->insert('end',"*Calculating md5 hash this may take a while be patient...");
	my $stdout = `md5sum $fileToHash` if $operatingSystem == 1;
	my $stdout = `md5 $fileToHash` if $operatingSystem == 2;
	
	my @split = split (/\s+/, $stdout);
	#print "$split[$#split]\n" if $operatingSystem == 2;
	#print "$split[0]\n" if $operatingSystem == 1;
	
	#[$#split] gives you the last element of an array
	$stdout = $split[0] if $operatingSystem == 1;
	$stdout = $split[$#split] if $operatingSystem == 2;

	#$stdout = $ssh->capture("md5sum $fileToHash");
	#print "done!\n";
	$consoleLog->insert('end',"done!\n");
	chomp $stdout;
	return $stdout;   
}

# Calculate SHA1 hash of local file
sub calculateSHA1HashLocal
{
	my $fileToHash = $_[0];
	my $operatingSystem = checkOS();
	
	#print "*Calculating sha1 hash this may take a while be patient...";
	$consoleLog->insert('end',"*Calculating sha1 hash this may take a while be patient...");
	my $stdout = `sha1sum $fileToHash` if $operatingSystem == 1;
	my $stdout = `shasum $fileToHash` if $operatingSystem == 2;
	
	#shasum on osx has same output as linux sha1sum
	my @split = split (/\s+/, $stdout);
	#print "$split[$#split]\n" if $operatingSystem == 2;
	#print "$split[0]\n" if $operatingSystem == 1;
	
	#[$#split] gives you the last element of an array
	$stdout = $split[0] if $operatingSystem == 1;
	$stdout = $split[0] if $operatingSystem == 2;

	
	#$stdout = $ssh->capture("sha1sum $fileToHash");
	#print "done!\n";
	$consoleLog->insert('end',"done!\n");
	chomp $stdout;
	return $stdout;   
}

#Because I am developing this on both OSX and linux I need to ensure
#the script would work on both linux and OSX. The reason being is that linux
#used the command 'md5sum' whereas OSX just uses 'md5'
sub checkOS
{
	my $OS = $^O;
	my $osValue;
	if($OS eq "linux")
	{
		$osValue = 1;
	}
	#darwin aka osx
	elsif($OS eq "darwin")
	{
		$osValue = 2;
	}
	else
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "You are running an operating system that this script is not designed to work for...\nYour operating system is: $^O\nSupported operating systems are Linux (linux) and OSX (darwin)\n");
		$message->Show;
		#print "! You are running an operating system that this script is not designed to work for...\n";
		#print "! Your operating system is: $^O\n";
		#print "! Supported operating systems are Linux (linux) and OSX (darwin)\n";
		exit;
	}
	return $osValue;
}
#***********************************************************************************************************************************#
#******End of Commonly Used Subs to Make Life Better********************************************************************************#
#***********************************************************************************************************************************#

# # # sub
# # # {
	# # # foreach(@checkButtonValues)
	# # # {
		# # # $consoleLog->insert('end', "$_\n");
	# # # }
	
# # # }

sub foo
{
	my $subWindow = $mw->Toplevel;
	$subWindow->title("foo");
	my $test = "hello world\nfoo\nbar";
	$consoleLog->insert('end',$test);
	$subWindow->Button(-text => "close window", -command => [$subWindow => 'destroy'])->pack();
}

#Wait for events
MainLoop;