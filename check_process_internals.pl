#! /usr/bin/perl -w 

use Switch;
use Win32::OLE('in');
use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use Nagios::Plugin;
use Data::Dumper;

use constant wbemFlagReturnImmediately => 0x10;
use constant wbemFlagForwardOnly => 0x20;

##############################
### Variables Declarations ###
##############################
use vars qw($Nagios_plugin $plugin_usage $plugin_version);
use vars qw($process_name $long_arguments $long_exclusions @xregex_rules);
use vars qw(@arguements_array @exclusions_array);
use vars qw(@pid_list_to_check);
use vars qw($WQL_Wrapper);
use vars qw(@check_results);
##############################


############################
### Methods Declarations ###
############################exists {map { $_ => 1 } @array}->{$X}exists {map { $_ => 1 } @array}->{$X}
sub ProcessCommandsLines;
sub ProcessChecks;
sub CheckMemUsage;
sub CheckCpuUsage;
sub BuildPidList;
sub xRegexWork;
sub ProcessChecksResults;
############################




###################
### Entry Point ###
###################

$plugin_version = 0.2;
$plugin_usage = "Usage: %s \n[-p|--process=<process.exe>]\n".
		"  --The processuce name to check e.g firefox.exe\n" .
		"[-a|--argument=<args>]\n".
		"  --Arguement <mem> <cpu>\n" . 
	        "[-e|--exclusion=<pid> ]\n" .
	        "  --Exclusion list of pid separated by : e.g <542:444:3256>\n" .
	        "[-x|--xregex=<value>]\n" .
	        "  --Regex for the convivial name of the process independently of his pid\n" .
	        "Use a part of the command line of the parent process for unique identity\n" .
	        'e.g  --xregex="windows\Explorer.EXE:Firefox Spwned by Explorer"';

# -x match:regex                                                    
# --xregex="windows\Explorer.EXE:Firefox Spwned by Explorer|"
# Determine le nom convivial du processuce independament de son pid. 
# Prend comme valeur fixe une partis de la ligne de commande du process parent . 

# Constructions du plugin nagios . 
$Nagios_plugin = Nagios::Plugin->new(  
	usage     => $plugin_usage,
	version   => $plugin_version,
	plugin    => 'Process_internals',
	timeout   => 15);
	

# Ajout des arguements ./ 	
$Nagios_plugin->add_arg(spec => 'process|p=s',
			help => "--process\n The process Name to Check",
			required => 1);
			
$Nagios_plugin->add_arg(spec => 'arguments|a=s',
			help => "--arguments\n Argument to process",
			required => 1);
			
$Nagios_plugin->add_arg(spec => 'exclusions|e=s',
			help => "--exclusions\n Pid Exclusion in case of multiple process with same name",
			required => 0);
			
$Nagios_plugin->add_arg(spec => 'xregex|x=s',
			help => "Extraction rules for process convivial naming",
			required => 0);
			
$Nagios_plugin->getopts;


# WORK ENTRY

ProcessCommandsLines();

$WQL_Wrapper =  Win32::OLE->GetObject("winmgmts:\\\\127.0.0.1\\root\\CIMV2") 
	or 
$Nagios_plugin->nagios_exit(CRITICAL, "Can't get wmi root object ."); 

  
ProcessChecks();

sub ProcessCommandsLines
{
	my @array = undef;
	$process_name = $Nagios_plugin->opts->process;
	$long_arguments = $Nagios_plugin->opts->arguments;
	$long_exclusions = $Nagios_plugin->opts->exclusions;	
	my $xregex = $Nagios_plugin->opts->xregex;
	
	
	if($long_arguments =~ /\|/) 
	{
		@array = split(/\|/, $long_arguments);
	}
		
	
	if($array[1])
	{
		foreach(@array) 
		{
			my $current = $_;
			my @object = undef;
			if($current =~ m/:/) 
			{
				@object = split(/:/, $current);	
				if(!looks_like_number($object[1]) || !looks_like_number($object[2])) 
				{
					$Nagios_plugin->nagios_exit(UNKNOWN, "Range warn 'n critical must be numeric ");
				}
				push(@arguements_array, [@object]);					
			}
			else 
			{
				$Nagios_plugin->nagios_exit(UNKNOWN, "Range must be defined");
			}
		}
	}
	else
	{
		my @obj = undef;
		
		if($long_arguments =~ /:/) 
		{
			@obj = split(/:/, $long_arguments);	
			if(!looks_like_number($obj[1]) || !looks_like_number($obj[2])) 
			{
				$Nagios_plugin->nagios_exit(UNKNOWN, "Range warn 'n critical must be numeric ");
			}
			push(@arguements_array, [@obj]);	
		}
		else 
		{
			$Nagios_plugin->nagios_exit(UNKNOWN, "Range must be defined");
		}
		
	}
	
	if(defined($long_exclusions))
	{	
		if($long_exclusions =~ m/:/) 
		{
			@exclusions_array = split(/:/, $long_exclusions);
			foreach(@exclusions_array) 
			{
				my $current = $_;
				if(!looks_like_number($current)) 
				{
					$Nagios_plugin->nagios_exit(UNKNOWN, "Exclusion must be defined as numerical pid");
				}
			}
		}
	}
	
	
	
	if(defined($xregex))
	{
		my @regex_rules_object = split(/\|/, $xregex);
		foreach my $object(in @regex_rules_object) 
		{
			my @final_obj = split(/:/, $object);
			if(!defined($final_obj[0]) || !defined($final_obj[1])) 
			{
				$Nagios_plugin->nagios_exit(UNKNOWN, "Invalide regex rules");
			}
			else 
			{
				push(@xregex_rules, [@final_obj]);
			}
		}		
	}				
}




sub ProcessChecks
{
	BuildPidList();
	foreach(@arguements_array)
	{
		my $object_command = $_;
		switch($object_command->[0])
		{
			case /mem/
			{
				CheckMemUsage($object_command);
			}
			case /cpu/
			{
				CheckCpuUsage($object_command);
			}
		}
	}	
	ProcessChecksResults();
	
}

sub CheckCpuUsage
{
	my ($args) = @_;
	my $warn = $args->[1];
	my $crit = $args->[2];
	
	my $memory_check_query = q{
		SELECT
			PercentProcessorTime
		FROM
			Win32_PerfFormattedData_PerfProc_Process
		WHERE
			IDProcess='};
	
	foreach(@pid_list_to_check)
	{
		my $current = $_;
		my $process_cpu_usage = undef;
		my $check_return_code = undef;
		my $check_perf_data = undef;	
		my $process_convivial_name = undef;
					
		my $query_result = $WQL_Wrapper->ExecQuery($memory_check_query . $current->[0] . "'", 'WQL', wbemFlagReturnImmediately | wbemFlagForwardOnly);
		if(!defined($query_result))
		{
			$Nagios_plugin->nagios_exit(UNKNOWN, "Can't execute query : $memory_check_query");
		}		
		foreach my $res(in $query_result) 
		{
			$process_cpu_usage = $res->{PercentProcessorTime};
		}
		
		
		if(@xregex_rules) 
		{
			$process_convivial_name = xRegexWork($current->[1]);
		}
		else
		{
			$process_convivial_name = $current->[0];
		}
		
				
		$check_perf_data = 'cpu-usage-' . $process_convivial_name . '!' . $process_cpu_usage . '!c!' . $warn .'!' . $crit . '!0!100';		
		if($process_cpu_usage >= $crit) 
		{
			$check_return_code = "CRITICAL";	
		}
		elsif($process_cpu_usage >= $warn) 
		{
			$check_return_code = "WARNING";
		}
		else 
		{
			$check_return_code = "OK";
		}		
		push(@check_results, [$check_return_code, "($process_convivial_name : " .  $current->[0] . " - Cpu Usage: $process_cpu_usage %)", $check_perf_data]);				
	}	
}

sub CheckMemUsage
{	
	my ($args) = @_;
	my $warn = $args->[1];
	my $crit = $args->[2];
		
	my $memory_check_query = q{
		SELECT 
			WorkingSet 
		FROM 
			Win32_PerfFormattedData_PerfProc_Process 
		WHERE 
			IDProcess='};
		
		
	foreach(@pid_list_to_check)
	{
		my $current = $_;
		my $process_memory = undef;
		my $check_return_code = undef;
		my $check_perf_data = undef;
		my $process_convivial_name = undef;
				
		my $query_result = $WQL_Wrapper->ExecQuery($memory_check_query . $current->[0] . "'", 'WQL', wbemFlagReturnImmediately | wbemFlagForwardOnly);
		if(!defined($query_result)) 
		{
			$Nagios_plugin->nagios_exit(UNKNOWN, "Can't execute query : $memory_check_query");
		}
		
		foreach my $res(in $query_result) 
		{
			$process_memory = $res->{WorkingSet};
		}
		
		
		
		
		if(@xregex_rules) 
		{
			$process_convivial_name = xRegexWork($current->[1]);
		}
		else 
		{
			$process_convivial_name = $current->[0];
		}
			
		$process_memory = $process_memory/1024/1024;  # Taille en Mb
		$process_memory = int($process_memory + 0.5); # Arondis au dixieme . 
		
		$check_perf_data = 'memory-used-' . $process_convivial_name . '!' . $process_memory . '!a!' . $warn .'!' . $crit . '!!';
		
		
		if($process_memory >= $crit) 
		{
			$check_return_code = "CRITICAL";	
		}
		elsif($process_memory >= $warn) 
		{
			$check_return_code = "WARNING";
		}
		else 
		{
			$check_return_code = "OK";
		}
		
		push(@check_results, [$check_return_code, "($process_convivial_name : " . $current->[0] . " - Memory Used: $process_memory Mb) ", $check_perf_data]);									
	}
}

sub BuildPidList
{	
        # Obtiens la list des processuces .
	my @process_list = $WQL_Wrapper->ExecQuery(q{SELECT * FROM Win32_Process}, 'WQL', wbemFlagReturnImmediately | wbemFlagForwardOnly); 	
	foreach(@process_list) 
	{
		foreach my $ok(in $_) 
		{
			# Verifie le pid avec la list des exclusion et place le pid dans la list .
			if(!exists { map { $_ => 1 } @exclusions_array}->{$ok->{ProcessId}} && $ok->{Name} eq $process_name)  
			{
				push(@pid_list_to_check, [$ok->{ProcessId}, $ok->{ParentProcessId}]); #obj(pid,parentpid)
			}
		}
	}
	
	if(!@pid_list_to_check) 
	{       #Controle si la list des pid est vide (dans ce cas le processuce n'existe pas)
		$Nagios_plugin->nagios_exit(CRITICAL, "There no $process_name process(s) to check.");
	}
}


# Dbleh
sub xRegexWork
{
	 my ($arg) = @_;	
 	 my $query = q{SELECT * FROM Win32_Process};
		
	 my @result = $WQL_Wrapper->ExecQuery($query, 'WQL', wbemFlagReturnImmediately | wbemFlagForwardOnly);
	 foreach(@result) 
	 {
		foreach my $proc(in $_) 
		{
			if($arg eq $proc->{ProcessId}) 
			{
				foreach (@xregex_rules) 
				{	
				        my $cmdline = $proc->{CommandLine};
				        my $rls = $_->[0];
					if($cmdline =~ m/\Q$rls\E/)  # Regex ftw \Q <= \E  "Anti '\' nextmetachar"
					{
						return $_->[1];
					}
				}
			}
		}
	 }
	return $arg;
}

sub ProcessChecksResults
{
	my $return_code = undef;
	my $status_string = undef;
	my $previous = undef;
		
	foreach(@check_results)
	{
		my $current = $_;
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
		
		
		if(defined($current->[2])) 
		{	
			my @perfdata = split(/!/, $current->[2]);		
			$Nagios_plugin->add_perfdata(label    => $perfdata[0],
						     value    => $perfdata[1],
						     uom      => $perfdata[2],  
						     warning  => $perfdata[3],
						     critical => $perfdata[4],
						     min      => $perfdata[5],
					             max      => $perfdata[6]);
		}		
		
		my $current_stat = $current->[1];
				
		# Determine le premier status a afficher dans la vue centreon en fonction du status 
		if(!defined($status_string)) 
		{
			$status_string = "$current_stat \n";		
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
	
	$status_string =~ s/\. /\n/;   #Regex FTW		
	$Nagios_plugin->nagios_exit($return_code, '['. $process_name . '] ' . $status_string);				
}