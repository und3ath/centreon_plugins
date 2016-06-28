#! /usr/bin/perl -w
use strict;
use warnings;
use Nagios::Plugin;
use Data::Dumper;

# Pour les fonctions propre au snmp nagios 
require "/usr/lib64/nagios/plugins/Centreon/SNMP/Utils.pm";

use vars qw($nagios_plugin %return_code %snmp_opts);
use vars qw(%variable_array %variable_valides);
use vars qw(@volumes_index);
use vars qw(@volumes_infos);
use vars qw($dfVolName $df64TotalKBytes $df64UsedKBytes);
use vars qw($hostname $warn_thres $crit_thres $perftype);
use vars qw(@critical_ @warning_ @ok_);
use vars qw($exit_code $exit_string);


%return_code = (
	'OK' => 0,
        'WARNING' => 1, 
        'CRITICAL' => 2, 
        'UNKNOWN' => 3);
        

# Oid's def. 
$dfVolName = ".1.3.6.1.4.1.789.1.5.4.1.2";
$df64TotalKBytes = ".1.3.6.1.4.1.789.1.5.4.1.29"; 
$df64UsedKBytes = ".1.3.6.1.4.1.789.1.5.4.1.30";


$nagios_plugin = Nagios::Plugin->new(
	shortname	=> 'Netapp',
	usage 		=> "",
	version 	=> '0.1',
	plugin		=> $0,
	timeout		=> 10);
	

$nagios_plugin->add_arg(
	spec		=>	'hostname|H=s',
	help		=>	"-H, --hostname \n The hostname",
	required	=> 	1);
	
$nagios_plugin->add_arg(
	spec 		=> 	'perftype|p=s',
	help 		=> 	"-p, --perftype \n Perf data type",
	required	=>	1);
		
$nagios_plugin->add_arg(
	spec		=>	'warning|w=s',
	help		=>	"-w, --warning \n The warning threshold",
	required	=> 	1);
	
	
$nagios_plugin->add_arg(
	spec		=>	'critical|c=s',
	help		=> 	"-c, --critical \n The critical threshold",
	required	=> 	1);
	

	
$nagios_plugin->getopts;
$hostname = $nagios_plugin->opts->hostname;
$warn_thres = $nagios_plugin->opts->warning;
$crit_thres = $nagios_plugin->opts->critical;
$perftype = $nagios_plugin->opts->perftype;


# Hash-def snmp options
%snmp_opts = (
    "host" => $hostname,
    "snmp-community" => "public",
    "snmp-version" => 2,
    "snmp-port" => 161, 
    "snmp-auth-key" => undef,
    "snmp-auth-user" => undef,
    "snmp-auth-password" => undef,
    "snmp-auth-protocol" => "MD5",
    "snmp-priv-key" => undef,
    "snmp-priv-password" => undef,
    "snmp-priv-protocol" => "DES",
    "maxrepetitions" => undef,
    "64-bits" 	=> 1 # Pour les valeurs depassants 32 bytes #
);
 

my($session_params) = Centreon::SNMP::Utils::check_snmp_options($return_code{'UNKNOWN'}, \%snmp_opts); 
my $session = Centreon::SNMP::Utils::connection($return_code{'UNKNOWN'}, $session_params);
$session->max_msg_size(4096);

# One shot collecting ( more efficient ) 
my $table_volume_name = Centreon::SNMP::Utils::get_snmp_table($dfVolName, $session, $return_code{'UNKNOWN'}, \%snmp_opts);
my $table_volume_bytesTotal = Centreon::SNMP::Utils::get_snmp_table($df64TotalKBytes, $session, $return_code{'UNKNOWN'}, \%snmp_opts);
my $table_volume_bytesUsed = Centreon::SNMP::Utils::get_snmp_table($df64UsedKBytes, $session, $return_code{'UNKNOWN'}, \%snmp_opts);

# Comput results
foreach my $key (oid_lex_sort(keys %$table_volume_name)) {
    my $index = rindex($key, ".");
    my $indexStr = substr($key, $index + 1);
    
    # Si volum snapshot ou .. => ignoré . 
    if ($table_volume_name->{$key} =~ m/\.snapshot/ or $table_volume_name->{$key} =~ m/\.\./) { 
	next;
    }
       
    # Dat ugly tricks
    my $bytesTotal = $table_volume_bytesTotal->{$df64TotalKBytes . "." . $indexStr};
    my $bytesUsed = $table_volume_bytesUsed->{$df64UsedKBytes . "." . $indexStr};
    push(@::volumes_infos, [$table_volume_name->{$key}, $bytesTotal, $bytesUsed, $bytesTotal - $bytesUsed]);
}


foreach(@volumes_infos) {
	
	# 1) Transformation unitaire 
	my $current = $_;
	my $totalSize = scaleIt($current->[1]);
	my $usedSize = scaleIt($current->[2]);
	my $available = scaleIt($current->[3]);
	
	# 2) Array valeur/uom 
	my @total = split(" ", $totalSize);
	my @used = split(" ", $usedSize);
	
	# 3) Calcule le pourcentage d'utilisation
	my $percentage = undef;
	$percentage = ($current->[2] / $current->[1]) * 100;
	$percentage = sprintf("%0.2f", $percentage);
	
	# 4) Formate la chaine de status
	my $computedString =  $current->[0] . " Total: $totalSize  Used: $usedSize  Available: $available ($percentage%)\n";
	
	# 5) Drop la chaine dans l'array correspondant en fonction du status
	if($percentage >= $crit_thres) {
		push(@::critical_, [$computedString, $percentage]);
	}
	elsif($percentage >= $warn_thres) {
		push(@::warning_, [$computedString, $percentage]);
	}
	else {
		push(@::ok_, [$computedString, $percentage]);
	}
	
	# 6) Construction des données de perfomances 			
	if($perftype eq "percent") {
		$nagios_plugin->add_perfdata(
			label 	=> $current->[0],
			value	=> $percentage,
			uom 	=> '%',
			warning => $warn_thres,
			critical=> $crit_thres);
	}	
	elsif($perftype eq "sized") {
		my @sizeScaledGB = split(" ", scaleToGB($current->[1]));
		my @usedScaledGB = split(" ", scaleToGB($current->[2]));
		
		my $warnBasedOnsize = $current->[1] * ($warn_thres / 100);
		my @warnScalledGB = split(" ", scaleToGB($warnBasedOnsize));
		
		my $critBasedOnsize = $current->[1] * ($crit_thres / 100);
		my @critScalledGB = split(" ", scaleToGB($critBasedOnsize));
		
		$nagios_plugin->add_perfdata(
			label	=> $current->[0],
			value	=> @usedScaledGB[0],
			uom	=> @usedScaledGB[1],
			warning => @warnScalledGB[0],
			critical=> @critScalledGB[0],
			min 	=> 0,
			max	=> @sizeScaledGB[0]);
		
	}				
}

$exit_code = 0;

if(scalar(grep {defined $_} @critical_) > 0) {
	$exit_code = 2;
	@critical_ = sort { $b->[1] <=> $a->[1] } @critical_;
	foreach(@critical_) {
		$exit_string .= $_->[0];
	}
	$exit_string .= "\n";
}
if(scalar(grep {defined $_} @warning_) > 0) {
	if($exit_code < 2) {
		$exit_code = 1;
	}
	@warning_ = sort { $b->[1] <=> $a->[1] } @warning_;
	foreach(@warning_) {
		$exit_string .= $_->[0];
	}
	$exit_string .= "\n";
}
if(scalar(grep {defined $_} @ok_) > 0) {	
	if($exit_code < 1) {
		$exit_code = 0;
	}
	@ok_ = sort { $b->[1] <=> $a->[1] } @ok_;
	foreach(@ok_) {
		$exit_string .= $_->[0];
	}
	$exit_string .= "\n";
}

$nagios_plugin->nagios_exit($exit_code, $exit_string);

# Conversion bytes en unité approprié la plus fine . 
sub scaleIt {
    my( $size, $n ) = ( shift, 0 );
    ++$n and $size /= 1024 until $size < 1024;
    return sprintf "%.2f %s", $size, ( qw[ bytes KB MB GB TB ] )[ $n +1 ];
}


# Conversion de bytes en GB 
sub scaleToGB {
	my ($size, $n) = (shift , 0);
	my $kilo = $size/1024;
	my $mega = $kilo/1024;
	my $giga = $kilo/1024;
	return sprintf("%.2f GB", $giga);
}





