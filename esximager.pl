#!/usr/bin/perl
use strict;
use Tk;
use Tk::ProgressBar;
#use Tk::Text;
use Net::OpenSSH;
use Net::SFTP::Foreign;

########################
#ESXimager2.1.pl
#Matt Tentilucci	
#10-23-2014
#
#V2.1 - Adding in user confirmation of VM choices and passing them back to sshToESXi sub, removing lots of misc. lines from debugging/trial and error
########################

#variable so ssh session to esxi can be accessible outside of sub
my $ssh;

#Creates main window
my $mw = MainWindow->new;
$mw->title("ESXimager 2.0");
#$mw->geometry("600x600");

#Create menu bar
$mw->configure(-menu => my $menubar = $mw->Menu);
my $file = $menubar->cascade(-label => '~File');
my $edit = $menubar->cascade(-label => '~Edit');
my $help = $menubar->cascade(-label => '~Help');

#label for IP
$mw->Label(-text => "Server IP")
	->grid(-row => 0, -column => 0, -sticky => "w");
	
#entry for IP
my $ESXip = $mw->Entry( -width => 20, -text => "192.168.100.141")
	->grid(-row => 0, -column =>1, -sticky => "w");

#Label for user
$mw->Label(-text => "Username")
	->grid(-row => 1, -column => 0, -sticky => "w");

#entry for user
my $username = $mw->Entry( -width => 20,  -text => "root")
	->grid(-row => 1, -column =>1, -sticky => "w");

#label for pass
$mw->Label(-text => "Password")
	->grid(-row => 2, -column => 0, -sticky => "w");

#entry for pass
my $password = $mw->Entry( -width => 20, -show => "*",  -text => "netsys01")
	->grid(-row => 2, -column =>1, -sticky => "w");

#connect button, first calls sub to do input sanitization and checking on ip, username, and password boxes then 
#either falls out with an error, or another sub is called to connect to the ESXi server
$mw->Button(-text => "Connect", -command => \&sanitizeInputs )
	->grid(-row => 3, -column => 0, -columnspan => 2, -sticky => "w");	
	
#console window
my $consoleLog = $mw->Text(-height => 10)
	->grid ( -row => 4, -column => 1, -columnspan => 2, -sticky => "nsew");
	
#$consoleLog->insert('end',"\nfoo");

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
	
	findVMs("/vmfs/volumes/", $ip);
	
	
}

#find VMs on ESXi server and allows the user to select which VM(s) they want to image
sub findVMs
{
	my @vmxFound;
	my @getVMs;
	my $vmstore = $_[0];
	my $ip = $_[1];
	
	#creates sub window to display choices of VMs to acquire to user
	my $subWindow = $mw->Toplevel;
	$subWindow->title("Virtual Machines found on $ip");
	my $checkFrame = $subWindow->Frame()->pack(-side => "top");
	$checkFrame->Label(-text=>"Please select which virtual machines you want to image:")->pack(-side => "left")->pack();
	
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
	my $buttonFrame = $subWindow->Frame()->pack(-side => "bottom");
	my $okButton = $buttonFrame->Button(-text => 'OK',
                                       -command => [\&confirmUserVMImageChoices, \@checkButtonValues]
									   )->pack(-side => "left");
	my $cancelButton = $buttonFrame->Button(-text => "Cancel", -command => [$subWindow => 'destroy'])->pack();
}

#Confirms the users choices for which VMs they wish to acquire
sub confirmUserVMImageChoices
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

#DD target VMs, expects the absolute path and the filename 
sub ddTargetFile
{

	#!!check to see if ddimages directory exists!! figure out later
	#print "\n\n---------------------------\nCreating DD copy of target file\n";
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
	
	my $localDestination = "/home/matt/Desktop/" . $getFileName2;
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
	
	#print "*Calculating md5 hash this may take a while be patient...";
	$consoleLog->insert('end',"*Calculating md5 hash this may take a while be patient...");
	my $stdout = `md5sum $fileToHash`;
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
	
	#print "*Calculating sha1 hash this may take a while be patient...";
	$consoleLog->insert('end',"*Calculating sha1 hash this may take a while be patient...");
	my $stdout = `sha1sum $fileToHash`;
	#$stdout = $ssh->capture("sha1sum $fileToHash");
	#print "done!\n";
	$consoleLog->insert('end',"done!\n");
	chomp $stdout;
	return $stdout;   
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

#$window->Label( - text => "Degrees F")
#	->grid(-row => 1, -column => 1, -columnspan => 1);

#my $enteredFahrenheit = $window->Entry( -width => 10);
#$enteredFahrenheit ->grid(-row => 1, -column =>2);

#Wait for events
MainLoop;