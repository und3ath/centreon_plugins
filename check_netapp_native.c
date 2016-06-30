#include <net-snmp/net-snmp-config.h>
#include <net-snmp/net-snmp-includes.h>
#include <string.h>

struct snmp_session session;
struct snmp_session *session_handle;
struct snmp_pdu *pdu;
struct snmp_pdu *response;
struct variable_list *vars;

size_t id_len = MAX_OID_LEN;
size_t serial_len = MAX_OID_LEN;

oid id_oid[MAX_OID_LEN];
oid serial_oid[MAX_OID_LEN];

int returncode;

char outbuff[256];
char *resultString;

void freeSession();
void processSnmpGet(char* oid);
void PrintHelp();

int main(int argc, char * argv[]){
    returncode = 0;
    int status;
    struct tree * mib_tree;

    if(argv[1] != NULL && strcmp("-h", argv[1]) == 0 || strcmp("--help", argv[1]) == 0){
        PrintHelp();
        return 0;
    }
    if(argv[1] == NULL || argv[2] == NULL || argv[3] == NULL || argv[4]== NULL) {
        printf("Argument invalide (hostname, variable, warning, critical)\n");
    }

    snmp_sess_init(&session);
    session.version = SNMP_VERSION_1;
    session.community = "public";
    session.community_len = strlen(session.community);
    session.peername = argv[1];

    session_handle = snmp_open(&session);
    add_mibdir("/usr/share/snmp/mibs/");

    pdu = snmp_pdu_create(SNMP_MSG_GET);

    char variable[50];
    snprintf(variable, 50, argv[2]);

    if(strcmp("CPULOAD", variable) == 0){
		processSnmpGet("NETWORK-APPLIANCE-MIB::cpuBusyTimePerCent.0");
		int result = atoi(resultString + 2);
        if(result >= atoi(argv[4])){
            returncode = 2;
        }
        else if (result >= atoi(argv[3])){
            returncode = 1;
        }
        printf("CPU Load : %d %% | cpu_load=%d %%\n", result, result);
    }
    else if(strcmp("PS", variable) == 0){
        processSnmpGet("NETWORK-APPLIANCE-MIB::envFailedPowerSupplyCount.0");
        int result = atoi(resultString);
        if(result >= atoi(argv[4])){
            returncode = 2;
        }
        else if (result >= atoi(argv[3])){
            returncode = 1;
        }
        printf("Failed Power Supply : %d\n", result);

    }
    else if(strcmp("FAN", variable) == 0){
        processSnmpGet("NETWORK-APPLIANCE-MIB::envFailedFanCount.0");
        int result = atoi(resultString);
        if(result >= atoi(argv[4])){
            returncode = 2;
        }
        else if (result >= atoi(argv[3])){
            returncode = 1;
        }
        printf("Failed FAN : %d\n", result);
    }
	else if(strcmp("TEMP", variable) == 0){
		processSnmpGet("NETWORK-APPLIANCE-MIB::envOverTemperature.0");
        int result = atoi(resultString);
        if(result == 2){
            returncode = 2;
			printf("Over Temperatur : YES");
        }
        else{
            printf("Over Temperatur : NO");
        }
	}
	else if(strcmp("NVRAM", variable) == 0){
		processSnmpGet("NETWORK-APPLIANCE-MIB::nvramBatteryStatus.0");
        int result = atoi(resultString);
		if(result > 1){
		    returncode = 2;
		}
		printf("NVRAM battery status: %d\n", result);
	}
    else{
        printf("Invalid argument");
        freeSession();
        return 3;
    }
    freeSession();
    return returncode;
}

void processSnmpGet(char * oid){
	read_objid(oid, id_oid, &id_len);
    snmp_add_null_var(pdu, id_oid, id_len);
    int status = snmp_synch_response(session_handle, pdu, &response);
	for(vars = response->variables; vars; vars = vars->next_variable){
        snprint_variable(outbuff, 256, vars->name, vars->name_length, vars);
        resultString = strrchr(outbuff, ':');
    }
}

void freeSession(){
    snmp_free_pdu(response);
    snmp_close(session_handle);
    return;
}

void PrintHelp(){
    printf("\n\nCheck_NETAPP\n");
    printf("Author : undx\n");
    printf("Version 0.1 (first release)\n\n");
    printf("Usage : ./check_netapp HOSTNAME VARIABLE WARNING CRITICAL\n");
    printf("  Valid VARIABLE : CPULOAD | PS | FAN | NVRAM\n");
    printf("Exemple : check_netapp myhost CPULOAD 80 90\n");
}
