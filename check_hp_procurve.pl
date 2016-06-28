#! /usr/bin/perl -w 

use strict;
use Switch 'Perl6';

require "/usr/lib64/nagios/plugins/Centreon/SNMP/Utils.pm";

use vars qw($PROGNAME);
use Getopt::Long;
use vars qw($opt_h $opt_V $opt_n $opt_a $opt_w $opt_c $opt_f %centreon $proc_run $port_status $result $result_table %resultarray);

# Nagios Specifique
my %ERRORS = ('OK' => 0, 'WARNING' => 1, 'CRITICAL' => 2, 'UNKNOWN' => 3);
my %centreon = Centreon::SNMP::Utils::load_oids($ERRORS{'UNKNOWN'}, "/usr/lib64/nagios/plugins/centreon.conf");

$PROGNAME = $0;
sub print_help();
sub print_usage();
sub check_hardware();
sub check_port();


my %OPTION = (
    "host" => undef,
    "snmp-community" => "public", "snmp-version" => 1, "snmp-port" => 161, 
    "snmp-auth-key" => undef, "snmp-auth-user" => undef, "snmp-auth-password" => undef, "snmp-auth-protocol" => "MD5",
    "snmp-priv-key" => undef, "snmp-priv-password" => undef, "snmp-priv-protocol" => "DES",
    "maxrepetitions" => undef,
    "64-bits" => undef
);

Getopt::Long::Configure('bundling');
GetOptions (
    "H|hostname|host=s"         => \$OPTION{'host'},
    "C|community=s"             => \$OPTION{'snmp-community'},
    "v|snmp|snmp-version=s"     => \$OPTION{'snmp-version'},
    "P|snmpport|snmp-port=i"    => \$OPTION{'snmp-port'},
    "u|username=s"              => \$OPTION{'snmp-auth-user'},
    "authpassword|password=s"   => \$OPTION{'snmp-auth-password'},
    "k|authkey=s"               => \$OPTION{'snmp-auth-key'},
    "authprotocol=s"            => \$OPTION{'snmp-auth-protocol'},
    "privpassword=s"            => \$OPTION{'snmp-priv-password'},
    "privkey=s"                 => \$OPTION{'snmp-priv-key'},
    "privprotocol=s"            => \$OPTION{'snmp-priv-protocol'},
    "maxrepetitions=s"          => \$OPTION{'maxrepetitions'},
    "64-bits"                   => \$OPTION{'64-bits'},
    
    "h"   => \$opt_h, "help"         => \$opt_h,
    "V"   => \$opt_V, "version"      => \$opt_V,
    "n=s" => \$opt_n, "variable"     => \$opt_n,
    "a=s" => \$opt_a, "arguments=s"  => \$opt_a,
    "f=s" => \$opt_f, "fault=s"      => \$opt_f,
    "w=s" => \$opt_w, "warning=s"    => \$opt_w,
    "c=s" => \$opt_c, "critical=s"   => \$opt_c);
    
    
    
if ($opt_h)
{
    print_help();
    exit $ERRORS{'OK'};
}


if (!$opt_n) 
{
    print "Argument : -n requiered \n\n";
    print_usage();
    exit $ERRORS{'OK'};
}

%centreon = Centreon::SNMP::Utils::load_oids($ERRORS{'UNKNOWN'}, "/usr/lib64/nagios/plugins/centreon.conf");



my $variable = $opt_n;

given($variable)
{
    when("hardware")
    {
        check_hardware();
    }
    when("port")
    {
        check_port();
    }
}

  
exit;
    
    
    
 

 
 
sub check_port()
{   
    
    $port_status = "";
    
    if(!defined($opt_a))
    {
        print "Argument -a is requiered with the port variable \n\n";
        print_usage();
    }
    
    
    my $hp_ifdesc_ports_entry = "1.3.6.1.2.1.2.2.1.2";
    my $hp_dot1stp_port_stat  = "1.3.6.1.2.1.17.2.15.1.3";
    my $hp_ifoper_status      = "1.3.6.1.2.1.2.2.1.8";
     
    my %port_list;  
    
    my $result_index;
 
    my ($session_params) = Centreon::SNMP::Utils::check_snmp_options($ERRORS{'UNKNOWN'}, \%OPTION);    
    my $session = Centreon::SNMP::Utils::connection($ERRORS{'UNKNOWN'}, $session_params);  
     
    $result_table = Centreon::SNMP::Utils::get_snmp_table($hp_ifdesc_ports_entry, $session, $ERRORS{'UNKNOWN'}, \%OPTION);
     
    foreach my $key (oid_lex_sort(keys %$result_table))
    {
        my @result_list = split (/\./, $key);
        $resultarray{$$result_table{$key}} = pop(@result_list); 
          
        if ($$result_table{$key} eq $opt_a)
        {
            $result_index = $resultarray{$$result_table{$key}};
        }
    }
     
     
    if(!defined($result_index))
    {
         print "Le port $opt_a n'existe pas\n";
         exit $ERRORS{'CRITICAL'};
    }
    else
    {
          $result = Centreon::SNMP::Utils::get_snmp_leef_no_return([$hp_dot1stp_port_stat . "." . $result_index], $session, $ERRORS{'UNKNOWN'});
          if(defined($result))
          {
               $proc_run = $result->{$hp_dot1stp_port_stat . "." . $result_index};     
               given($proc_run)
               {
                    when (1)
                    {
                        $port_status = "Disabled";
                    }
                    when (2)
                    {
                        $port_status = "Blocking";
                    } 
                    when (3)
                    {
                        $port_status = "Listening";
                    } 
                    when (4)
                    {
                        $port_status = "Learning";
                    }
                    when (5)
                    {                      
                        $port_status = "Forwading";
                    }
                    when (6)
                    {
                        $port_status = "Broken";
                    }                                 
               }  
               
               if($port_status eq $opt_f)
               {
                   print "$opt_a is $port_status";
                   exit $ERRORS{'OK'};
               }
               else
               {
                   print "$opt_a is $port_status";
                   exit $ERRORS{'CRITICAL'};
               }                                                                      
          } 
          else
          {
                $result = Centreon::SNMP::Utils::get_snmp_leef_no_return([$hp_ifoper_status . "." . $result_index], $session, $ERRORS{'UNKNOWN'});
                $proc_run =  $result->{$hp_ifoper_status . "." . $result_index};
                given($proc_run)
                {
                    when 1
                    {
                       $port_status = "Up";
                    }
                    when 2
                    {
                        $port_status = "Down";
                    }
                    when 3
                    {
                        $port_status = "Testing";
                    }
                    when 4
                    {
                        $port_status = "Unknown";             
                    }
                    when 5
                    {
                        $port_status = "Dormant";
                    }
                    when 6
                    {
                        $port_status = "Not present";
                    }
                    when 7
                    {
                        $port_status = "lowerDown";
                    }                                   
                }
                
                
                
                if($port_status eq $opt_f)
                {
                    print "$opt_a is $port_status";
                    exit $ERRORS{'OK'};
                }
                else
                {
                    print "$opt_a is $port_status";
                    exit $ERRORS{'CRITICAL'};
                }        
          }                 
    }                   
}
 
 

sub check_hardware()
{    
  
    if(!defined($opt_f))
    {
        print "Argument -f is requiered with the check hardware variable \n\n";
        print_usage();
        exit $ERRORS{'OK'};
    }
  
    
    my $hwFailureCount = 0;
    my $result;
    my $hpicfSensorEntry  = "1.3.6.1.4.1.11.2.14.11.1.2.6.1.7";
    my $hpicfSensorStatus = "1.3.6.1.4.1.11.2.14.11.1.2.6.1.4";
 
    my %objects = ();   
    
    my ($session_params) = Centreon::SNMP::Utils::check_snmp_options($ERRORS{'UNKNOWN'}, \%OPTION);    
    my $session = Centreon::SNMP::Utils::connection($ERRORS{'UNKNOWN'}, $session_params); 
    
    $result_table = Centreon::SNMP::Utils::get_snmp_table($hpicfSensorEntry, $session, $ERRORS{'UNKNOWN'}, \%OPTION);
    
    my @result_list;
    
    foreach my $key (oid_lex_sort(keys %$result_table))
    {
        @result_list = split (/\./, $key);      
        $resultarray{$$result_table{$key}} = pop(@result_list);                    
        $objects{$$result_table{$key}} = $hpicfSensorStatus . '.' . $resultarray{$$result_table{$key}};                               
    }   
        
    my $criticalcounter = 0;   
    my $returnStatusExtended = ""; 
    $session = Centreon::SNMP::Utils::connection($ERRORS{'UNKNOWN'}, $session_params); 
        
    while((my $a, my $b) = each(%objects))
    {

        my $name = $a;
        
        $result = Centreon::SNMP::Utils::get_snmp_leef([$b], $session, $ERRORS{'UNKNOWN'});
        $proc_run = $result->{$b};

        given($proc_run)
        {
            when 1
            {
                $criticalcounter += 1;
                $returnStatusExtended = "$returnStatusExtended $name : Unknown\n";
            }
            when 2
            {
                $criticalcounter += 1;
                $returnStatusExtended = "$returnStatusExtended $name : Bad\n";
            }
            when 3
            {
                $criticalcounter += 1;
                $returnStatusExtended = "$returnStatusExtended $name : Warning\n";
            }
            when 4
            {
                $returnStatusExtended = "$returnStatusExtended $name : Good\n";
                
            }
            when 5
            {
                 $returnStatusExtended = "$returnStatusExtended $name : Not Present\n";
            }
        }               
    }
       
    
    if($criticalcounter == 0)
    {
        print "Devices failed : $criticalcounter\n";
        print $returnStatusExtended;
        exit $ERRORS{'OK'};
    }         
    elsif($criticalcounter > $opt_f)
    {
        print "Devices failed : $criticalcounter\n";
        print $returnStatusExtended;
        exit $ERRORS{'CRITICAL'};
    }
    elsif($criticalcounter <= $opt_f && $criticalcounter > 0)
    {
        print "Devices failed : $criticalcounter\n";
        print $returnStatusExtended;
        exit $ERRORS{'WARNING'};
    }  
                            
 }
 
 
 

 
 sub print_usage () 
 {
    print "\nUsage:\n";
    print "$PROGNAME\n";
    print "   -H (--hostname)   Hostname to query (required)\n";
    print "   -C (--community)  SNMP read community (defaults to public)\n";
    print "                     used with SNMP v1 and v2c\n";
    print "   -v (--snmp-version)  1 for SNMP v1 (default)\n";
    print "                        2 for SNMP v2c\n";
    print "                        3 for SNMP v3\n";
    print "   -P (--snmp-port)  SNMP port (default: 161)\n";
    print "   -k (--authkey)    snmp V3 key\n";
    print "   -u (--username)   snmp V3 username \n";
    print "   -p (--password)   snmp V3 password\n";
    print "   --authprotocol    protocol MD5/SHA  (v3)\n";
    print "   --privprotocol    encryption system (DES/AES)(v3) \n";
    print "   --privpassword    passphrase (v3) \n";
    print "   --64-bits         Use 64 bits OID\n";
    print "   --maxrepetitions  To use when you have the error: 'Message size exceeded buffer maxMsgSize'\n";
    print "                     Work only with SNMP v2c and v3 (Example: --maxrepetitions=1)\n";
    print "   -n (--variable)   Variable to Query. \n";
    print "                     hardware | ports\n";
    print "   -f (--fault)      Fault tolerence\n";
    print "   -a (--arguments)  Arguments to pass to the variable to query. \n";
    print "   -V (--version)    Plugin version\n";
    print "   -h (--help)       usage help\n";
    print "\n";
    print "\n";
    print "    Exemple :  $PROGNAME .pl -h xx.xx.xx.xx -n hardware -f 1  \n";
    print "               $PROGNAME .pl -h xx.xx.xx.xx -n port -a A21   \n";
       
    
}

sub print_help ()
{
    print_usage();
    print "\n";
}   
    
    
    
