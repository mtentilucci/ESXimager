#!/usr/bin/perl
use strict;
use Tk;
use Tk::ProgressBar;
use Tk::MsgBox;
use Tk::DirTree;
use Tk::Pane;
use Tk::Font;
#use Tk::Text;
use Net::OpenSSH;
use Net::SFTP::Foreign;

########################
#ESXimager2.6.pl
#Matt Tentilucci	
#12-6-2014
#
#V2.1 - Adding in user confirmation of VM choices and passing them back to sshToESXi sub, removing lots of misc. lines from debugging/trial and error
#V2.2 - Redesign user selection of VMs window and switched from grid to pack geometry manager. Instead of having a sub window, 
# there will be a frame within main window that will be updated with the VM choices for the user to image. This should be a much
# cleaner look and prevent multiple windows from popping up. Also added configuration file and Tools->Settings menu bar for editing it
#V2.3 - Added in menu item to open an existing case, variable cleanup, create new case, open case
#V2.4 - Created dirTreeFrame to show case directory listing to use once a case has been opened -> future, allow user to click on files and get info(size, hash, etc...)
# moved some boxes around, the connect frame is now horizontial at the top of the window
#V2.5 - Improved VM imaging window. Asks the user what VM they want to image, then what files from that VM, then confirms selection. Added windows telling the user
# what the program is doing, when the file gets DD, or hashes are being calculated because the program will not respond to user inputs when those things are being executed
# Controled where subwindows are shown on the screen, they show up in the middle of the main window. Changed console log box to scrolled and tied STDOUT to print in the box. 
# Now using print will print in the consoleLog, also $consoleLog->see('end') shows the bottom of the console log and esentially makes it scroll automatically as it grows 
# After the image has been dd'd and SFTP'd the script will cleanup the .dd files is created on the ESXi server
# Made the checkbutton frame scrolled when user has to select what vms/files they want to image
#V2.6 - Integrating buttons into file listing listbox to put selected file through strings and hexdump -C. Case names will not allow spaces, will =~ s/ //;
#
########################

#variable so ssh session to esxi can be accessible outside of sub
my $ssh;
my $checkFrame1;
my $checkFrame2;
my $buttonFrame1;
my $buttonFrame2;

#Variables for location of working directory, case directory, configuration file, and log file
my $configFileLocation = $ENV{"HOME"} . "/ESXimager/ESXimager.cfg";
my $ESXiWorkingDir;
my $ESXiCasesDir;
my $logFileDestination;
my $currentCaseName = "No Case Opened Yet";
my $currentCaseLocation;

#Creates main window
my $mw = MainWindow->new;
$mw->title("ESXimager 2.6");
$mw->geometry("1400x600");

#Create menu bar
$mw->configure(-menu => my $menubar = $mw->Menu);
my $file = $menubar->cascade(-label => '~File');
my $tools = $menubar->cascade(-label => '~Tools');
my $view = $menubar->cascade(-label => '~View');
my $help = $menubar->cascade(-label => '~Help');

$file->command(-label => 'New Case', -underline => 0, -command => \&createNewCase);
$file->command(-label => 'Open Case', -underline => 0, -command => \&openExistingCase);
$file->separator;
$file->command(-label => "Quit", -underline => 0, -command => \&exit);

$tools->command(-label => "Settings", -command => \&editSettings);

#console window
#Anytime print is used, it will output to the $consoleLog window
#my $consoleLog = $mw->Text(-height => 10, -width => 125)->pack(-side => 'bottom', -fill => 'both');
my $consoleLog = $mw->Scrolled('Text',-height => 10, -width => 125)->pack(-side => 'bottom', -fill => 'both');
tie *STDOUT, 'Tk::Text', $consoleLog->Subwidget('scrolled');

##Connection Frame##
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
#my $caseLabel = $mw->Label(-text => "Current Case: $currentCaseName Location: $currentCaseLocation")->pack;#(-side => 'left', -anchor => 'nw');
my $caseLabel = $mw->Label(-text => "$currentCaseName. You must open a case before imaging a VM")->pack;#(-side => 'left', -anchor => 'nw');


##Dir File Frame##	
my $dirFileFrame = $mw->Frame(-borderwidth => 2, -relief => 'groove');
$dirFileFrame->pack(-side => 'right', -fill => 'both');
###Dir Tree Frame##
my $dirTreeFrame = $dirFileFrame->Frame(-borderwidth => 2, -relief => 'groove');
$dirTreeFrame->pack(-side => 'left', -fill => 'both');
#my $dirTreeLabel = $dirTreeFrame->Label(-text => "Directory listing of open case:\nOpen a case to populate\n")->pack;
#my $dirTree = $dirTreeFrame->DirTree(-directory => $ESXiCasesDir, -width => 60, -height => 20, -browsecmd => \&listFiles)->pack(-side => 'left',  -anchor => 'n');
my $dirTree = $dirTreeFrame->Scrolled('DirTree', -scrollbars => 'e', -directory => $ESXiCasesDir, -width => 35, -height => 20, -browsecmd => \&listFiles)->pack(-side => 'left',  -anchor => 'n', -fill => 'both');
###End Dir Tree Frame##
###File List Frame##
my $fileListFrame = $dirFileFrame->Frame(-borderwidth => 2, -relief => 'groove');
$fileListFrame->pack(-side => 'right', -fill => 'both');
my $fileList = $fileListFrame->Scrolled('Listbox', -scrollbars => 'e', -width => 40, -height => 15)->pack(-side => 'top',  -anchor => 'n', -fill => 'both', -expand => 1);
listFiles($ESXiCasesDir);
$fileListFrame->Label(-text => "Display Selected File In: ")->pack(-side => 'left', -anchor => 's', -fill => 'both');
my $stringsButton = $fileListFrame->Button(-text => "Strings", -command => [\&runThroughStrings, \$fileList])->pack(-side => 'left', -anchor => 's', -fill => 'both', -expand => 1);
my $hexdumpButton = $fileListFrame->Button(-text => "Hexdump", -command => [\&runThroughHexdump, \$fileList])->pack(-side => 'left', -anchor => 's', -fill => 'both', -expand => 1);
###End File List Frame##
##End Dir Tree Frame##

##VM Choices Frame##
my $vmChoicesFrame = $mw->Frame(-borderwidth => 2, -relief => 'groove');
$vmChoicesFrame->pack(-side => 'left', -fill => 'both', -expand => 1);
my $vmChoicesLabel = $vmChoicesFrame->Label(-text => "Connect to an ESXi server to populate\n")->pack;
##EndVM Choices Frame##

$consoleLog->see('end');


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
				$dirTree->chdir($ESXiCasesDir);
				listFiles($ESXiCasesDir);
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
				$consoleLog->see('end');
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
	$consoleLog->see('end');
	
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
	$consoleLog->see('end');
	$mw->update;
	
	#my $stdout = $ssh->capture("ls -l /vmfs/volumes/");
	#$consoleLog->insert('end', $stdout);
	
	#Are all vm's stored here? Investigate what path is used for each esxi host for iscsi or VMs on a SAN
	findVMs("/vmfs/volumes/", $ip);
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
	
	# #creates sub window to display choices of VMs to acquire to user
	# my $subWindow = $mw->Toplevel;
	# $subWindow->title("Virtual Machines found on $ip");
	# my $checkFrame = $subWindow->Frame()->pack(-side => "top");
	# $checkFrame->Label(-text=>"Please select which virtual machines you want to image:")->pack(-side => "left")->pack();
	
	#my $subWindow = $mw->Toplevel;
	#$vmChoicesFrame->title("Virtual Machines found on $ip");
	#$checkFrame1 = $vmChoicesFrame->Frame()->pack(-side => "top");
	#make the checkbox frame scrollable incase there are multiple VMs/files that go beyond the window size
	$checkFrame1 = $vmChoicesFrame->Scrolled('Pane',-scrollbars => 'osoe')->pack(-side => 'top', -fill => 'both', -expand => 1);
	if (defined $vmChoicesLabel)
	{
		$vmChoicesLabel->packForget;
	}
	$checkFrame1->Label(-text=>"Please select which virtual machines you want to image:")->pack(-side => "top")->pack();
	
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
		$checkButtons[$counter] = $checkFrame1->Checkbutton(-text => $_,-onvalue => $_,-offvalue => '0',-variable => \$checkButtonValues[$counter])->pack();
		$counter++;
	}
	
	#Creates ok and cancel button to approve VM selections
	$buttonFrame1 = $vmChoicesFrame->Frame()->pack(-side => "bottom");
	my $okButton = $buttonFrame1->Button(-text => 'Next', -command => [\&selectVMFiles, \@checkButtonValues])->pack(-side => "left");
	#my $cancelButton = $buttonFrame->Button(-text => "Cancel", -command => [$subWindow => 'destroy'])->pack();
}

#Step 2: $checkFrame2 and $checkFrame2 - destroys the frames from the findVMs sub and replaces them with files assiciated with the VMs they want to image.
#Asks the user what files they want to acquire, .vmx .vmdk .vmem etc.....
sub selectVMFiles
{
	my @vmsToRestart;
	if($currentCaseName =~ m/No Case Opened Yet/)
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "A case has not yet been opened. Open a case before imaging a VM.\n");
		$message->Show;
	}
	else
	{
		my $choicesRef = shift; #$_[0];
		my @findVMFiles;
		foreach(@$choicesRef)
		{
			#$consoleLog->insert('end',"**Working on --$_--\n");
			if($_ ne '0')
			{
				#$consoleLog->insert('end',"**--$_-- is not 0\n");
				push @findVMFiles, $_;
			}
			else
			{
				#$consoleLog->insert('end',"**--$_-- is 0\n");
			}
		}
		my $count = @findVMFiles;
		if ($count == 0)
		{
			my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "No VM's were selected to be imaged.\n");
			$message->Show;
		}
		else
		{
			foreach(@findVMFiles)
			{
				my $vmStatus = checkIfVMRunning($_);
				print "VM status is: $vmStatus\n";
				if ($vmStatus == 1)
				{
					my $messageBoxAnswer = $mw->messageBox(-title => "Suspend Virtual Machine?", -type => "YesNo", -icon => "question", -message => "$_ is currently powered on and running.\nDo you want to suspend it?\n", -default => "yes");
					$consoleLog->insert('end',"**Message box answer: --$messageBoxAnswer--\n");
					$consoleLog->see('end');
					if ($messageBoxAnswer eq 'Yes')
					{
						suspendVM($_);
						push @vmsToRestart, $_;						
					}
				}	
			}
			$checkFrame1->destroy();
			$buttonFrame1->destroy();
			
			my @checkButtons;
			my @checkButtonValues;
			my $counter = 0;
			
			#$checkFrame2 = $vmChoicesFrame->Frame()->pack(-side => "top");
			$checkFrame2 = $vmChoicesFrame->Scrolled('Pane', -scrollbars => 'osoe')->pack(-side => 'top', -fill => 'both', -expand => 1);
			#$checkFrame2->Label(-text=>"Please select which virtual machines you want to image:")->pack(-side => "top")->pack();
			
			foreach(@findVMFiles)
			{
				$consoleLog->insert('end', "Path -> --$_--\n");
				$consoleLog->see('end');
				my $VMDirPath = getDirName($_);
				$consoleLog->insert('end', "VMDIRPATH -> --$VMDirPath--\n");
				$consoleLog->see('end');
				#lists (ls) the given directory on the esxi server
				my $stdout = $ssh->capture("ls $VMDirPath");
				$consoleLog->insert('end', "STDOUT -> --$stdout--\n");
				$consoleLog->see('end');
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
	$consoleLog->insert('end',"--$currentCaseName--\n");
	$consoleLog->see('end');

	if($currentCaseName =~ m/No Case Opened Yet/)
	{
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
		
		my $count = @VMsToImage;
		if ($count == 0)
		{
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
			my $messageBoxAnswer = $mw->messageBox(-title => "Test", -type => "YesNo", -icon => "question", -message => "Would you like to image the following VMs files?: @shortVMFileNames", -default => "yes");
			$consoleLog->insert('end',"**Message box answer: --$messageBoxAnswer--\n");
			$consoleLog->see('end');
			if ($messageBoxAnswer eq 'Yes')
			{
				$consoleLog->insert('end',"**Message box answer $messageBoxAnswer was yes\n");
				foreach(@VMsToImage)
				{
					$consoleLog->insert('end',"Working on $_\n");
					$consoleLog->see('end');
					#my $targetImageFile = ddTargetFile($_, getFileName($_));
					my $targetImageFile = ddTargetFile($_);
					#print "Going to SFTP $targetImageFile to this computer\n";
					my $ip = $ESXip->get;
					$consoleLog->insert('end',"Going to SFTP $targetImageFile to this computer from esxi server at IP $ip\n");
					$consoleLog->see('end');
					$mw->update;
					sftpTargetFileImage($targetImageFile);
				}
				#Restart VMs that were suspended once the imaging process is complete
				foreach (@$vmsToRestartRef)
				{
					startVM($_);
				}
				#Maybe add more info to the "done" window
				my $message = $mw->MsgBox(-title => "Info", -type => "ok", -icon => "info", -message => "Done!\n");
				$message->Show;
				#Return the vm selection window to what it was origionally in case user wants to image more VMs
				findVMs();
			}
			else
			{
				$consoleLog->insert('end',"**Message box answer $messageBoxAnswer was no\n");
			}
		}
	}
}

#Step 4: DD target VMs, expects the absolute path to the vm file on ESXi server
sub ddTargetFile
{
	#!!check to see if ddimages directory exists!! figure out later
	#print "\n\n---------------------------\nCreating DD copy of target file\n";
	my $absolutePathFileToDD = $_[0];
	#my $fileToDD = $_[1];
	#my $fileToDDDestinationName  = $fileToDD;
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
	
	#determine file size of file we are about to acquire
	my $fileSize = $ssh->capture("ls -lah $absolutePathFileToDD");
	$fileSize = returnFileSize($fileSize);
	my $subWindow = $mw->Toplevel;
	$subWindow->title("Size");
	
	########debugging window position stuff 
	my $mwx = $mw->x;
	my $mwy = $mw->y;
	my $mwHeight = $mw->height;
	my $mwWidth = $mw->width;
	my $swHeight = $subWindow->height;
	my $swWidth = $subWindow->width;
	
	$consoleLog->insert('end',"mwx=$mwx \nmwy=$mwy \nmwHeight=$mwHeight \nmwWidth=$mwWidth \nsubWindowHeight=$swHeight \nsubWindowWidth=$swWidth");
	$consoleLog->see('end');
	###########debugging window position stuff 
	
	#Adjusts the sub window to appear in the middle of the main window
	my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
	my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
	$subWindow->geometry("+$xpos+$ypos");
	 # Center window
	#my $xpos = int(($subWindow->screenwidth  - $subWindow->width ) / 2);
	#my $ypos = int(($subWindow->screenheight - $subWindow->height) / 2);
	
	#Tells the user what is happening b/c they will not have control until they get to the SFTP step
	$subWindow->Label(-text => "File: $absolutePathFileToDD\nSize: $fileSize\nCalculating MD5 and SHA1 hashes for $absolutePathFileToDD...\nThis may take some time depending on the file size, please be patient\n")->pack;
	$mw->update;

	sleep(1);
	
	my $md5 = calculateMD5HashOnESX($absolutePathFileToDD);
	my $sha1 = calculateSHA1HashOnESX($absolutePathFileToDD);

	#Done telling the user some info, destroy the sub window b/c we are about to create a new one with new info
	$subWindow->destroy();
	
	#print "Hashes Before DD:\n \tMD5: $md5\n \tSHA1: $sha1\n";
	$consoleLog->insert('end',"Hashes Before DD:\n \tMD5: $md5\n \tSHA1: $sha1\n");
	$consoleLog->see('end');
	$mw->update;
	sleep(1);

	my $subWindow = $mw->Toplevel;
	$subWindow->title("Size");
	
	#Dont need to recalculate window position again b/c the main window should not have been moved. Just using values calculated from above
	$subWindow->geometry("+$xpos+$ypos");
	
	$subWindow->Label(-text => "File: $absolutePathFileToDD\nSize: $fileSize\nCreating a copy of $absolutePathFileToDD with DD...\nThis may take some time depending on thefile size, please be patient\n")->pack;
	$mw->update;
	
	sleep(5);
	
	my $stdout = $ssh->capture("dd if=$absolutePathFileToDD of=$ddDestination");
	
	$subWindow->destroy();
	
	my $pathToHash = $ddDestination;
	my $md5Check = calculateMD5HashOnESX($pathToHash);
	my $sha1Check = calculateSHA1HashOnESX($pathToHash);
	#print "Hashes After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check\n";
	$consoleLog->insert('end',"Hashes After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check\n");
	$consoleLog->see('end');
	$mw->update;
	sleep(1);
	return $pathToHash;

}

#Step 5: SFTP target VMs, expects absolute path to target dd file
sub sftpTargetFileImage
{
	#my $serverIP = $_[0];
	my $fileToSFTP = $_[0];

	my %args; #= ( user => 'root',password => 'netsys01');
	my $serverIP = $ESXip->get;
	my $user = $username->get;
	#$consoleLog->insert('end', "$user\n");
	my $password = $password->get;
	my $host= '192.168.100.141';
	$consoleLog->insert('end', "Going to connect to $serverIP with credeitials $user and $password\n");
	$consoleLog->see('end');
	$mw->update;
	my $sftp = Net::SFTP::Foreign->new($serverIP,  user => $user, password => $password);
	$sftp->die_on_error("SSH Connection Failed");
	
	
	my $getFileName2 = getFileName($fileToSFTP);
	#my @filePathParts2 = split('/', $fileToSFTP);
	#my $getFileName2 = pop(@filePathParts2);
	
	#Now that we have a cases directory, the images need to be saved to that directory
	#my $localDestination = "/home/matt/Desktop/" . $getFileName2;
	my $localDestination = $currentCaseLocation . "/" . $getFileName2;
	$consoleLog->insert('end', "Transfering file from:$fileToSFTP to:$localDestination\n");
	$consoleLog->see('end');
	$mw->update;

	#print "This file will SFTP from $fileToSFTP to $localDestination\n";
	#my $f=<STDIN>;

	#Create progress bar to show user program is doing something
	my $percentDone = 0;
	my $subWindow = $mw->Toplevel;
	$subWindow->title("Transfering Image");
	$subWindow->geometry("300x30");
	
	my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
	my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
	$subWindow->geometry("+$xpos+$ypos");
	 # Center window
	#my $xpos = int(($subWindow->screenwidth  - $subWindow->width ) / 2);
	#my $ypos = int(($subWindow->screenheight - $subWindow->height) / 2);
	
	my $progressBar = $subWindow->ProgressBar(-width => 30, -blocks => 50, -from => 0, -to => 100, -variable => \$percentDone)->pack(-fill => 'x');
	
	$sftp->get($fileToSFTP,$localDestination, callback => sub {
		my ($sftp, $data, $offset, $size) = @_;
		#print "$offset of $size bytes read\n";
		$percentDone = ($offset / $size) * 100;
		$subWindow->update;
	
	}); #or die "File transfer failed\n";
	$subWindow->destroy;
	#With transfer complete, destroy the progress bar window
	sleep(2);
	
	#get the file size locally
	my $fileSize = `ls -lah $localDestination`;
	$fileSize = returnFileSize($fileSize);
	
	#Create subwindow to tell use the program is calculating hashes
	my $subWindow = $mw->Toplevel;
	$subWindow->title("Size");
	#Adjusts the sub window to appear in the middle of the main window
	my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
	my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
	$subWindow->geometry("+$xpos+$ypos");
	
	#Tells the user what is happening b/c they will not have control while hashes are being calculated
	$subWindow->Label(-text => "File: $localDestination\nSize: $fileSize\nCalculating MD5 and SHA1 hashes for $localDestination...\nThis may take some time depending on the file size, please be patient\n")->pack;
	$mw->update;
	
	my $md5Check = calculateMD5HashLocal($localDestination);
	my $sha1Check = calculateSHA1HashLocal($localDestination);
	#print "Hashes After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check\n";
	$consoleLog->insert('end',"Hashes After DD:\n \tMD5: $md5Check\n \tSHA1: $sha1Check\n");
	$consoleLog->see('end');
	sleep(1);
	
	cleanup($fileToSFTP);
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
		#print "going to work on $_\n";
		my @lineParts = split(/\s+/, $_);
		foreach (@lineParts)
		{
			#print "comparing $vmxPath is $_\n";
			if ($_ =~ m/$vmxPath/)
			{
				#print "Match, $vmxPath is $_\n";
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
	my $stdout = $ssh->capture('/sbin/vmdumper -l');
	my @lines = split(/\n/, $stdout);
	foreach(@lines)
	{
		my @lineParts = split(/\s+/, $_);
		foreach (@lineParts)
		{
			print "comparing $vmxPath is $_\n";
			if ($_ =~ m/$vmxPath/)
			{
				print "Match, $vmxPath is $_\n";
				print "here is the current WID $lineParts[0]\n";
				my $VMwid = $lineParts[0];
				$VMwid =~ s/=/ /g;
				my @VMwidSplit = split(/\s+/,$VMwid);
				print "Cleaned WID $VMwidSplit[1]\n";
				print "going to execute /sbin/vmdumper $VMwidSplit[1] suspend_vm\n";
				my $stdout = $ssh->capture("/sbin/vmdumper $VMwidSplit[1] suspend_vm") or warn "remote command failed " . $ssh->error;
				print "Suspending VM...";
				
				my $subWindow = $mw->Toplevel;
				$subWindow->title("Suspending VM: $vmxPath");
				#Adjusts the sub window to appear in the middle of the main window
				my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
				my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
				$subWindow->geometry("+$xpos+$ypos");
				
				my $size = 24;
				my $font = $subWindow->fontCreate(-size => $size);
				#,-height => 10, -width => 125
				my $text = "Suspending VM...";
				my $suspendVMLabel = $subWindow->Label(-text => $text,-width => 20, -font => $font)->pack(-fill => 'both');
				$mw->update;
				my $vmStillRunning = 1;
				while ($vmStillRunning == 1)
				{
					$vmStillRunning = checkIfVMRunning($vmxPath);
					print ".";
					$text = $text . ".";
					$suspendVMLabel->configure(-text => $text);
					$mw->update;
					sleep(1);
				}
				print "Done!\n";
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
	print "going to try and restart this vm $vmToRestart\n";
	my $vmxFile = getFileName($vmToRestart);
	print "this is the vmx $vmxFile\n";
	my $stdout = $ssh->capture("vim-cmd vmsvc/getallvms |grep $vmxFile");
	my @lines = split(/\n/, $stdout);
	my $count = @lines;
	#only one .vmx file was matched so we dont need to worry about starting the wrong VM
	if ($count == 1)
	{
		my @parts = split(/\s+/, $lines[0]);
		print "@parts\n";
		print "Here is the VMID $parts[0]\n";
		print "This command can be executed vim-cmd vmsvc/power.on $parts[0]\n";
		my $stdout = $ssh->capture("vim-cmd vmsvc/power.on $parts[0]") or warn "remote command failed " . $ssh->error;
		print "Starting VM...";
		
		my $subWindow = $mw->Toplevel;
		$subWindow->title("Starting VM: $vmToRestart");
		#Adjusts the sub window to appear in the middle of the main window
		my $xpos = int((($mw->width - $subWindow->width) / 2) + $mw->x);
		my $ypos = int((($mw->height - $subWindow->height) / 2) + $mw->y);
		$subWindow->geometry("+$xpos+$ypos");
		
		my $size = 24;
		my $font = $subWindow->fontCreate(-size => $size);
		#,-height => 10, -width => 125
		my $text = "Strting VM...";
		my $startVMLabel = $subWindow->Label(-text => $text,-width => 20, -font => $font)->pack(-fill => 'both');
		$mw->update;
		my $vmStillRunning = 0;
		while ($vmStillRunning == 0)
		{
			$vmStillRunning = checkIfVMRunning($vmToRestart);
			print ".";
			$text = $text . ".";
			$startVMLabel->configure(-text => $text);
			$mw->update;
			sleep(1);
		}
		print "Done!\n";
		$subWindow->destroy();
		return 0;
	}
}

#because the dd images are being stored into the same directory the file exists in on the ESXi server, we want to clean up these files when we are done
#expects the absolute path of the file to delete on the esxi server and will also check that the file has a .dd extension so the wrong file does not get deleted which would be very bad
#ideally dd would "store" copies somewhere else but this is how I have it setup for now
sub cleanup
{
	my $fileToDel = $_[0];
	if ($fileToDel =~ m/.+\.dd$/)
	{
		print "Going to delete file $fileToDel\n";
		my $stdout = $ssh->capture("rm -f $fileToDel");
		print "STDOUT: $stdout ...Done!\n";
		$consoleLog->see('end');
	}
	else
	{
		print "File ($fileToDel) does not have a .dd extension, will not delete this file\n";
		$consoleLog->see('end');
	}
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
				$consoleLog->see('end');
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
		$consoleLog->see('end');
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
			#Dont want case names to have any spaces
			$currentCaseName =~ s/ //g;
			print "current case name: $currentCaseName\n";
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
				$consoleLog->insert('end', "Created new case: $currentCaseName Location: $currentCaseLocation\n");
				$consoleLog->see('end');
				$caseLabel->configure(-text => "Current Case: $currentCaseName Location: $currentCaseLocation");
				#$dirTreeLabel->configure(-text => "Directory listing of open case:\n");
				#my $dirTree = $dirTreeFrame->DirTree(-directory => $currentCaseLocation)->pack;
				$dirTree->chdir($currentCaseLocation);
				listFiles($currentCaseLocation);
				$mw->update;
			}
		
	})->pack(-side => "left");	
	my $cancelButton = $createCaseWindowBottomFrame->Button(-text => "Exit", -command => [$createCaseWindow => 'destroy'])->pack(-side => "left");
}

#Allows user to open existing case, brings up a popup direcoty navigation window to allow the user to select the case they want to open
sub openExistingCase
{
	#my $filename = $mw->getOpenFile(-initialdir=>$ESXiCasesDir);
	##More work to be done here
	my $directory = $mw->chooseDirectory(-initialdir=>$ESXiCasesDir, -title => "Select a case to open");
	$currentCaseLocation = $directory;
	$currentCaseName = getFileName($currentCaseLocation);
	##my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "current case name: --$currentCaseName-- dir: --$currentCaseLocation--n");
		##$message->Show;
	$consoleLog->insert('end', "Opened an existing case: $currentCaseName Location: $currentCaseLocation\n");
	$consoleLog->see('end');
	$caseLabel->configure(-text => "Current Case: $currentCaseName Location: $currentCaseLocation");
	#$dirTreeLabel->configure(-text => "Directory listing of open case:\n");
	#my $dirTree = $dirTreeFrame->DirTree(-directory => $currentCaseLocation)->pack;
	$dirTree->chdir($currentCaseLocation);
	listFiles($currentCaseLocation);
	$mw->update;
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
	print "@cursorSelection\n";
	
	#The current directory being listed is always shown at the top of the fileList listbox, this is element 0 of the listbox
	my $currentDirectory = $fileListBoxDeref->get(0);
	print "got current directory $currentDirectory\n";
	
	my $targetFile = $fileListBoxDeref->get(0) . "/" . $fileListBoxDeref->get($cursorSelection[0]);
	print "target file $targetFile\n";
	
	if (-f $targetFile)
	{
		print "is a file\n";
		my $subWindow = $mw->Toplevel;
		$subWindow->title("Strings Output of File: $targetFile");
		#,-height => 10, -width => 125
		my $stringsOutputWindow = $subWindow->Scrolled('Text')->pack(-fill => 'both');
		my $stringsFindLabel = $subWindow->Entry(-width => 20)->pack();
		$subWindow->Button(-text => "Find", -command => sub {
			my $searchString = $stringsFindLabel->get;
			#my $textFindAll = $stringsOutputWindow->FindAll(-regexp, -nocase, m/.+\$searchString.+/);
			print "searc string: $searchString\n";
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
	elsif($cursorSelection[0] == 1 | $cursorSelection[0] == 0)
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "No valid file selected. Please select a file.\n");
		$message->Show;
	}
	#Otherwise they probably selected a directory 
	else
	{
		print "---$targetFile--nont of the above\n";
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
	print "@cursorSelection\n";
	
	#The current directory being listed is always shown at the top of the fileList listbox, this is element 0 of the listbox
	my $currentDirectory = $fileListBoxDeref->get(0);
	print "got current directory $currentDirectory\n";
	
	my $targetFile = $fileListBoxDeref->get(0) . "/" . $fileListBoxDeref->get($cursorSelection[0]);
	print "target file $targetFile\n";
	
	if (-f $targetFile)
	{
		print "is a file\n";
		my $subWindow = $mw->Toplevel;
		$subWindow->title("Hexdump Output of File: $targetFile");
		#,-height => 10, -width => 125
		my $stringsOutputWindow = $subWindow->Scrolled('Text')->pack(-fill => 'both');
		$subWindow->Button(-text => "Close Window", -command => [$subWindow => 'destroy'])->pack();
		my $stdout = `hexdump -C $targetFile`;
		$stringsOutputWindow->insert('end', $stdout);
	}
	#To prevent anything from happening if the user selects the divider line ------------------------ or the current directory path located at the top of the listbox
	elsif($cursorSelection[0] == 1 | $cursorSelection[0] == 0)
	{
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "No valid file selected. Please select a file.\n");
		$message->Show;
	}
	#Otherwise they probably selected a directory 
	else
	{
		print "---$targetFile--nont of the above\n";
		my $message = $mw->MsgBox(-title => "Error", -type => "ok", -icon => "error", -message => "$targetFile is a directory. Please select a file.\n");
		$message->Show;
	}
	
}

#***********************************************************************************************************************************#
#******Start of Commonly Used Subs to Make Life Better******************************************************************************#
#***********************************************************************************************************************************#

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

	$consoleLog->insert('end',"Got this: $absolutePath\n");
	$consoleLog->see('end');
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
	$consoleLog->insert('end',"Returning This:  $parentDirPath\n");
	$consoleLog->see('end');
	return $parentDirPath;
}

#Calculate MD5 hash of file about to be copied on ESX server
sub calculateMD5HashOnESX
{
	my $fileToHash = $_[0];
	
	#print "*Calculating md5 hash this may take a while be patient...";
	$consoleLog->insert('end',"*Calculating md5 hash this may take a while be patient...");
	$consoleLog->see('end');
	my $stdout = $ssh->capture("md5sum $fileToHash");
	#print "done!\n";
	$consoleLog->insert('end',"done!\n");
	$consoleLog->see('end');
	chomp $stdout;
	return $stdout;   
}

# Calculate SHA1 hash of the file about to be copied on ESX server
sub calculateSHA1HashOnESX
{
	my $fileToHash = $_[0];
	
	#print "*Calculating sha1 hash this may take a while be patient...";
	$consoleLog->insert('end',"Calculating sha1 hash this may take a while be patient...");
	$consoleLog->see('end');
	my $stdout = $ssh->capture("sha1sum $fileToHash");
	#print "done!\n";
	$consoleLog->insert('end',"done!\n");
	$consoleLog->see('end');
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
	$consoleLog->see('end');
	my $stdout = `md5sum $fileToHash` if $operatingSystem == 1;
	$stdout = `md5 $fileToHash` if $operatingSystem == 2;
	
	my @split = split (/\s+/, $stdout);
	#print "$split[$#split]\n" if $operatingSystem == 2;
	#print "$split[0]\n" if $operatingSystem == 1;
	
	$consoleLog->insert('end',"\nRaw: @split\n");
	$consoleLog->see('end');
	
	#[$#split] gives you the last element of an array
	$stdout = $split[0] if $operatingSystem == 1;
	$stdout = $split[$#split] if $operatingSystem == 2;

	#$stdout = $ssh->capture("md5sum $fileToHash");
	#print "done!\n";
	$consoleLog->insert('end',"done!\n");
	$consoleLog->see('end');
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
	$consoleLog->see('end');
	my $stdout = `sha1sum $fileToHash` if $operatingSystem == 1;
	$stdout = `shasum $fileToHash` if $operatingSystem == 2;
	
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
	$consoleLog->see('end');
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