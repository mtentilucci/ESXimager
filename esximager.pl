#!/usr/bin/perl
use strict;
use Tk;
#use Tk::Text;
use Net::OpenSSH;

########################
#ESXimager2.0.pl
#Matt Tentilucci	
#10-22-2014
#
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
	$ssh = Net::OpenSSH->new("$user:$password\@$ip", master_opts => [ -o => "StrictHostKeyChecking=no"]);
	$ssh->error and die "Could not connect to $ip" . $ssh->error;
	$consoleLog->insert('end', "done!\n");
	
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
	
	#my %vmSelectionHash = ();
	#my %checkButtonHash = ();
	my @checkButtons;
	my @checkButtonValues;
	my $counter = 0;
	
	# # my $var1;
	# # my $var2;
	# # my $var3;
	
	# # my $vars1 = $checkFrame->Checkbutton(-text => $vmxFound[0],
									# # -variable => $var1,
									# # -onvalue => 'CHECKED',
                                    # # -offvalue => 'NOT CHECKED')->pack();
	# # my $vars2 = $checkFrame->Checkbutton(-text => $vmxFound[1],
									# # -variable => $var2,
									# # -onvalue => 'CHECKED',
									# # -offvalue => 'NOT CHECKED')->pack();
	# # my $vars3 = $checkFrame->Checkbutton(-text => $vmxFound[2],
									# # -variable => $var3,
									# # -onvalue => 'CHECKED',
									# # -offvalue => 'NOT CHECKED')->pack();
									
	# # print "$var1 $var2 $var3";
	
	foreach(@vmxFound)
	{
		#$checkButtons[$counter] = 'Not Checked';
		#$checkFrame->Checkbutton(-text => $_)->pack();
		$checkButtons[$counter] = $checkFrame->Checkbutton(-text => $_,
									-onvalue => $_,
                                    -offvalue => '0',
									-variable => \$checkButtonValues[$counter])->pack();
		$counter++;
	}
	$consoleLog->insert('end', "After checkbox creation\n");
	my $buttonFrame = $subWindow->Frame()->pack(-side => "bottom");
	my $okButton = $buttonFrame->Button(-text => 'OK',
                                       -command => sub
													{
														$consoleLog->insert('end', "running sub\n");
														foreach(@checkButtonValues)
														{
															$consoleLog->insert('end', "$_\n");
														}
														#foreach my $key ( sort( keys( %vmSelectionHash ) ) ) 
														#{
														#	#print "Key: $key Value:$vmSelectionHash{$key} \n";
														#	$consoleLog->insert('end', "Key: $key Value:$vmSelectionHash{$key} \n");
														#}
													}
									   )->pack(-side => "left");
	$consoleLog->insert('end', "After button creation\n");
	#foreach my $key ( sort( keys( %vmSelectionHash ) ) ) 
	#{
		#print "Key: $key Value:$vmSelectionHash{$key} \n";
	#	$consoleLog->insert('end', "Key: $key Value:$vmSelectionHash{$key} \n");
	#}
	$consoleLog->insert('end', "After hash print creation\n");
}

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