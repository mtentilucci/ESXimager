#!/usr/bin/perl
use strict;
use warnings;
use Tk;
use Tk::ProgressBar;
use Tk::MsgBox;
use Tk::DirTree;
use Tk::Pane;
use Tk::Font;
use Net::OpenSSH;
use Net::SFTP::Foreign;
use Data::Dumper;
use Time::HiRes;

########################
#ESXimager2.9.pl
#Matt Tentilucci	
#mjt5206@psu.edu
#3-4-2014
########################

#Before the config file is read and the desired log file location is determined, I want to log debug messages so I will utilize this array
my @debugMessages;
push @debugMessages, logIt("[debug] (main) Program opened.",0,0,0,0);
push @debugMessages, logIt("[debug] (main) Initilizing some variables.",0,0,0,0);
#variable so ssh session to esxi can be accessible outside of sub
my $ssh;
my $checkFrame1;
my $checkFrame2;
my $buttonFrame1;
my $buttonFrame2;
#used for storing the data structure of the case integrity file
my $hashRef;
#hash ref used to save hashes of a file as it is being imaged. This will be added into $hasRef and reset once a praticular file has been imaged
my $processingHashRef;
my $preMD5;
my $preSHA1;

#Variables for location of working directory, case directory, configuration file, and log file
my $configFileLocation = $ENV{"HOME"} . "/ESXimager/ESXimager.cfg";
my $ESXiWorkingDir;
my $ESXiCasesDir;
my $logFileDestination;
my $currentCaseName = "No Case Opened Yet";
my $currentCaseLocation;
my $currentCaseLog;
my $currentCaseIntegrityFile;

push @debugMessages, logIt("[debug] (main) Done initilizing variables.",0,0,0,0);

#Creates main window
my $mw = MainWindow->new;
push @debugMessages, logIt("[debug] (main) Creating MainWindow.",0,0,0,0);
$mw->title("ESXimager 2.9");
$mw->geometry("1400x600");

#Create menu bar
push @debugMessages, logIt("[debug] (main) Creating menu bar.",0,0,0,0);
$mw->configure(-menu => my $menubar = $mw->Menu);
my $file = $menubar->cascade(-label => '~File');
my $tools = $menubar->cascade(-label => '~Tools');
my $view = $menubar->cascade(-label => '~View');
my $help = $menubar->cascade(-label => '~Help');

$file->command(-label => 'New Case', -underline => 0, -command => \&createNewCase);
$file->command(-label => 'Open Case', -underline => 0, -command => \&openExistingCase);
$file->separator;
$file->command(-label => "Quit", -underline => 0, -command => \&exit);

$tools->command(-label => "Verify Integrity", -command => \&checkImageIntegrity);
$tools->command(-label => "Settings", -command => \&editSettings);

$help->command(-label => "About", -command => \&showHelp);

#console window
#Anytime print is used, it will output to the $consoleLog window
push @debugMessages, logIt("[debug] (main) Creating ConsoleLog window.",0,0,0,0);
my $consoleLog = $mw->Scrolled('Text',-height => 10, -width => 125)->pack(-side => 'bottom', -fill => 'both');
tie *STDOUT, 'Tk::Text', $consoleLog->Subwidget('scrolled');

##Connection Frame##
push @debugMessages, logIt("[debug] (main) Creating Connection Frame.",0,0,0,0);
#Create top left frame for holding username, password, server IP, connect button widgets
my $connectionFrame = $mw->Frame(-borderwidth => 2, -relief => 'groove');
$connectionFrame->pack;#(-side => 'left', -anchor => 'nw');
#label for IP
$connectionFrame->Label(-text => "Server IP")->pack(-side => 'left', -anchor => 'n');
#entry for IP
my $ESXip = $connectionFrame->Entry( -width => 20, -text => "192.168.100.142")->pack(-side => 'left', -anchor => 'n');
#Label for user
$connectionFrame->Label(-text => "Username")->pack(-side => 'left', -anchor => 'n');
#entry for user
my $username = $connectionFrame->Entry( -width => 20,  -text => "root")->pack(-side => 'left', -anchor => 'n');
#label for pass
$connectionFrame->Label(-text => "Password")->pack(-side => 'left', -anchor => 'n');
#entry for pass
my $password = $connectionFrame->Entry( -width => 20, -show => "*",  -text => "netsys01")->pack(-side => 'left', -anchor => 'n');
#connect button, first calls sub to do input sanitization and checking on ip, username, and password boxes then 
#either falls out with an error, or another sub is called to connect to the ESXi server
$connectionFrame->Button(-text => "Connect", -command => \&sanitizeInputs )->pack(-side => 'left', -anchor => 'n');	
##End Connection Frame##

#Creates a label in the top left display the case currently "open"
my $caseLabel = $mw->Label(-text => "$currentCaseName. You must open a case before imaging a VM")->pack;#(-side => 'left', -anchor => 'nw');

##Dir File Frame##	
push @debugMessages, logIt("[debug] (main) Creating Dir File Frame.",0,0,0,0);
my $dirFileFrame = $mw->Frame(-borderwidth => 2, -relief => 'groove');
$dirFileFrame->pack(-side => 'right', -fill => 'both');
###Dir Tree Frame##
push @debugMessages, logIt("[debug] (main) Creating Dir Tree Frame.",0,0,0,0);
my $dirTreeFrame = $dirFileFrame->Frame(-borderwidth => 2, -relief => 'groove');
$dirTreeFrame->pack(-side => 'left', -fill => 'both');
my $dirTree = $dirTreeFrame->Scrolled('DirTree', -scrollbars => 'e', -directory => $ESXiCasesDir, -width => 35, -height => 20, -browsecmd => \&listFiles)->pack(-side => 'left',  -anchor => 'n', -fill => 'both');
###End Dir Tree Frame##
###File List Frame##
push @debugMessages, logIt("[debug] (main) Creating File List Frame.",0,0,0,0);
my $fileListFrame = $dirFileFrame->Frame(-borderwidth => 2, -relief => 'groove');
$fileListFrame->pack(-side => 'right', -fill => 'both');
my $fileList = $fileListFrame->Scrolled('Listbox', -scrollbars => 'e', -width => 40, -height => 15)->pack(-side => 'top',  -anchor => 'n', -fill => 'both', -expand => 1);

$fileListFrame->Label(-text => "Display Selected File In: ")->pack(-side => 'left', -anchor => 's', -fill => 'both');
my $stringsButton = $fileListFrame->Button(-text => "Strings", -command => [\&runThroughStrings, \$fileList])->pack(-side => 'left', -anchor => 's', -fill => 'both', -expand => 1);
my $hexdumpButton = $fileListFrame->Button(-text => "Hexdump", -command => [\&runThroughHexdump, \$fileList])->pack(-side => 'left', -anchor => 's', -fill => 'both', -expand => 1);
###End File List Frame##
##End Dir Tree Frame##
#This needs to go after $fileList is defined
$view->command(-label => "File Information", -command => [\&viewFileInfo, \$fileList]);

##VM Choices Frame##
push @debugMessages, logIt("[debug] (main) Creating VM Choices Frame.",0,0,0,0);
my $vmChoicesFrame = $mw->Frame(-borderwidth => 2, -relief => 'groove');
$vmChoicesFrame->pack(-side => 'left', -fill => 'both', -expand => 1);
my $vmChoicesLabel = $vmChoicesFrame->Label(-text => "Connect to an ESXi server to populate\n")->pack;
##EndVM Choices Frame##

$consoleLog->see('end');

push @debugMessages, logIt("[debug] (main) Done creating Main Window.",0,0,0,0);
checkOS();
readConfigFile();

#This needs to be called after the config file is opened and $ESXiCasesDir defined
listFiles($ESXiCasesDir);
#In addition to opening the program log file, we can open and print out everything to our debug log file
my $debugLogLocation = $logFileDestination;
$debugLogLocation =~ s/\.log/Debug\.log/;
open (DEBUGLOGFILE, ">>$debugLogLocation");
{ my $ofh = select DEBUGLOGFILE;
  $| = 1;
  select $ofh;
}
foreach(@debugMessages)
{
	print DEBUGLOGFILE $_
}
#With the config file read, we now know where the ovarall $logFileDestination is so we can open a file handle
open (PROGRAMLOGFILE, ">>$logFileDestination");
#Make file handle 'hot' so lines don't get buffered before printing http://perl.plover.com/FAQs/Buffering.html
{ my $ofh = select PROGRAMLOGFILE;
  $| = 1;
  select $ofh;
}
logIt("[info] (main) Initilized... GREETINGS PROFESSOR FALKEN.", 1, 0, 1);

#Reads the configuration file for this program. It looks in /home/user/ESXimager/ESXimager.cfg
#If it does not find a config file it will prompt the user to create one, bringing them to the 
#configuration window. Otherwise, the config file is loaded and the storage locations defined in it are used
sub readConfigFile
{
	my $expectedConfigFileLoc = $ENV{"HOME"} . "/ESXimager/ESXimager.cfg";
	#if config file exists
	if (-e $expectedConfigFileLoc)
	{
		push @debugMessages, logIt("[debug] (main) Found config file in expected location, here: $expectedConfigFileLoc.",0,0,0,0);
		open (CONFIGFILE, $expectedConfigFileLoc); 
		push @debugMessages, logIt("[debug] (main) Reading config file.",0,0,0,0);
		while(<CONFIGFILE>)
		{
			chomp($_);
			if($_ =~ m/^WorkingDir=.+/)
			{
				my @configFileSplit = split(/=/);
				chomp($configFileSplit[1]);
				$ESXiWorkingDir = $configFileSplit[1];
				push @debugMessages, logIt("[debug] (main) Setting ESXi Working Dir to: $ESXiWorkingDir.",0,0,0,0);
			}
			elsif($_ =~ m/CaseDir=.+/)
			{
				my @configFileSplit = split(/=/);
				chomp($configFileSplit[1]);
				$ESXiCasesDir = $configFileSplit[1];
				push @debugMessages, logIt("[debug] (main) Setting ESXi cases directory to: $ESXiCasesDir.",0,0,0,0);
				$dirTree->chdir($ESXiCasesDir);
				listFiles($ESXiCasesDir);
			}
			elsif($_ =~ m/LogFile=.+/)
			{
				my @configFileSplit = split(/=/);
				chomp($configFileSplit[1]);
				$logFileDestination = $configFileSplit[1];
				push @debugMessages, logIt("[debug] (main) Setting log file destination to: $logFileDestination.",0,0,0,0);
			}
			else
			{
				push @debugMessages, logIt("[debug] (main) Misformated Config file, dont know what $_ is.",0,0,0,0);
				$consoleLog->insert('end', "Misformated Config file, dont know what $_ is\n");
				$consoleLog->see('end');
			}
		}
		close(CONFIGFILE);
	}
	#config file must not exist in the expected location
	else
	{
		push @debugMessages, logIt("[debug] (main) No config file could be located. Going to create config file.",0,0,0,0);
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
	my $user = $username->get;
	my $password = $password->get;
	logIt("[info] (main) Sanatizing inputs...", 1, 0, 1);

	my $validInput = 0;
	
	#Check if the a valid IP address was entered
	if(($ip =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/) && ($1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 ))
	{ $validInput++; }
	else
	{
		logIt("[error] (main) Please enter a valid ip address.", 1, 0, 1);
		my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "Please enter a valid ip address.");
		$error->Show;
	}
	#checks to see if username field has something typed in
	if(length($user) > 0)
	{ $validInput++; }
	else
	{
		logIt("[error] (main) Please enter a username.", 1, 0, 1);
		my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "Please enter a username.");
		$error->Show;
	}
	#checks to see if password field has something typed in
	if(length($password) > 0)
	{ $validInput++; }
	else
	{
		logIt("[error] (main) Please enter a password.", 1, 0, 1);
		my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "Please enter a password.");
		$error->Show;
	}
	
	#Calls sub to connect only if input validation has passed
	if($validInput == 3)
	{
		logIt("[info] (main) Done sanatizing inputs.", 1, 0, 1);
		sshToESXi($ip, $user, $password)
	}
}

#connects to the ESXi server via SSH, may need to make $ssh global so commands can be run outside this sub
sub sshToESXi
{
	my $ip = $_[0];
	my $user = $_[1];
	my $password = $_[2];
	
	logIt("[info] (main) Attempting to connect to ESXi server at $ip...", 1, 0, 1);
	$mw->update;
	$ssh = Net::OpenSSH->new("$user:$password\@$ip", master_opts => [ -o => "StrictHostKeyChecking=no"]);
	if(!$ssh->error)
	{
		logIt("[info] (main) Succesfully connected to $ip", 1, 0, 1);
		$mw->update;
		#Are all vm's stored here? Investigate what path is used for each esxi host for iscsi or VMs on a SAN
		findVMs("/vmfs/volumes/", $ip);
	}
	else
	{
		logIt("[error] (main) Failed to connect to $ip " . $ssh->error, 1, 0, 1);
		my $error = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "Failed to connect to $ip " . $ssh->error);
		$error->Show;
	}
}

#Step 1: $checkFrame1 and $buttonFrame1 - find VMs on ESXi server and allows the user to select which VM(s) they want to image
sub findVMs
{
	#destroys the two frames from the selectVMFiles sub if they are defined. Either the user hit the back button or they imaged a VM which returns to this screen when completed
	if (defined $checkFrame2 && defined $buttonFrame2)
	{
		$checkFrame2->destroy();
		$buttonFrame2->destroy();
	}

	my @vmxFound;
	my @getVMs;
	my $vmstore = $_[0];
	my $ip = $_[1];
	
	#make the checkbox frame scrollable incase there are multiple VMs/files that go beyond the window size
	$checkFrame1 = $vmChoicesFrame->Scrolled('Pane',-scrollbars => 'osoe')->pack(-side => 'top', -fill => 'both', -expand => 1);
	if (defined $vmChoicesLabel)
	{
		$vmChoicesLabel->packForget;
	}
	$checkFrame1->Label(-text=>"Please select which virtual machines you want to image:")->pack(-side => "top")->pack();
	
	#finds anything with .vmx extension meaning it is a VM
	my $stdout = $ssh->capture("find $vmstore -name \"*.vmx\"");
	@vmxFound = split(/\s+/, $stdout);
	
	my @checkButtons;
	my @checkButtonValues;
	my $counter = 0;
	
	#Creates check buttons depending on how many VMs are found on the server
	foreach(@vmxFound)
	{
		$checkButtonValues[$counter] = '0';
		$checkButtons[$counter] = $checkFrame1->Checkbutton(-text => $_,-onvalue => $_,-offvalue => '0',-variable => \$checkButtonValues[$counter])->pack();
		$counter++;
	}
	
	#Creates ok and cancel button to approve VM selections
	$buttonFrame1 = $vmChoicesFrame->Frame()->pack(-side => "bottom");
	my $okButton = $buttonFrame1->Button(-text => 'Next', -command => [\&selectVMFiles, \@checkButtonValues])->pack(-side => "left");
}

#Step 2: $checkFrame2 and $checkFrame2 - destroys the frames from the findVMs sub and replaces them with files assiciated with the VMs they want to image.
#Asks the user what files they want to acquire, .vmx .vmdk .vmem etc.....
sub selectVMFiles
{
	my @vmsToRestart;
	if($currentCaseName =~ m/No Case Opened Yet/)
	{
		logIt("[error] (main) A case has not yet been opened. Open a case before imaging a VM.", 1, 0, 1);
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "A case has not yet been opened. Open a case before imaging a VM.\n");
		$message->Show;
	}
	else
	{
		my $choicesRef = shift; #$_[0];
		my @findVMFiles;
		foreach(@$choicesRef)
		{
			if($_ ne '0')
			{
				push @findVMFiles, $_;
			}
			else
			{}
		}
		my $count = @findVMFiles;
		if ($count == 0)
		{	
			logIt("[error] ($currentCaseName) No VM's were selected to be imaged.", 1, 1, 1);
			my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "No VM's were selected to be imaged.\n");
			$message->Show;
		}
		else
		{
			foreach(@findVMFiles)
			{
				logIt("[info] ($currentCaseName) Checking state of Virtual Machine: $_", 1, 1, 1);
				my $vmStatus = checkIfVMRunning($_);
				if ($vmStatus == 1)
				{
					logIt("[info] ($currentCaseName) Virtual Machine: $_ is running.", 1, 1, 1);
					my $messageBoxAnswer = $mw->messageBox(-title => "Suspend Virtual Machine?", -type => "YesNo", -icon => "question", -message => "$_ is currently powered on and running.\nIt is strongly recommended the virtual machine be suspended before imaging.\nDo you want to suspend it?\n", -default => "yes");
					if ($messageBoxAnswer eq 'Yes')
					{
						logIt("[info] ($currentCaseName) User has selected to suspend $_. The virtual machine will be restarted once imaging is complete.", 1,1,1);
						suspendVM($_);
						push @vmsToRestart, $_;						
					}
				}
				else
				{
					logIt("[info] ($currentCaseName) Virtual Machine: $_ is not running.", 1, 1, 1);
				}
			}
			$checkFrame1->destroy();
			$buttonFrame1->destroy();
			
			my @checkButtons;
			my @checkButtonValues;
			my $counter = 0;
			$checkFrame2 = $vmChoicesFrame->Scrolled('Pane', -scrollbars => 'osoe')->pack(-side => 'top', -fill => 'both', -expand => 1);
			
			foreach(@findVMFiles)
			{
				my $VMDirPath = getDirName($_);
				#lists (ls) the given directory on the esxi server
				my $stdout = $ssh->capture("ls $VMDirPath");
				my @filesFound = split(/\s+/, $stdout);
				
				foreach(@filesFound)
				{
					my $filePath = $VMDirPath . $_;
					$checkButtonValues[$counter] = '0';
					$checkButtons[$counter] = $checkFrame2->Checkbutton(-text => $filePath,-onvalue => $filePath,-offvalue => '0',-variable => \$checkButtonValues[$counter])->pack();
					$counter++;
				}
			}
			#Creates ok and cancel button to approve VM selections
			$buttonFrame2 = $vmChoicesFrame->Frame()->pack(-side => "bottom");
			my $backButton = $buttonFrame2->Button(-text => 'Back',-command => [\&findVMs])->pack(-side => "left");
			my $okButton = $buttonFrame2->Button(-text => 'Next',-command => [\&confirmUserVMImageChoices, \@checkButtonValues, \@vmsToRestart])->pack(-side => "left");
		}		
	}
}

#Step 3: Confirms the users choices for which VMs they wish to acquire, expects a refrence to the array of checkButton choices as well as a 
#refrence to the array of VMs that need to be restarted once imaging is complete
sub confirmUserVMImageChoices
{
	if($currentCaseName =~ m/No Case Opened Yet/)
	{
		logIt("[error] (main) A case has not yet been opened. Open a case before imaging a VM.", 1, 0, 1);
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "A case has not yet been opened. Open a case before imaging a VM.\n");
		$message->Show;
	}
	else
	{
		my $choicesRef = $_[0]; #shift; #$_[0];
		my $vmsToRestartRef = $_[1];
		my @VMsToImage;
		foreach(@$choicesRef)
		{
			if($_ ne '0')
			{
				push @VMsToImage, $_;
			}
			else
			{}
		}
		
		my $count = @VMsToImage;
		if ($count == 0)
		{
			logIt("[error] ($currentCaseName) No files were selected to be imaged.", 1, 1, 1);
			my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "No files were selected to be imaged.\n");
			$message->Show;
		}
		else
		{
			my @shortVMFileNames;
			foreach(@VMsToImage)
			{
				push @shortVMFileNames, "\n" .  getFileName($_);
			}
			my $messageBoxAnswer = $mw->messageBox(-title => "Confirm File Selection", -type => "YesNo", -icon => "question", -message => "Would you like to image the following VMs files?: @shortVMFileNames", -default => "yes");
			if ($messageBoxAnswer eq 'Yes')
			{
				logIt("[info] ($currentCaseName) the following files will be imaged: @shortVMFileNames", 1, 1, 1);
				my @fileNames;
				my $startTime = time();
				foreach(@VMsToImage)
				{
					#delete whatever is currently in the processing hash ref 
					#we want to only have hash values for a praticular file  
					$processingHashRef = {};
					for (keys %$processingHashRef)
					{
						delete $processingHashRef->{$_};
					}
					
					logIt("[info] ($currentCaseName) Working on $_", 1, 1, 1);
					
					my $targetImageFile = ddTargetFile($_);
					my $ip = $ESXip->get;
					logIt("[info] ($currentCaseName) Going to SFTP $targetImageFile to this computer from ESXi server at IP $ip", 1, 1, 1);
					$mw->update;
					sftpTargetFileImage($targetImageFile);
					my $filename = getFileName($targetImageFile);
					push @fileNames, $filename;
					#print "Hash REf: $hashRef File: $filename ProcessingHashReg: $processingHashRef\n";
					$hashRef->{$filename} = $processingHashRef;
				}	
				my $arrayRef = \@fileNames;
				checkImageIntegrity($arrayRef);
				
				#Restart VMs that were suspended once the imaging process is complete
				logIt("[info] ($currentCaseName) Attempting to restart suspended VMs.", 1, 1, 1);
				foreach (@$vmsToRestartRef)
				{
					startVM($_);
				}
				#After imaging is complete, we want to write our $hashRef data scructure containing all the hash history to the case integrity file
				my $caseIntegrityFileLocation = $currentCaseLocation . "/" . $currentCaseName . ".integrity";
				open ($currentCaseIntegrityFile, ">$caseIntegrityFileLocation");
				logIt("[info] ($currentCaseName) Writing to integrity file", 1, 1, 1);
				print $currentCaseIntegrityFile Data::Dumper->Dump([$hashRef], [qw/digest/]);
				close($currentCaseIntegrityFile);
				#Maybe add more info to the "done" window
				listFiles($currentCaseLocation);	
				logIt("[info] ($currentCaseName) All imaging operations complete.", 1, 1, 1);
				my $endTime = time();
				my $outputTime = $endTime - $startTime;
				logIt("[info] ($currentCaseName) Imaging process took $outputTime seconds", 1, 1, 1);
				
				my $message = $mw->MsgBox(-title => "Info", -type => "ok", -icon => "info", -message => "\tDone!\nImaging process took $outputTime seconds\n");
				$message->Show;
				#Return the vm selection window to what it was origionally in case user wants to image more VMs
				findVMs();
			}
			else
			{}
		}
	}
}

#Step 4: DD target VMs, expects the absolute path to the vm file on ESXi server
sub ddTargetFile
{
	#!!check to see if ddimages directory exists!! figure out later
	my $absolutePathFileToDD = $_[0];
	#This was a much easier solution to determining where to dd the file to
	my $ddDestination = $absolutePathFileToDD . ".dd";

	#Took out datastore1 b/c with esxi4 does not have a datastore1, this may have to be changed depending on how it works with a NAS involved
	#Instead, place the dd image file in the same directory as the orig. Could be changed
	#to "find" the storage directory and make a directory by splitting and poping the 
	#absolute path apart but this should work for now 
	
	#determine file size of file we are about to acquire
	my $fileSize = $ssh->capture("ls -lah $absolutePathFileToDD");
	$fileSize = returnFileSize($fileSize);
	my $subWindow = $mw->Toplevel;
	$subWindow->title("(Step 1/5) Calculating *MD5* and SHA1 Hashes");
	
	########debugging window position  
	my $mwx = $mw->x;
	my $mwy = $mw->y;
	my $mwHeight = $mw->height;
	my $mwWidth = $mw->width;
	my $swHeight = $subWindow->height;
	my $swWidth = $subWindow->width;
	###########debugging window position  
	
	#Adjusts the sub window to appear in the middle of the main window
	my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
	my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
	$subWindow->geometry("+$xpos+$ypos");

	#Tells the user what is happening b/c they will not have control until they get to the SFTP step
	$subWindow->Label(-text => "File: $absolutePathFileToDD\nSize: $fileSize\nCalculating *MD5* hash for $absolutePathFileToDD...\nThis may take some time depending on the file size, please be patient\n")->pack;
	$mw->update;

	sleep(1);
	
	my $startTime = time();
	my $md5 = calculateMD5HashOnESX($absolutePathFileToDD);
	my $endTime = time();
	my $outputTime = $endTime - $startTime;
	chomp ($outputTime);
	$subWindow->Label(-text => "MD5 calculation took: $outputTime seconds\n")->pack;
	logIt("[info] ($currentCaseName) MD5 calcualtion of file $absolutePathFileToDD took $outputTime seconds", 1, 1, 1);
	
	#Try and give some idea when program is calculating each hash
	$subWindow->title("(Step 1/5) Calculating MD5 and *SHA1* Hashes");
	$subWindow->Label(-text => "File: $absolutePathFileToDD\nSize: $fileSize\nCalculating *SHA1* hash for $absolutePathFileToDD...\nThis may take some time depending on the file size, please be patient\n")->pack;
	$mw->update;
	sleep(2);
	
	$startTime = time();
	my $sha1 = calculateSHA1HashOnESX($absolutePathFileToDD);
	$endTime = time();
	$outputTime = $endTime - $startTime;
	chomp ($outputTime);
	$subWindow->Label(-text => "SHA1 calculation took: $outputTime seconds\n")->pack;
	logIt("[info] ($currentCaseName) SHA1 calcualtion of file $absolutePathFileToDD took $outputTime seconds", 1, 1, 1);
	
	#Done telling the user some info, destroy the sub window b/c we are about to create a new one with new info
	$subWindow->destroy();

	logIt("[info] ($currentCaseName) Hashes of $absolutePathFileToDD Before DD:\n \tMD5: $md5\n \tSHA1: $sha1", 1, 1, 1);
	$processingHashRef->{getLoggingTime() . " Before DD on remote server MD5"} = $md5;
	$processingHashRef->{getLoggingTime() . " Before DD on remote server SHA1"} = $sha1;
	$mw->update;
	sleep(1);

	$subWindow = $mw->Toplevel;
	$subWindow->title("(Step 2/5) Creating bit level copy with DD");
	
	#Dont need to recalculate window position again b/c the main window should not have been moved. Just using values calculated from above
	$subWindow->geometry("+$xpos+$ypos");
	
	$subWindow->Label(-text => "File: $absolutePathFileToDD\nSize: $fileSize\nCreating a copy of $absolutePathFileToDD with DD...\nThis may take some time depending on thefile size, please be patient\n")->pack;
	$mw->update;
	
	logIt("[info] ($currentCaseName) Begining DD of file: $absolutePathFileToDD Destination: $ddDestination", 1, 1, 1);

	sleep(5);
	
	$startTime = time();
	my $stdout = $ssh->capture("dd if=$absolutePathFileToDD of=$ddDestination bs=1M");
	$endTime = time();
	$outputTime = $endTime - $startTime;
	chomp ($outputTime);
	$subWindow->Label(-text => "DD took: $outputTime seconds\n")->pack;
	logIt("[info] ($currentCaseName) DD copy of file $absolutePathFileToDD took $outputTime seconds", 1, 1, 1);
	
	sleep(5);
	
	$subWindow->destroy();
	$mw->update;
	logIt("[info] ($currentCaseName) DD of file: $absolutePathFileToDD to Destination: $ddDestination Done.", 1, 1, 1);
	
	sleep(1);
	$subWindow = $mw->Toplevel;
	$subWindow->title("(Step 3/5) Calculating *MD5* and SHA1 hashes after DD");
	
	#Dont need to recalculate window position again b/c the main window should not have been moved. Just using values calculated from above
	$subWindow->geometry("+$xpos+$ypos");
	$fileSize = $ssh->capture("ls -lah $ddDestination");
	$fileSize = returnFileSize($fileSize);
	
	$subWindow->Label(-text => "File: $ddDestination\nSize: $fileSize\nCalculating *MD5* hash for $ddDestination...\nThis may take some time depending on the file size, please be patient\n")->pack;
	$mw->update;
	
	my $pathToHash = $ddDestination;
	$startTime = time();
	my $md5Check = calculateMD5HashOnESX($pathToHash);
	$endTime = time();
	$outputTime = $endTime - $startTime;
	chomp ($outputTime);
	$subWindow->Label(-text => "MD5 calculation took: $outputTime seconds\n")->pack;
	logIt("[info] ($currentCaseName) MD5 calcualtion of file $pathToHash took $outputTime seconds", 1, 1, 1);
	
	#Try and give some idea when program is calculating each hash
	$subWindow->title("(Step 3/5) Calculating MD5 and *SHA1* hashes after DD");
	$subWindow->Label(-text => "File: $ddDestination\nSize: $fileSize\nCalculating *SHA1* hash for $ddDestination...\nThis may take some time depending on the file size, please be patient\n")->pack;
	$mw->update;
	sleep(2);
	
	$startTime = time();
	my $sha1Check = calculateSHA1HashOnESX($pathToHash);
	$endTime = time();
	$outputTime = $endTime - $startTime;
	chomp ($outputTime);
	$subWindow->Label(-text => "SHA1 calculation took: $outputTime seconds\n")->pack;
	logIt("[info] ($currentCaseName) SHA1 calcualtion of file $pathToHash took $outputTime seconds", 1, 1, 1);
	
	$preMD5 = $md5Check;
	$preSHA1 = $sha1Check;
	logIt("[info] ($currentCaseName) Hashes of $pathToHash After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check", 1, 1, 1);
	$processingHashRef->{getLoggingTime() . " After DD on remote server MD5"} = $md5Check;
	$processingHashRef->{getLoggingTime() . " After DD on remote server SHA1"} = $sha1Check;

	#Done telling the user some info, destroy the sub window b/c we are about to create a new one with new info
	$subWindow->destroy();
	
	$mw->update;
	sleep(1);
	return $pathToHash;
}

#Step 5: SFTP target VMs, expects absolute path to target dd file
sub sftpTargetFileImage
{
	my $fileToSFTP = $_[0];

	my %args; #= ( user => 'root',password => 'netsys01');
	my $serverIP = $ESXip->get;
	my $user = $username->get;
	my $password = $password->get;
	my $host= '192.168.100.141';
	
	#label program will goto if a file hash is different after SFTP and the user wants to try and reacquire the file
	REACQUIRE:
	
	logIt("[info] ($currentCaseName) SFTP connecting to ESXi server $serverIP", 1, 1, 1);
	$mw->update;
	my $sftp = Net::SFTP::Foreign->new($serverIP,  user => $user, password => $password);
	$sftp->die_on_error("SSH Connection Failed");
	logIt("[info] ($currentCaseName) Successfully connected to $serverIP", 1, 1, 1);
	
	my $getFileName2 = getFileName($fileToSFTP);
	
	#Now that we have a cases directory, the images need to be saved to that directory
	my $localDestination = $currentCaseLocation . "/" . $getFileName2;
	logIt("[info] ($currentCaseName) Transfering $fileToSFTP from ESXi server to this computer. Local Destination:$localDestination", 1, 1, 1);
	$mw->update;

	#Create progress bar to show user program is doing something
	my $percentDone = 0;
	my $subWindow = $mw->Toplevel;
	$subWindow->title("(Step 4/5) Transfering image to local computer via SFTP");
	my $startTime = time();
	$subWindow->geometry("300x30");
	
	my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
	my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
	$subWindow->geometry("+$xpos+$ypos");
	
	my $progressBar = $subWindow->ProgressBar(-width => 30, -blocks => 50, -from => 0, -to => 100, -variable => \$percentDone)->pack(-fill => 'x');
	
	$sftp->get($fileToSFTP,$localDestination, callback => sub {
		my ($sftp, $data, $offset, $size) = @_;
		#For whatever reason if the file size is 0, we avoid dividing by 0
		if ($size == 0)
		{$size = 1;}
		$percentDone = ($offset / $size) * 100;
		$subWindow->update;
	
	}); #or die "File transfer failed\n";
	$subWindow->destroy;
	#With transfer complete, destroy the progress bar window
	logIt("[info] ($currentCaseName) SFTP transfer complete.", 1, 1, 1);
	my $endTime = time();
	my $outputTime = $endTime - $startTime;
	chomp ($outputTime);
	logIt("[info] ($currentCaseName) SFTP transfer of file $fileToSFTP took $outputTime seconds", 1, 1, 1);
	sleep(2);
	
	#get the file size locally
	my $fileSize = `ls -lah $localDestination`;
	$fileSize = returnFileSize($fileSize);
	
	#Create subwindow to tell use the program is calculating hashes
	$subWindow = $mw->Toplevel;
	$subWindow->title("(Step 5/5) Calculating *MD5* and SHA1 hashes after SFTP transfer");
	#Adjusts the sub window to appear in the middle of the main window
	$xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
	$ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
	$subWindow->geometry("+$xpos+$ypos");
	
	#Tells the user what is happening b/c they will not have control while hashes are being calculated
	$subWindow->Label(-text => "File: $localDestination\nSize: $fileSize\nCalculating *MD5* hash for $localDestination...\nThis may take some time depending on the file size, please be patient\n")->pack;
	$mw->update;
	
	logIt("[info] ($currentCaseName) Working on $localDestination", 1, 1, 1);
	
	$startTime = time();
	my $md5Check = calculateMD5HashLocal($localDestination);
	$endTime = time();
	$outputTime = $endTime - $startTime;
	chomp ($outputTime);
	$subWindow->Label(-text => "MD5 calculation took: $outputTime seconds\n")->pack;
	logIt("[info] ($currentCaseName) MD5 calcualtion of file $localDestination took $outputTime seconds", 1, 1, 1);
	
	#Try and give some idea when program is calculating each hash
	$subWindow->title("(Step 5/5) Calculating MD5 and *SHA1* hashes after SFTP transfer");
	$subWindow->Label(-text => "File: $localDestination\nSize: $fileSize\nCalculating *SHA1* hash for $localDestination...\nThis may take some time depending on the file size, please be patient\n")->pack;
	$mw->update;
	sleep(2);
	
	$startTime = time();
	my $sha1Check = calculateSHA1HashLocal($localDestination);
	$endTime = time();
	$outputTime = $endTime - $startTime;
	chomp ($outputTime);
	$subWindow->Label(-text => "SHA1 calculation took: $outputTime seconds\n")->pack;
	logIt("[info] ($currentCaseName) SHA1 calcualtion of file $localDestination took $outputTime seconds", 1, 1, 1);
	
	logIt("[info] ($currentCaseName) Hashes of $localDestination After SFTP Transfer:\n \tMD5: $md5Check\n \tSHA1: $sha1Check", 1, 1, 1);
	$processingHashRef->{getLoggingTime() . " After SFTP transfer MD5"} = $md5Check;
	$processingHashRef->{getLoggingTime() . " After SFTP transfer SHA1"} = $sha1Check;
	
	$subWindow->destroy();
	
	if ($preMD5 ne $md5Check || $preSHA1 ne $sha1Check)
	{
		logIt("[error] ($currentCaseName) Hashes do not match for file $localDestination. Pre MD5:$preMD5 Post MD5:$md5Check Pre SHA1:$preSHA1 Post SHA1:$sha1Check", 1, 1, 1);
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "Hashes do not match for file $localDestination. Pre MD5:$preMD5 Post MD5:$md5Check Pre SHA1:$preSHA1 Post SHA1:$sha1Check\n");
		$message->Show;
		my $messageBoxAnswer = $mw->messageBox(-title => "Re-acquire file?", -type => "YesNo", -icon => "question", -message => "Would you like to try and re-acquire file: $localDestination?", -default => "yes");
		if ($messageBoxAnswer eq 'yes')
		{
			logIt("[info] ($currentCaseName) Attempting to re-acquire file: $localDestination.", 1, 1, 1);
			goto REACQUIRE;
		}
	}
	sleep(1);
	
	cleanup($fileToSFTP);
}

#Checks the integrity of all the files currently in the given case integrity file, or checks a subset of files if an array refrence containing
#the file names to be checked is passed to the sub
sub checkImageIntegrity
{
	my $arrayOfSpecificFiles = $_[0];
	
	if($currentCaseName =~ m/No Case Opened Yet/)
	{
		logIt("[error] (main) A case has not yet been opened. Open a case before verifying image integrity.", 1, 0, 1);
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "A case has not yet been opened. Open a case before verifying image integrity.\n");
		$message->Show;
	}
	else
	{
		logIt("[info] ($currentCaseName) Verifying integrity of image files...", 1, 1, 1);
		if (defined $arrayOfSpecificFiles && $arrayOfSpecificFiles ne '')
		{
			foreach (@$arrayOfSpecificFiles)
			{	
				my $absolutePath = $currentCaseLocation . "/" . $_;
				logIt("[info] ($currentCaseName) Checking integrity of $absolutePath", 1, 1, 1);
				
				#determine file size of file
				my $fileSize = `ls -lah $absolutePath`;
				$fileSize = returnFileSize($fileSize);
				my $subWindow = $mw->Toplevel;
				$subWindow->title("Calculating *MD5* and SHA1 Hashes for Image Integrity Verification");
				
				########debugging window position  
				my $mwx = $mw->x;
				my $mwy = $mw->y;
				my $mwHeight = $mw->height;
				my $mwWidth = $mw->width;
				my $swHeight = $subWindow->height;
				my $swWidth = $subWindow->width;

				#Adjusts the sub window to appear in the middle of the main window
				my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
				my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
				$subWindow->geometry("+$xpos+$ypos");
				
				#Tells the user what is happening b/c they will not have control while files are being hashed
				$subWindow->Label(-text => "File: $absolutePath\nSize: $fileSize\nCalculating *MD5* hash for $absolutePath...\nThis may take some time depending on the file size, please be patient\n")->pack;
				$mw->update;

				sleep(1);
				
				my $startTime = time();
				my $currentMD5Hash = calculateMD5HashLocal($absolutePath);
				my $endTime = time();
				my $outputTime = $endTime - $startTime;
				chomp ($outputTime);
				$subWindow->Label(-text => "MD5 calculation took: $outputTime seconds\n")->pack;
				logIt("[info] ($currentCaseName) MD5 calcualtion of file $absolutePath took $outputTime seconds", 1, 1, 1);
				
				#Try and give some idea when program is calculating each hash
				$subWindow->title("Calculating MD5 and *SHA1* Hashes for Image Integrity Verification");
				$subWindow->Label(-text => "File: $absolutePath\nSize: $fileSize\nCalculating *SHA1* hash for $absolutePath...\nThis may take some time depending on the file size, please be patient\n")->pack;
				$mw->update;
				sleep(2);
				
				$startTime = time();
				my $currentSHA1Hash = calculateSHA1HashLocal($absolutePath);
				$endTime = time();
				$outputTime = $endTime - $startTime;
				chomp ($outputTime);
				$subWindow->Label(-text => "SHA1 calculation took: $outputTime seconds\n")->pack;
				logIt("[info] ($currentCaseName) SHA1 calcualtion of file $absolutePath took $outputTime seconds", 1, 1, 1);
				
				#Done telling the user some info, destroy the sub window b/c we are about to create a new one with new info
				$subWindow->destroy();

				logIt("[info] ($currentCaseName) Hashes of $absolutePath:\n \tMD5: $currentMD5Hash\n \tSHA1: $currentSHA1Hash", 1, 1, 1);
				my $message = getLoggingTime() . " Verifying Image Integrity MD5";
				$hashRef->{$_}->{$message} = $currentMD5Hash;
				$message = getLoggingTime() . " Verifying Image Integrity SHA1";
				$hashRef->{$_}->{$message} = $currentSHA1Hash;
				
				my %derefHash = %$hashRef;
				my $savedHashRef = $derefHash{$_};
				my %HoH = %$savedHashRef;
				my $isDifferent;
				foreach my $key (keys %HoH)
				{
					if ($key =~ m/.*MD5.*/)
					{
						my $value = compareHashes($currentMD5Hash, $HoH{$key});
						$isDifferent = $isDifferent + $value;
					}
					elsif ($key =~ m/.*SHA1.*/)
					{
						my $value = compareHashes($currentSHA1Hash, $HoH{$key});
						$isDifferent = $isDifferent + $value;
					}
					else {}
				}
				if ($isDifferent > 0 )
				{
					logIt("[warning] ($currentCaseName) Image corrupt! Hashes are different for file: $absolutePath", 1, 1, 1);
					my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "Image corrupt! Current hash values are different from the hashes in the saved digest file for file: $absolutePath\nIt is strongly suggested you re-acquire this file!\n");
					$message->Show;
				}
				else
				{
					logIt("[info] ($currentCaseName) No integrity problems found for file: $absolutePath", 1, 1, 1);
				}
			}
		}		else
		{
			my %digest = %$hashRef;
			foreach my $key (keys %digest)
			{
				if ($key =~ m/.*\.dd/)
				{	
					my $absolutePath = $currentCaseLocation . "/" . $key;
					logIt("[info] ($currentCaseName) Checking integrity of $absolutePath", 1, 1, 1);
				
					#determine file size of file 
					my $fileSize = `ls -lah $absolutePath`;
					$fileSize = returnFileSize($fileSize);
					my $subWindow = $mw->Toplevel;
					$subWindow->title("Calculating MD5 and SHA1 Hashes for Image Integrity Verification");
					
					########debugging window position  
					my $mwx = $mw->x;
					my $mwy = $mw->y;
					my $mwHeight = $mw->height;
					my $mwWidth = $mw->width;
					my $swHeight = $subWindow->height;
					my $swWidth = $subWindow->width;

					#Adjusts the sub window to appear in the middle of the main window
					my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
					my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
					$subWindow->geometry("+$xpos+$ypos");
					
					#Tells the user what is happening b/c they will not have control while files are being hashed
					$subWindow->Label(-text => "File: $absolutePath\nSize: $fileSize\nCalculating MD5 and SHA1 hashes for $absolutePath...\nThis may take some time depending on the file size, please be patient\n")->pack;
					$mw->update;

					sleep(1);
					
					my $currentMD5Hash = calculateMD5HashLocal($absolutePath);
					my $currentSHA1Hash = calculateSHA1HashLocal($absolutePath);
					
					#Done telling the user some info, destroy the sub window b/c we are about to create a new one with new info
					$subWindow->destroy();

					logIt("[info] ($currentCaseName) Hashes of $absolutePath:\n \tMD5: $currentMD5Hash\n \tSHA1: $currentSHA1Hash", 1, 1, 1);
					my $message = getLoggingTime() . " Verifying Image Integrity MD5";
					$hashRef->{$key}->{$message} = $currentMD5Hash;
					$message = getLoggingTime() . " Verifying Image Integrity SHA1";
					$hashRef->{$key}->{$message} = $currentSHA1Hash;
					
					my $ref = $digest{$key};
					my %HoH = %$ref;
					my $isDifferent;
					foreach my $otherKey (keys %HoH)
					{
						if ($otherKey =~ m/.*MD5.*/)
						{
							my $value = compareHashes($currentMD5Hash, $HoH{$otherKey});
							$isDifferent = $isDifferent + $value;
						}
						elsif ($otherKey =~ m/.*SHA1.*/)
						{
							my $value = compareHashes($currentSHA1Hash, $HoH{$otherKey});
							$isDifferent = $isDifferent + $value;
						}
						else {}
					}
					if ($isDifferent > 0 )
					{
						logIt("[warning] ($currentCaseName) Image corrupt! Hashes are different for file: $absolutePath", 1, 1, 1);
						my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "Image corrupt! Current hash values are different from the hashes in the saved digest file for file: $absolutePath\nIt is strongly suggested you re-acquire this file!\n");
						$message->Show;
					}
					else
					{
						logIt("[info] ($currentCaseName) No integrity problems found for file: $absolutePath", 1, 1, 1);
					}
				}
				else {}
			}
				my $caseIntegrityFileLocation = $currentCaseLocation . "/" . $currentCaseName . ".integrity";
				open ($currentCaseIntegrityFile, ">$caseIntegrityFileLocation");
				logIt("[info] ($currentCaseName) Writing to integrity file", 1, 1, 1);
				print $currentCaseIntegrityFile Data::Dumper->Dump([$hashRef], [qw/digest/]);
				close($currentCaseIntegrityFile);
		}
		logIt("[info] ($currentCaseName) Done performing image integrity verification", 1, 1, 1);
	}
}

#Checks if the virtual machine use wants to image is currently powered on/running. Ideally you want to freeze the VM so nothing changes as you acquire the VM
#Expects to be passed the absolute path to the VM in questions .vmx file
sub checkIfVMRunning
{
	my $vmxPath = $_[0];
	my $stdout = $ssh->capture('/sbin/vmdumper -l');
	my @lines = split(/\n/, $stdout);
	
	foreach(@lines)
	{
		my @lineParts = split(/\s+/, $_);
		foreach (@lineParts)
		{
			if ($_ =~ m/$vmxPath/)
			{
				return 1;
				last;
			}
		}
	}
	return 0;
}

#suspends a given VM, expects absolute path to vm's .vmx path
sub suspendVM
{
	my $vmxPath = $_[0];
	logIt("[info] ($currentCaseName) Working on $vmxPath ...", 1,1,1);
	my $stdout = $ssh->capture('/sbin/vmdumper -l');
	my @lines = split(/\n/, $stdout);
	foreach(@lines)
	{
		my @lineParts = split(/\s+/, $_);
		foreach (@lineParts)
		{
			if ($_ =~ m/$vmxPath/)
			{
				my $VMwid = $lineParts[0];
				$VMwid =~ s/=/ /g;
				my @VMwidSplit = split(/\s+/,$VMwid);
				my $stdout = $ssh->capture("/sbin/vmdumper $VMwidSplit[1] suspend_vm") or warn "remote command failed " . $ssh->error;
				my $lineToPrint = getLoggingTime() . " [info] ($currentCaseName) Suspending VM...";
				print PROGRAMLOGFILE $lineToPrint;
				print $currentCaseLog $lineToPrint;
				print DEBUGLOGFILE $lineToPrint;
				$consoleLog->insert('end', $lineToPrint);
				$consoleLog->see('end');
						
				my $subWindow = $mw->Toplevel;
				$subWindow->title("Suspending VM: $vmxPath");
				#Adjusts the sub window to appear in the middle of the main window
				my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
				my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
				$subWindow->geometry("+$xpos+$ypos");
				
				my $size = 24;
				my $font = $subWindow->fontCreate(-size => $size);
				my $text = "Suspending VM...";
				my $suspendVMLabel = $subWindow->Label(-text => $text,-width => 20, -font => $font)->pack(-fill => 'both');
				$mw->update;
				my $vmStillRunning = 1;
				while ($vmStillRunning == 1)
				{
					$vmStillRunning = checkIfVMRunning($vmxPath);
					
					print PROGRAMLOGFILE ".";
					print $currentCaseLog ".";
					print DEBUGLOGFILE ".";
					print ".";
					
					$text = $text . ".";
					$suspendVMLabel->configure(-text => $text);
					$mw->update;
					sleep(1);
				}
				print PROGRAMLOGFILE "Done!\n";
				print $currentCaseLog "Done!\n";
				print DEBUGLOGFILE "Done!\n";
				print "Done!\n";
				logIt("[info] $vmxPath suspended.", 1,1,1);
				$subWindow->destroy();
				return 0;
			}
		}
	}
	return 0;
}

#starts a given VM, expects absolute path to .vmx file in question
sub startVM
{
	my $vmToRestart = $_[0];
	logIt("[info] ($currentCaseName) Going to try and restart this VM: $vmToRestart", 1, 1, 1);
	my $vmxFile = getFileName($vmToRestart);
	my $stdout = $ssh->capture("vim-cmd vmsvc/getallvms |grep $vmxFile");
	my @lines = split(/\n/, $stdout);
	my $count = @lines;
	#only one .vmx file was matched so we dont need to worry about starting the wrong VM
	if ($count == 1)
	{
		my @parts = split(/\s+/, $lines[0]);
		my $stdout = $ssh->capture("vim-cmd vmsvc/power.on $parts[0]") or warn "remote command failed " . $ssh->error;
		my $lineToPrint = getLoggingTime() . " [info] ($currentCaseName) Starting VM...";
		print PROGRAMLOGFILE $lineToPrint;
		print $currentCaseLog $lineToPrint;
		$consoleLog->insert('end', $lineToPrint);
		$consoleLog->see('end');
		
		my $subWindow = $mw->Toplevel;
		$subWindow->title("Starting VM: $vmToRestart");
		#Adjusts the sub window to appear in the middle of the main window
		my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
		my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
		$subWindow->geometry("+$xpos+$ypos");
		
		my $size = 24;
		my $font = $subWindow->fontCreate(-size => $size);
		my $text = "Starting VM...";
		my $startVMLabel = $subWindow->Label(-text => $text,-width => 20, -font => $font)->pack(-fill => 'both');
		$mw->update;
		my $vmStillRunning = 0;
		while ($vmStillRunning == 0)
		{
			$vmStillRunning = checkIfVMRunning($vmToRestart);
			
			print PROGRAMLOGFILE ".";
			print $currentCaseLog ".";
			print ".";
			$text = $text . ".";
			$startVMLabel->configure(-text => $text);
			$mw->update;
			sleep(1);
		}
		print PROGRAMLOGFILE "Done!\n";
		print $currentCaseLog "Done!\n";
		print "Done!\n";
		logIt("[info] ($currentCaseName) $vmToRestart restarted.", 1,1,1);
		$subWindow->destroy();
		return 0;
	}
}

#because the dd images are being stored into the same directory the file exists in on the ESXi server, we want to clean up these files when we are done
#expects the absolute path of the file to delete on the esxi server and will also check that the file has a .dd extension so the wrong file does not get 
#deleted which would be very bad
#ideally dd would "store" copies somewhere else but this is how I have it setup for now
sub cleanup
{
	logIt("[info] ($currentCaseName) Cleaning up.", 1, 1, 1);
	my $fileToDel = $_[0];
	if ($fileToDel =~ m/.+\.dd$/)
	{
		logIt("[info] ($currentCaseName) Going to delete remote file $fileToDel.", 1, 1, 1);
		my $stdout = $ssh->capture("rm -f $fileToDel");
		logIt("[info] ($currentCaseName) Done deleting remote file $fileToDel $stdout", 1, 1, 1);
		$consoleLog->see('end');
	}
	else
	{
		logIt("[info] ($currentCaseName) File ($fileToDel) does not have a .dd extension, will not delete this file.", 1, 1, 1);
		$consoleLog->see('end');
	}
}

#Allows user to edit settings of program. Location where cases, log files, etc are stored. Maybe additional configurable options later
#Will be run from the Tools->Setttings menu bar or run from the readConfigFile sub if no configuration file is found
sub editSettings
{
	if (-e $configFileLocation)
	{
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
				logIt("[error] (main) Misformated Config file, dont know what $_ is", 1,0,1);
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
	#Adjusts the sub window to appear in the middle of the main window
	my $xpos = int((($mw->width - $settingsWindow->width) / 2) + $mw->x);
	my $ypos = int((($mw->height - $settingsWindow->height) / 2) + $mw->y);
	$settingsWindow->geometry("+$xpos+$ypos");
	
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
		logIt("[info] (main) Config File Saved", 1,0,1);
	})->pack(-side => "left");	
	my $cancelButton = $settingsWindowBottomFrame->Button(-text => "Exit", -command => [$settingsWindow => 'destroy'])->pack(-side => "left");
}

#sub to create a new case, esentially all it does is create a directory under whatever $ESXiCasesDir is and updates the label in $mw
sub createNewCase
{
	my $createCaseWindow = $mw->Toplevel;
	$createCaseWindow->title("Create New Case");
	my $xpos = int((($mw->width - $createCaseWindow->width) / 2) + $mw->x);
	my $ypos = int((($mw->height - $createCaseWindow->height) / 2) + $mw->y);
	$createCaseWindow->geometry("+$xpos+$ypos");
	
	#label for configuration file location
	$createCaseWindow->Label(-text => "Case Directory Location: $ESXiCasesDir")->grid(-row => 0, -column => 0);
	
	#label for working directory location
	$createCaseWindow->Label(-text => "Case Name: ")->grid(-row => 1, -column => 0, -sticky => "e");
	#entry for working directory location
	my $newCaseName = $createCaseWindow->Entry( -width => 40)->grid(-row => 1, -column => 1);
	
	my $createCaseWindowBottomFrame = $createCaseWindow->Frame;
	$createCaseWindowBottomFrame->grid(-row => 2, -column => 0, -columnspan => 2);
	$createCaseWindowBottomFrame->Button(-text => "Create", -command => sub {
			$currentCaseName = $newCaseName->get;
			#Dont want case names to have any spaces
			$currentCaseName =~ s/ //g;
			$mw->update;
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
				my $caseLogFileLocation = $currentCaseLocation . "/$currentCaseName.log";
				open ($currentCaseLog, ">>$caseLogFileLocation");
				logIt("[info] ($currentCaseName) Created new case: $currentCaseName Location: $currentCaseLocation", 1, 1, 1);
				logIt("[info] ($currentCaseName) Opened case log file $caseLogFileLocation", 1, 1, 1);
				my $caseIntegrityFileLocation = $currentCaseLocation . "/" . $currentCaseName . ".integrity";
				open ($currentCaseIntegrityFile, ">>$caseIntegrityFileLocation");
				logIt("[info] ($currentCaseName) Opened case integrity file $caseIntegrityFileLocation", 1, 1, 1);
				#delete whatever is currently in the hash ref 
				$hashRef = {};
				for (keys %$hashRef)
				{
					delete $hashRef->{$_};
				}
				#Adds the case name and case location to our hash
				$hashRef->{"casename"} = $currentCaseName;
				$hashRef->{"caselocation"} = $currentCaseLocation;
				print $currentCaseIntegrityFile Data::Dumper->Dump([$hashRef], [qw/digest/]);
				$caseLabel->configure(-text => "Current Case: $currentCaseName Location: $currentCaseLocation");
				$dirTree->chdir($currentCaseLocation);
				listFiles($currentCaseLocation);
				$mw->update;
				#Done telling the user some info, destroy the sub window b/c we are about to create a new one with new info
				$createCaseWindow->destroy();
			}
		
	})->pack(-side => "left");	
	my $cancelButton = $createCaseWindowBottomFrame->Button(-text => "Exit", -command => [$createCaseWindow => 'destroy'])->pack(-side => "left");
}

#Allows user to open existing case, brings up a popup direcoty navigation window to allow the user to select the case they want to open
sub openExistingCase
{
	##More work to be done here
	my $directory = $mw->chooseDirectory(-initialdir=>$ESXiCasesDir, -title => "Select a case to open");
	if ($directory ne '')
	{
		$currentCaseLocation = $directory;
		$currentCaseName = getFileName($currentCaseLocation);
		my $caseLogFileLocation = $currentCaseLocation . "/$currentCaseName.log";
		open ($currentCaseLog, ">>$caseLogFileLocation");
		logIt("[info] ($currentCaseName) Opened an existing case: $currentCaseName Location: $currentCaseLocation", 1, 1, 1);
		logIt("[info] ($currentCaseName) Opened log file: $caseLogFileLocation For case: $currentCaseName", 1, 1, 1);
		my $caseIntegrityFileLocation = $currentCaseLocation . "/" . $currentCaseName . ".integrity";
		$hashRef = {};
		for (keys %$hashRef)
		{
			delete $hashRef->{$_};
		}
		open (CASEINTEGRITY, "< $caseIntegrityFileLocation");
		my @lines = <CASEINTEGRITY>;
		close(CASEINTEGRITY);
						
		my $digest = "";
		my $perlsrc = join(" ", @lines);
		eval $perlsrc;
		$hashRef = $digest;
		logIt("[info] ($currentCaseName) Opened case integrity file $caseIntegrityFileLocation", 1, 1, 1);
		$caseLabel->configure(-text => "Current Case: $currentCaseName Location: $currentCaseLocation");
		$dirTree->chdir($currentCaseLocation);
		listFiles($currentCaseLocation);
		$mw->update;
	}
	else {#use must have pressed cancel when selecting a directory
	}
}

#given a directory path, will list all the files in given directory into the $fileList listbox next to the dirTree
sub listFiles
{
	my $path = $_[0];
	#deletes all the entries in the listbox before populating it
	$fileList->delete(0,'end');
	
	opendir (DIR, $path);
	$fileList->insert('end', $path);
	$fileList->insert('end', "----------------------------------------------------------");
	while (my $file = readdir(DIR))
	{
		next if $file =~ /^[.]/;
		if (-f $file)
		{
			$fileList->insert('end', "its a file\n");
		}
		else
		{$fileList->insert('end', $file);}
	}
	closedir(DIR);
}

#Runs a selected file from the file listbox through the strings command and shows the output in a new window, expects a refrence to the $fileList listbox
sub runThroughStrings
{
	my $fileListBoxRef = $_[0];
	#de-refrence
	my $fileListBoxDeref = $$fileListBoxRef;
	#curselection (cusor selection) returns an array in case multiple items are selected however, I only allow one item to be selected with this implementation -selectionmode?
	my @cursorSelection = $fileListBoxDeref->curselection;
	#The current directory being listed is always shown at the top of the fileList listbox, this is element 0 of the listbox
	my $currentDirectory = $fileListBoxDeref->get(0);
	my $targetFile = $fileListBoxDeref->get(0) . "/" . $fileListBoxDeref->get($cursorSelection[0]);
	
	if (-f $targetFile)
	{
		my $subWindow = $mw->Toplevel;
		$subWindow->title("Strings Output of File: $targetFile");
		my $stringsOutputWindow = $subWindow->Scrolled('Text')->pack(-fill => 'both');
		my $stringsFindLabel = $subWindow->Entry(-width => 20)->pack();
		$subWindow->Button(-text => "Find", -command => sub {
			my $searchString = $stringsFindLabel->get;
			my $stdout = `strings $targetFile | grep $searchString`;
			my $findStringsSubWindow = $mw->Toplevel;
			my $stringsFindOutputWindow = $findStringsSubWindow->Scrolled('Text')->pack(-fill => 'both');
			$findStringsSubWindow->Button(-text => "Close Window", -command => [$findStringsSubWindow => 'destroy'])->pack();
			$stringsFindOutputWindow->insert('end', $stdout);
		})->pack();
		$subWindow->Button(-text => "Close Window", -command => [$subWindow => 'destroy'])->pack();
		my $stdout = `strings $targetFile`;
		$stringsOutputWindow->insert('end', $stdout);
	}
	#To prevent anything from happening if the user selects the divider line ------------------------ or the current directory path located at the top of the listbox
	elsif($cursorSelection[0] == 1 || $cursorSelection[0] == 0)
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "No valid file selected. Please select a file.\n");
		$message->Show;
	}
	#Otherwise they probably selected a directory 
	else
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "$targetFile is a directory. Please select a file.\n");
		$message->Show;
	}
}

#Runs a selected file from the file listbox through the strings command and shows the output in a new window, expects a refrence to the $fileList listbox
sub runThroughHexdump
{
	my $fileListBoxRef = $_[0];
	#de-refrence
	my $fileListBoxDeref = $$fileListBoxRef;
	#curselection (cusor selection) returns an array in case multiple items are selected however, I only allow one item to be selected with this implementation -selectionmode?
	my @cursorSelection = $fileListBoxDeref->curselection;	
	#The current directory being listed is always shown at the top of the fileList listbox, this is element 0 of the listbox
	my $currentDirectory = $fileListBoxDeref->get(0);
	my $targetFile = $fileListBoxDeref->get(0) . "/" . $fileListBoxDeref->get($cursorSelection[0]);
	
	if (-f $targetFile)
	{
		my $subWindow = $mw->Toplevel;
		$subWindow->title("Hexdump Output of File: $targetFile");
		my $stringsOutputWindow = $subWindow->Scrolled('Text')->pack(-fill => 'both');
		$subWindow->Button(-text => "Close Window", -command => [$subWindow => 'destroy'])->pack();
		my $stdout = `hexdump -C $targetFile`;
		$stringsOutputWindow->insert('end', $stdout);
	}
	#To prevent anything from happening if the user selects the divider line ------------------------ or the current directory path located at the top of the listbox
	elsif($cursorSelection[0] == 1 || $cursorSelection[0] == 0)
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "No valid file selected. Please select a file.\n");
		$message->Show;
	}
	#Otherwise they probably selected a directory 
	else
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "$targetFile is a directory. Please select a file.\n");
		$message->Show;
	}
}

#Displays a window with information about one of the image files that has been acquired 
#Such as the date acquired, the hashes, file size
sub viewFileInfo
{
	my $fileListBoxRef = $_[0];
	#de-refrence
	my $fileListBoxDeref = $$fileListBoxRef;
	#curselection (cusor selection) returns an array in case multiple items are selected however, I only allow one item to be selected with this implementation -selectionmode?
	my @cursorSelection = $fileListBoxDeref->curselection;	
	#The current directory being listed is always shown at the top of the fileList listbox, this is element 0 of the listbox
	my $currentDirectory = $fileListBoxDeref->get(0);
	my $targetFile = $fileListBoxDeref->get(0) . "/" . $fileListBoxDeref->get($cursorSelection[0]);
	
	if (-f $targetFile && $targetFile =~ m/.*\.dd/)
	{
		my %digest = %$hashRef;
		foreach my $key (keys %digest)
		{
			if ($key eq $fileListBoxDeref->get($cursorSelection[0]))
			{	
				my $subWindow = $mw->Toplevel;
				$subWindow->title("View Information of File: $targetFile");
				my $fileInfoOutputWindow = $subWindow->Scrolled('Text')->pack(-fill => 'both');		
				$subWindow->Button(-text => "Close Window", -command => [$subWindow => 'destroy'])->pack();
				$fileInfoOutputWindow->insert('end', "File: " . $fileListBoxDeref->get($cursorSelection[0]) . "\n");
				my $filesize = `ls -lah $targetFile`;
				$fileInfoOutputWindow->insert('end', "Size: " . returnFileSize($filesize) . "\n");
				$fileInfoOutputWindow->insert('end', "Hash History:\n");
				
				my $absolutePath = $currentCaseLocation . "/" . $key;
				my $ref = $digest{$key};
				my %HoH = %$ref;
				foreach my $otherKey (sort keys %HoH)
				{
					$fileInfoOutputWindow->insert('end', "\t$otherKey $HoH{$otherKey}\n");
				}
			}
		}
	}
	elsif($targetFile =~ m/.*\.log/ || $targetFile =~ m/.*\.integrity/)
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "No information available for .log or .integrity files\n");
		$message->Show;
	}
	#To prevent anything from happening if the user selects the divider line ------------------------ or the current directory path located at the top of the listbox
	elsif($cursorSelection[0] == 1 || $cursorSelection[0] == 0)
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "No valid file selected. Please select a file.\n");
		$message->Show;
	}
	#Otherwise they probably selected a directory 
	else
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "$targetFile is a directory. Please select a file.\n");
		$message->Show;
	}
} 

#***********************************************************************************************************************************#
#******Start of Commonly Used Subs to Make Life Better******************************************************************************#
#***********************************************************************************************************************************#

#simpflies logging. Will take what you want to print as an arguement and output to $consoleLog, the main program log, and the current case log
#Expects he exact message to be printed. ex. [info] (foo) case foo was opened
#Also expects 4 values 0 or 1 to determine what to print out to (for whatever reason a message need to only be printed to one log file). Last value is
# optional if they want debug messages to be printed. This solves a problem in the begining of the program where logIt is being run but the DEBUGLOGFILE 
# handle has not been opened yet. Not a problem really but it show up with use warnings;
# Args: message programLogFile caseLogFile consoleLog debugLogFile
sub logIt
{
	my $debugLogPrint = 1;
	my $lineToPrint = $_[0];
	my $programLogPrint = $_[1];
	my $caseLogPrint = $_[2];
	my $consoleLogPrint = $_[3];
	#allows the fourth arg of the sub to be optional. By default all messages should be printed to the debug log file but it can be controlled if necessary
	if (defined $_[4])
	{
		$debugLogPrint = $_[4];
	}
	
	$lineToPrint = getLoggingTime() . " " . $lineToPrint . "\n";
	print PROGRAMLOGFILE $lineToPrint if $programLogPrint == 1;
	print $currentCaseLog $lineToPrint if $caseLogPrint == 1;
	$consoleLog->insert('end', $lineToPrint) if $consoleLogPrint == 1;
	$consoleLog->see('end') if $consoleLogPrint == 1;
	print DEBUGLOGFILE $lineToPrint if $debugLogPrint == 1;
	return $lineToPrint;
}

#Gets the current time and returns a nice timestamp for logging purposes
#http://stackoverflow.com/questions/12644322/how-to-write-the-current-timestamp-in-a-file-perl
sub getLoggingTime 
{

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $nice_timestamp = sprintf ( "%04d%02d%02d %02d:%02d:%02d",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $nice_timestamp;
}

#Given the output of ls -lah of a single file, returns the file size, *nix systems only
sub returnFileSize
{
	my $output = $_[0];
	my @split = split(/\s+/, $output);
	
	return $split[4];
}

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

#Sub is passed long absolute path of a file and returns the files parent directory
#ex. sub is passed /var/storage/foo/bar.vmx and returns /var/storage/foo/
sub getDirName
{
	my $absolutePath = $_[0];
	my @fileNameParts = split('/',$absolutePath);
	#Becasue there is a leading / in the path we need to get rid of the first element in the array becasue it is nothing. print "--$_--" = ----
	shift @fileNameParts;
	pop @fileNameParts;
	
	my $parentDirPath;
	foreach(@fileNameParts)
	{
		$parentDirPath = $parentDirPath . "/" . $_;
	}
	$parentDirPath = $parentDirPath . "/";
	return $parentDirPath;
}

#Calculate MD5 hash of file about to be copied on ESX server
sub calculateMD5HashOnESX
{
	my $fileToHash = $_[0];
	
	logIt("[info] ($currentCaseName) Calculating md5 hash of file on ESXi server this may take a while be patient...", 1, 1, 1);
	my $stdout = $ssh->capture("md5sum $fileToHash");
	my @split = split (/\s+/, $stdout);
	$stdout = $split[0];
	logIt("[info] ($currentCaseName) Done calculating md5 hash of file on ESXi server.", 1, 1, 1);
	chomp $stdout;
	return $stdout;   
}

# Calculate SHA1 hash of the file about to be copied on ESX server
sub calculateSHA1HashOnESX
{
	my $fileToHash = $_[0];
	logIt("[info] ($currentCaseName) Calculating sha1 hash of file on ESXi server this may take a while be patient...", 1, 1, 1);
	my $stdout = $ssh->capture("sha1sum $fileToHash");
	my @split = split (/\s+/, $stdout);
	$stdout = $split[0];
	logIt("[info] ($currentCaseName) Done calculating sha1 hash of file on ESXi server.", 1, 1, 1);
	chomp $stdout;
	return $stdout;   
}

#Calculate MD5 hash of local file
sub calculateMD5HashLocal
{
	my $fileToHash = $_[0];
	my $operatingSystem = checkOS();

	logIt("[info] ($currentCaseName) Calculating md5 hash of local file this may take a while be patient...", 1, 1, 1);
	my $stdout;	
	$stdout = `md5sum $fileToHash` if $operatingSystem == 1;
	$stdout = `md5 $fileToHash` if $operatingSystem == 2;	
	my @split = split (/\s+/, $stdout);
	
	#[$#split] gives you the last element of an array
	$stdout = $split[0] if $operatingSystem == 1;
	$stdout = $split[$#split] if $operatingSystem == 2;
	logIt("[info] ($currentCaseName) Done calculating md5 hash of local file.", 1, 1, 1);
	chomp $stdout;
	return $stdout;   
}

# Calculate SHA1 hash of local file
sub calculateSHA1HashLocal
{
	my $fileToHash = $_[0];
	my $operatingSystem = checkOS();
	
	logIt("[info] ($currentCaseName) Calculating sha1 hash of local file this may take a while be patient...", 1, 1, 1);
	my $stdout;
	$stdout = `sha1sum $fileToHash` if $operatingSystem == 1;
	$stdout = `shasum $fileToHash` if $operatingSystem == 2;
	#shasum on osx has same output as linux sha1sum
	my @split = split (/\s+/, $stdout);
	
	#[$#split] gives you the last element of an array
	$stdout = $split[0] if $operatingSystem == 1;
	$stdout = $split[0] if $operatingSystem == 2;
	logIt("[info] ($currentCaseName) Done calculating sha1 hash of local file.", 1, 1, 1);
	chomp $stdout;
	return $stdout;   
}

#Because I am developing this on both OSX and linux I need to ensure
#the script would work on both linux and OSX. The reason being is that linux
#used the command 'md5sum' whereas OSX just uses 'md5'
sub checkOS
{
	push @debugMessages, logIt("[debug] (main) Checking operating system.",0,0,0,0);
	my $OS = $^O;
	my $osValue;
	if($OS eq "linux")
	{
		push @debugMessages, logIt("[debug] (main) Operating system is Linux.",0,0,0,0);
		$osValue = 1;
	}
	#darwin aka osx
	elsif($OS eq "darwin")
	{
		push @debugMessages, logIt("[debug] (main) Operating system is Mac OSX (darwin).",0,0,0,0);
		$osValue = 2;
	}
	else
	{
		push @debugMessages, logIt("[debug] (main) Unsupported operating system detected. ^O.",0,0,0,0);
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "You are running an operating system that this script is not designed to work for...\nYour operating system is: $^O\nSupported operating systems are Linux (linux) and OSX (darwin)\n");
		$message->Show;
		exit;
	}
	return $osValue;
}

#compares two hashes and returns 1 if they are different and 0 if they are the same
sub compareHashes
{
	my $currentHash = $_[0];	
	my 	$savedHash = $_[1];
	
	if($currentHash ne $savedHash)
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

#***********************************************************************************************************************************#
#******End of Commonly Used Subs to Make Life Better********************************************************************************#
#***********************************************************************************************************************************#

#Wait for events. Required for the program to work
MainLoop;

#Close any file handles that may be open
close (PROGRAMLOGFILE);
close ($currentCaseLog);
close (DEBUGLOGFILE);
close ($currentCaseIntegrityFile);