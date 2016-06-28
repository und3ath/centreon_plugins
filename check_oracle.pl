#! /usr/bin/perl -w

# arg template connected-user:80:95|process-usage:80:90|tablespace-usage:[AO_INDX!65!80%AO_DATA!65!90]



# Trick ultra moche pour la multi compatibilité oracle .
use lib '/root/perl5/lib/perl5/';
my $ora_home = "/usr/lib64/nagios/plugins/instantclient_10_1";
my $ora_path = "/usr/lib64/nagios/plugins/instantclient_10_1";
my $ora_ldlibpath = "/usr/lib64/nagios/plugins/instantclient_10_1:/usr/lib:/usr/lib64";
my $ora_tns = "/usr/lib64/nagios/plugins/instantclient_10_1";
$ENV{'ORACLE_HOME'} = $ora_home;
$ENV{'PATH'} = $ora_path;
$ENV{'LD_LIBRARY_PATH'} = $ora_ldlibpath;
$ENV{'TNS_ADMIN'} = $ora_tns;




use strict;
use warnings;
use DateTime;
use Switch;
use Nagios::Plugin;
use Nagios::Plugin::Threshold;
use Nagios::Plugin::Performance;
use Scalar::Util qw(looks_like_number);


# Declarations des variables pour le plugins Nagios. 
use vars qw($nagios_plugin $plugin_version $plugin_license $plugin_usage_desc);
use vars qw($db_instance $db_username $db_password);
use vars qw(%valid_variables %valid_arguements);
use vars qw($database_handle);
use vars qw(@obj_to_check);
use vars qw(@nagios_check_results);

# Declaration des methods et procedures du package principal. 
sub ParseCommandLines;
sub LoadAuthFile;
sub VerifyObjectToCheck;
sub ExecuteChecks;
sub ParseNagiosCheckResult;


%valid_variables  = ('connected-users' => 0, 'process-usage' => 1, 'startup-time' => 2, 'tablespace-usage' => 3);


###################################################
################# Entry Point #####################
###################################################

$plugin_version = '0.1';
$plugin_license = '05/03/2014';
$plugin_usage_desc = "\n \n";




$nagios_plugin = Nagios::Plugin->new(
       shortname => 'Oracle',
	usage =>   $plugin_usage_desc,
	version => $plugin_version,
	license => $plugin_license,
	plugin  => $0,
	timeout => 15);
        
$nagios_plugin->add_arg(
	spec      => 'instance|i=s',
	help      => "-i, --instance\n TNS Instance",
	required  => 1);


$nagios_plugin->add_arg(
	spec	  => 'authfile|f=s',
	help	  => "-f, --authfile\n Authentification file (more secure)",
	required  => 0);

$nagios_plugin->add_arg(
	spec      => 'username|u=s',
	help      => "-u, --username\n Db Username",
	required  => 0);
	
$nagios_plugin->add_arg(
	spec      => 'password|p=s',
	help      => "-p, --password\n Db Password",
	required  => 0);
	
$nagios_plugin->add_arg(
	spec      => 'variable|b=s',
	help      => "-b, --variable\n params",
	required  => 1);


$nagios_plugin->getopts;


#Here the devil . 
ParseCommandLines();
ExecuteChecks();


########################################
######### Methods & Procedures #########
########################################


sub ParseCommandLines
{
	
	if(!defined($nagios_plugin->opts->username) and !defined($nagios_plugin->opts->password) and !defined($nagios_plugin->opts->authfile))
	{
		$nagios_plugin->nagios_exit(CRITICAL, "Vous devez specifier un fichier d'authentification ou un utilisateur/password ");
	}
	

	if(defined($nagios_plugin->opts->authfile))
	{
		LoadAuthFile();
	}
	else
	{
		$db_username = $nagios_plugin->opts->username;
		$db_password = $nagios_plugin->opts->password;	
	}
	$db_instance = $nagios_plugin->opts->instance;
	
	
	
	my $current = $nagios_plugin->opts->variable;
	if($current =~ /\|/) 
	{
		@obj_to_check = split(/\|/, $nagios_plugin->opts->variable); 
	}
	else 
	{
		push(@obj_to_check, $current);
	}
	
	VerifyObjectToCheck();
}


sub LoadAuthFile
{
	my $path = $nagios_plugin->opts->authfile;
	my $file = undef;
	open $file, '<', $path or $nagios_plugin->nagios_exit(CRITICAL, "Impossible d'ouvrire le fichier $file d'authentification : $!");
	my $authString = <$file>;
	close $file;
	
	if($authString =~ /:/)
	{
		my @auth = split(/:/, $authString);
		$db_username = $auth[0];
		$db_password = $auth[1];
	}
	else
	{
		$nagios_plugin->nagios_exit(CRITICAL, "$authString est dans un format invalide");
	}
	
}

sub VerifyObjectToCheck
{
	foreach(@obj_to_check) 
	{   # => e.g connected-users:50:100
		my @obj;
		my $current_obj = $_;	
		if($current_obj =~ /:/) 
		{			
			@obj = split(/:/, $current_obj);
		}
		else 
		{			
			push(@obj, $current_obj);
		}	
		if(!exists($valid_variables{$obj[0]})) 
		{
			$nagios_plugin->nagios_exit(UNKNOWN, "$obj[0] is not a valid variable"); 
		}
		elsif($valid_variables{$obj[0]} eq 'connected-users' || $valid_variables{$obj[0]} eq 'process-usage')
		{
			if($obj[1] || $obj[2])
			{
				if(!looks_like_number($obj[1]) && !looks_like_number($obj[2]))
				{
					$nagios_plugin->nagios_exit(UNKNOWN, "When $obj[0] is defined with range it must be a numeric value"); 
				}
			}
		}
		elsif($valid_variables{$obj[0]} eq 'tablespace-usage')
		{
			if(!$obj[1])
			{
				$nagios_plugin->nagios_exit(UNKNOWN, 'When checking tablespace usage , a tablespace name must be provided'); 
			}
		}
				
	}
}


sub ExecuteChecks
{
	$database_handle = new SQL_WORKER(
		{
			nagios_plugin	=>	$nagios_plugin,
			db_instance	=>	$db_instance,
			db_username	=>	$db_username,
			db_password	=>	$db_password
		});
	

	$database_handle->DbConnect();
	
	foreach(@obj_to_check) 
	{
		my $to_check = undef;
		my $current = $_;
		switch ($current) 
		{
			case m/startup-time/  
			{				
				$to_check = new CHECK_ORACLE_STRATUP_TIME(
					{
						db_handle => $database_handle,
						command   => $current
					});			
			}
			case m/connected-users/ 
			{
				$to_check = new CHECK_ORACLE_CONNECTED_USERS(
					{
						db_handle => $database_handle,
						command	  => $current
					});
			}
			case m/process-usage/ 
			{
				$to_check = new CHECK_ORACLE_PROCESS_USAGE(
					{
						db_handle => $database_handle,
						command	  => $current
					});
			}
			case m/tablespace-usage/ 
			{
				$to_check = new CHECK_ORACLE_TABLESPACE_USAGE(
					{
						db_handle => $database_handle,
						command	  => $current
					});
			}
			
		}	
		$to_check->ProcessCheck();		
	}
	
	$database_handle->CloseConnexion();
	$database_handle = undef; # Destruction de l'object et liberation de la memoire. 	
	ParseNagiosCheckResult();
}


# Fonction final * construction du retour du plugins * 
sub ParseNagiosCheckResult
{
	my $return_code = undef;
	my $status_string = undef;
	my $previous = undef;
	foreach (@nagios_check_results) 
	{
		my $current = $_;
				
		# Determine le code de sortis du script en fonction du status le plus critique retourné par les checks . 
		switch($current->[0]) 
		{
         		case /CRITICAL/ 
         		{	
				$return_code = $current->[0];
			}
			case /WARNING/ 
			{
				if(!defined($return_code) || $return_code ne 'CRITICAL') 
				{
					$return_code = $current->[0]
				}				
			}
			case /UNKNOWN/ 
			{
				if(!defined($return_code) || $return_code ne 'CRITICAL' && $return_code ne  'WARNING') 
				{
					$return_code = $current->[0]
				}				
			}
			case /OK/ 
			{
				if(!defined($return_code) || $return_code ne 'CRITICAL' && $return_code ne  'WARNING' && $return_code ne  'UNKNOWN' ) 
				{
					$return_code = $current->[0]
				}				
			}	
		}
								
		#Construit les données de perfomances pour les graphiques centreon si disponible 						
		if(defined($current->[2])) 
		{	
			my @perfdata = split(/!/, $current->[2]);		
			$nagios_plugin->add_perfdata(label    => $perfdata[0],
						     value    => $perfdata[1],
						     uom      => $perfdata[2],  
						     warning  => $perfdata[3],
						     critical => $perfdata[4],
						     min      => $perfdata[5],
					             max      => $perfdata[6]);
		}		
		
		my $current_stat = $current->[1];
		
		
				
		# Determine le premier status a afficher dans la vue centreon en fonction du status 
		# Moche et fonctionel. Todo : à simplifié.  
		if(!defined($status_string)) 
		{
			$status_string = "$current_stat";		
		}
		elsif($current->[0] =~ /CRITICAL/) 
		{

			$status_string = "$current_stat $status_string";
		}
		elsif($current->[0] =~ /WARNING/ && $status_string !~ /CRITICAL/) 
		{
			if($previous =~ /CRITICAL/) 
			{
				$status_string = "$status_string $current_stat";
			}
			else 
			{
				$status_string = "$current_stat $status_string";
			}			
		}
		elsif($current->[0] =~ /UNKNOWN/ && $status_string !~ /CRITICAL/ || /WARNING/) 
		{
			$status_string = "$current_stat $status_string";
		}
		else 
		{
			$status_string = "$status_string  $current_stat";	
		}
		$previous = $return_code;
	}
	
	#Regex FTW
	$status_string =~ s/\. /\n/;
	
	
	# Final : retour du script. 		
	$nagios_plugin->nagios_exit($return_code, $status_string);	
}

#####################################################################################################################################
#####################################################################################################################################
#####################################################################################################################################
package SQL_WORKER;

use strict;
use warnings;
use DBI;
use Nagios::Plugin;


sub DbConnect;
sub CloseConnexion;
sub ProcessSQLQuery;

# Constructeur
sub new 
{
	my ($class, $ref_arguments) = @_;	
	$class = ref($class) || $class;
	
	my $this = {};
	
	bless($this, $class);  
	
	$this->{_NAGIOS_PLUGIN}		= $ref_arguments->{nagios_plugin};
	$this->{_DB_INSTANCE}		= $ref_arguments->{db_instance};
	$this->{_DB_USERNAME}		= $ref_arguments->{db_username};
	$this->{_DB_PASSWORD}		= $ref_arguments->{db_password};
	$this->{DB_HANDLE}		= undef;						      	 
	return $this;
}

sub DESTROY 
{
	my $this = shift;
	return;
}


# Se connecte et verifie la connexion a la base de données . 
sub DbConnect
{	
	my $this = shift;
	$this->{DB_HANDLE} = DBI->connect('dbi:Oracle:' . $this->{_DB_INSTANCE}, $this->{_DB_USERNAME}, $this->{_DB_PASSWORD}, {PrintError => 0});
	
	# Si la connexion échoue pour une quelquonque raison, DB_HANDLE est 'undef'
	if(!defined($this->{DB_HANDLE})) 
	{
		$this->{_NAGIOS_PLUGIN}->nagios_exit(CRITICAL, "Impossible de se connecté à la base de données : $DBI::errstr \n");
	}
			
	return $this->{DB_HANDLE};
}

# Execute les requete sql et retourne l'object *sql_query* de façon generique pour ensuite être
# inteprété par le check ( fetch / fetchrow_array etc .. ) . 
sub ProcessSQLQuery
{	
	my ($this, $args) = @_;	
	my $sql_query = $this->{DB_HANDLE}->prepare($args);
	# Execute la requete
	$sql_query->execute or die "SQL Error: $DBI::errstr\n";	
	return $sql_query;
}

# Ferme la connexion a la base de donnée une fois les traitements terminés . 
sub CloseConnexion 
{
	my $this = shift;
	$this->{DB_HANDLE}->disconnect or warn $DBI::errstr;
}



#####################################################################################################################################
#####################################################################################################################################
######################################################################################################################################
package CHECK_ORACLE_STRATUP_TIME;

use DateTime;
use strict;
use warnings;

sub ProcessCheck;
sub ProcessCheckResult;


use vars qw($hostname $instance $status $date);

sub new 
{
	my ($class, $ref_arguments) = @_;
	$class = ref($class) || $class;
	
	my $this = {};
	bless($this, $class);
	
	
	$this->{_DB_HANDLE}	= $ref_arguments->{db_handle};
	$this->{_COMANDE}	= $ref_arguments->{command};
	$this->{_SQL_QUERIE}	= q{ select host_name, instance_name, status, to_char(startup_time,'[DD-MM-YYYY] HH24:MI:SS ') from v$instance };
	
	return $this;
}

sub ProcessCheck
{
	my $this = shift;
	my $queryresult;	
	$queryresult = $this->{_DB_HANDLE}->ProcessSQLQuery($this->{_SQL_QUERIE});		
	$queryresult->bind_columns(undef,\$hostname, \$instance, \$status, \$date);
        $queryresult->fetch();
        $queryresult->finish();            
        ProcessCheckResult();       
}


sub ProcessCheckResult
{	
	my $currentDate = DateTime->now(time_zone => 'local');
	
	my @tocheck_0 = split(/ /, $date);
	my $tocheck_1 = $tocheck_0[0];
	my $return_code = undef;
	
	$tocheck_1 = substr $tocheck_1, 1;
	$tocheck_1 = substr $tocheck_1, 0, 10;
	  
	if($tocheck_1 ne $currentDate->dmy) 
	{
		$return_code = 'CRITICAL';		
	}
	else 
	{
		$return_code = 'OK';
	}
		
	push(@::nagios_check_results, [$return_code, "Database date is : $date. ", undef]);
	
}

#####################################################################################################################################
#####################################################################################################################################
######################################################################################################################################
package CHECK_ORACLE_CONNECTED_USERS;

use strict;
use warnings;

use vars qw(@result);

sub ProcessCheck;
sub ProcessCheckResult;

sub new
{
	my ($class, $ref_arguments) = @_;
	$class = ref($class) || $class;
	
	my $this = {};
	bless($this, $class);
	
	
	$this->{_DB_HANDLE}	= $ref_arguments->{db_handle};
	$this->{_COMANDE}	= $ref_arguments->{command};
	$this->{_SQL_QUERIE}	= q{ SELECT COUNT(*) FROM v$session WHERE type = 'USER' };
	
	return $this;

}

sub ProcessCheck
{
	my $this = shift;
	my $queryresult;
	$queryresult = $this->{_DB_HANDLE}->ProcessSQLQuery($this->{_SQL_QUERIE});	
	@result = $queryresult->fetchrow_array();	
        $queryresult->finish();	      
        ProcessCheckResult($this->{_COMANDE});      
}

sub ProcessCheckResult
{	
	my ($arg) = @_;
	my $return_code = undef;
	
	if($arg =~ /:/) 
	{
		my @range = split(/:/, $arg);
		my $warn = $range[1];
		my $crit = $range[2];
		my $perf_data = 'connected-users!' . $result[0] . '!a!' . $warn . '!'. $crit . '!!';
		
		if($result[0] >= $crit)	
		{	
			$return_code = 'CRITICAL';				
		}
		elsif($result[0] >= $warn) 
		{
			$return_code = 'WARNING';	
		}
		else 
		{
			$return_code = 'OK';			
		}
		push(@::nagios_check_results, [$return_code, "$result[0] connected users. ", $perf_data]);						 
	}
	else 
	{
		push(@::nagios_check_results, ['OK', "$result[0] connected users. ", undef]);
	}
	
}

#####################################################################################################################################
#####################################################################################################################################
######################################################################################################################################
package CHECK_ORACLE_PROCESS_USAGE;

use strict;
use warnings;
use POSIX;

use vars qw(@result);

sub ProcessCheck;
sub ProcessCheckResult;

sub new
{	
	my ($class, $ref_arguments) = @_;
	$class = ref($class) || $class;
	
	my $this = {};
	bless($this, $class);
		
	$this->{_DB_HANDLE}	= $ref_arguments->{db_handle};
	$this->{_COMANDE}	= $ref_arguments->{command};
	$this->{_SQL_QUERIE}	= q{ SELECT current_utilization/limit_value*100 FROM v$resource_limit WHERE resource_name LIKE '%processes%' };
	
	return $this;
}


sub ProcessCheck
{
	my $this = shift;
	my $queryresult;

	$queryresult = $this->{_DB_HANDLE}->ProcessSQLQuery($this->{_SQL_QUERIE});	
	@result = $queryresult->fetchrow_array();	
        $queryresult->finish();	
        
        ProcessCheckResult($this->{_COMANDE});
}


sub ProcessCheckResult
{
	my $rounded = undef;
	my $return_code = undef;
	my($arg) = @_;
	
	$result[0] =~ s/,/./m;
	$rounded = ceil($result[0]); # Arrondis nombre a virgule a l'entier superieur .
	
	if($arg =~ /:/) 
	{		
		my @range = split(/:/, $arg);
		my $warn = $range[1];
		my $crit = $range[2];
		my $perf_data = 'process-usage!' . $rounded . '!c!' . $warn . '!'. $crit . '!0!100';
		
		if($rounded >= $crit) 
		{	
			$return_code = 'CRITICAL';			
		}
		elsif($rounded >= $warn) 
		{
			$return_code = 'WARNING';
		}
		else 
		{
			$return_code = 'OK';
		}
		push(@::nagios_check_results, [$return_code, " Process Usage : $rounded%. ", $perf_data]);						 
	}
	else 
	{
		$rounded = ceil($result[0]);
		push(@::nagios_check_results, ['OK', " Process Usage : $rounded%. ", undef]);
	}	
}


#####################################################################################################################################
#####################################################################################################################################
######################################################################################################################################
package CHECK_ORACLE_TABLESPACE_USAGE;

use strict;
use warnings;

use vars qw($oracle_version @result);

sub GetOracleVersion;
sub ProcessCheck;

sub new
{
	my ($class, $ref_arguments) = @_;
	$class = ref($class) || $class;
	
	my $this = {};
	bless($this, $class);
	
	
	$this->{_DB_HANDLE}	= $ref_arguments->{db_handle};
	$this->{_COMANDE}	= $ref_arguments->{command};
	return $this;	
}


sub GetOracleVersion
{
	my $this = shift;
	my $queryresult;		
	$queryresult = $this->{_DB_HANDLE}->ProcessSQLQuery(q{SELECT version FROM v$instance});	
	my @result = $queryresult->fetchrow_array();	
        $queryresult->finish();	 
        my $longversion = $result[0];      
        my $index = index( $longversion, '.');      
        $oracle_version = substr($longversion, 0, $index);     
}


sub ProcessCheck
{
	
	
	my $sql_query = undef;
	my $this = shift;
	$this->GetOracleVersion();
	my @tablespaces_objects = undef;
	
	switch($oracle_version)
	{
		case '10'
		{
			$sql_query = q{
					select
						fs.tablespace_name                          "Tablespace",
						(df.totalspace - fs.freespace)              "Used MB",
						fs.freespace                                "Free MB",
						df.totalspace                               "Total MB",
						round(100 * (fs.freespace / df.totalspace)) "Pct. Free"
					from
						(select
							tablespace_name,
							round(sum(bytes) / 1048576) TotalSpace
						from
							dba_data_files
						group by
							tablespace_name
						) df,
						(select
							tablespace_name,
							round(sum(bytes) / 1048576) FreeSpace
						from
							dba_free_space
						group by
							tablespace_name
						) fs
					where
						df.tablespace_name = fs.tablespace_name
					and 
						df.tablespace_name = 
					};	
			
			my $arg = $this->{_COMANDE};
			if(defined($arg))  #  e.g   tablespace-usage:[AO_INDX*65*80%AO_DATA*65*90]
			{
				my @commands = split(/:/, $arg);
				my $tablespace_command = $commands[1];
				if(defined($tablespace_command)) 
				{
					if($tablespace_command =~ /\[/)  # Multiple tablespace 
					{
						$tablespace_command =~ s/\[//;
						$tablespace_command =~ s/\]//;
						@tablespaces_objects = split(/%/, $tablespace_command);						
					}
					else # Single tablespace
					{
						push(@tablespaces_objects, $tablespace_command);
					}
				}
				else 
				{
					die; # todo : supression , controls des arguments en amont . 
				}
				
				
				foreach(@tablespaces_objects)
				{
					my $current_tablespace_object = $_;
					my @decomp_object = split(/\*/, $current_tablespace_object);
					my $tocheck = $sql_query . "'" . $decomp_object[0] . "'";
					my $queryresult = $this->{_DB_HANDLE}->ProcessSQLQuery($tocheck);	
					@result = $queryresult->fetchrow_array();					
					$queryresult->finish();
					
					
					
					ProcessCheckResult("tablespace-usage:$decomp_object[0]:$decomp_object[1]:$decomp_object[2]"); 				
				}								
			}
		}
	}             
}


sub ProcessCheckResult
{
	my $rounded = undef;
	my $return_code = undef;
	my $perf_data = undef;
	my($arg) = @_;
	
	$rounded = 100 - $result[4];
	
	
	
	if($arg =~ /:/) 
	{
		my @range = split(/:/, $arg);
		my $warn = $range[2];
		my $crit = $range[3];
		
		$perf_data = "tablespace-usage-$result[0]!" . $rounded . '!c!' . $warn . '!'. $crit . '!0!100';
		
		
		
		if($rounded >= $crit) 
		{		
			$return_code = 'CRITICAL';
		}
		elsif($rounded >= $warn) 
		{
			$return_code = 'WARNING';
		}
		else 
		{
			$return_code = 'OK';
		}	
		push(@::nagios_check_results, [$return_code, "Tablespace $result[0] Usage : $rounded%. ", $perf_data]);		
	}
	else 
	{
		
		push(@::nagios_check_results, ['OK', "Tablespace $result[0] : $rounded%. ", undef]);
	}
		
}
