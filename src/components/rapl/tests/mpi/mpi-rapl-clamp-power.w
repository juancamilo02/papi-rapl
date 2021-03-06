#include <stdio.h>
#include <sys/time.h>
#include <unistd.h>
#include <stdint.h>
#include "papi_test.h"

#define MAX_RAPL_EVENTS 64
#define PKG_POWER_LIMIT_DEFAULT 0x6845000148398
#define PP0_POWER_LIMIT_DEFAULT 0x80000000
#define DRAM_POWER_LIMIT_DEFAULT 0x80000000


static int rank;
int retVal = -1; 

static int msr_rank_mod=16;
uint64_t msr_pkg_power_limit=PKG_POWER_LIMIT_DEFAULT, msr_pp0_power_limit=PP0_POWER_LIMIT_DEFAULT;
#ifdef ARCH_062D
        uint64_t msr_dram_power_limit=DRAM_POWER_LIMIT_DEFAULT;
#endif


int retval,cid,rapl_cid=-1,numcmp;
int EventSet = PAPI_NULL;
long long *values;
int num_events=0;
int code;
char event_names[MAX_RAPL_EVENTS][PAPI_MAX_STR_LEN];
char units[MAX_RAPL_EVENTS][PAPI_MIN_STR_LEN];
int r,i;
const PAPI_component_info_t *cmpinfo = NULL;
PAPI_event_info_t evinfo;
long long before_time,after_time;
double elapsed_time;


/*For the MSR_RANK_MOD variable */
int get_env_int(const char *name, int *val){
        char *str=NULL;
        str = getenv(name);

        //PATKI: Adding another missing error check that was resulting in a random segfault!    
        if(str ==NULL){
                *val = -1;
                return -1;
        }
        *val = (int) strtol(str, (char **)NULL, 0);
        return 0;
}



void
read_env_vars(){
        int cpu;
        char *env = NULL;


        // First, check the environment variables.
        env = getenv("MSR_PKG_POWER_LIMIT");

        if(env == NULL){
                fprintf(stderr, "Error in reading environment variable MSR_PKG_POWER_LIMIT. Using defaults.\n");
        }
        if(env){
                msr_pkg_power_limit = strtoll( env, NULL, 0 );
        }



        env = getenv("MSR_PP0_POWER_LIMIT");
        if(env == NULL){
                fprintf(stderr, "Error in reading environment variable MSR_PP0_POWER_LIMIT. Using defaults.\n");
        }
        if(env){
                msr_pp0_power_limit = strtoll( env, NULL, 0 );
        }


#ifdef ARCH_062D
        env = getenv("MSR_DRAM_POWER_LIMIT");
        if(env == NULL){
                fprintf(stderr, "Error in reading environment variable MSR_DRAM_POWER_LIMIT. Using defaults.\n");
        }

        if(env){
                msr_dram_power_limit = strtoll( env, NULL, 0 );
        }
#endif
}


{{fn foo MPI_Init}}
	{{callfn}}
	rank = -1;
	PMPI_Comm_rank( MPI_COMM_WORLD, &rank );
	

	/*Get the MSR_RANK_MOD environment variable. Default is 16. */
	retVal = get_env_int("MSR_RANK_MOD", &msr_rank_mod);

        if(retVal == -1){
                printf("Error: To run an MPI program, the MSR_RANK_MOD environment variable should be set.\n");
                exit(EXIT_FAILURE);
        }


/*BIG IF STATEMENT. ENSURES THAT ONLY ONE RANK READS OR WRITES ON A NODE */
if(rank % msr_rank_mod == 0) {
   /* PAPI Initialization */
     retval = PAPI_library_init( PAPI_VER_CURRENT );
     if ( retval != PAPI_VER_CURRENT ) {
        test_fail(__FILE__, __LINE__,"PAPI_library_init failed\n",retval);
     }

     numcmp = PAPI_num_components();

     for(cid=0; cid<numcmp; cid++) {

        if ( (cmpinfo = PAPI_get_component_info(cid)) == NULL) {
           test_fail(__FILE__, __LINE__,"PAPI_get_component_info failed\n", 0);
        }

        if (strstr(cmpinfo->name,"linux-rapl")) {
           rapl_cid=cid;
            printf("Found rapl component at cid %d\n",
                                    rapl_cid);
           if (cmpinfo->num_native_events==0) {
              test_skip(__FILE__,__LINE__,"No rapl events found",0);
           }
           break;
        }
     }

     /* Component not found */
     if (cid==numcmp) {
       test_skip(__FILE__,__LINE__,"No rapl component found\n",0);
     }

     /* Create EventSet */
     retval = PAPI_create_eventset( &EventSet );
     if (retval != PAPI_OK) {
        test_fail(__FILE__, __LINE__,
                              "PAPI_create_eventset()",retval);
     }


     /* Add all events */

     code = PAPI_NATIVE_MASK;

     r = PAPI_enum_cmp_event( &code, PAPI_ENUM_FIRST, rapl_cid );

     while ( r == PAPI_OK ) {

        retval = PAPI_event_code_to_name( code, event_names[num_events] );
        if ( retval != PAPI_OK ) {
           printf("Error translating %x\n",code);
           test_fail( __FILE__, __LINE__,
                            "PAPI_event_code_to_name", retval );
        }


    retval = PAPI_get_event_info(code,&evinfo);
        if (retval != PAPI_OK) {
          test_fail( __FILE__, __LINE__,
             "Error getting event info\n",retval);
        }

        strncpy(units[num_events],evinfo.units,PAPI_MIN_STR_LEN);


        retval = PAPI_add_event( EventSet, code );
        if (retval != PAPI_OK) {
          break; /* We've hit an event limit */
        }
        num_events++;

        r = PAPI_enum_cmp_event( &code, PAPI_ENUM_EVENTS, rapl_cid );
     }

     values=calloc(num_events,sizeof(long long));
     if (values==NULL) {
        test_fail(__FILE__, __LINE__,
                              "No memory",retval);
     }


  /*Now, write the register values. Note that if you change the order of events the values[] subscript would need to be changed. The following assumes all events are added in the same order as they were created by RAPL. */
	
	read_env_vars();
	

	values[14] = (long long) msr_pkg_power_limit;
	values[15] = (long long) msr_pkg_power_limit;
	values[16] = (long long) msr_pp0_power_limit;
	values[17] = (long long) msr_pp0_power_limit;
	values[18] = (long long) msr_dram_power_limit;
	values[19] = (long long) msr_dram_power_limit;

     retval = PAPI_start( EventSet);
     if (retval != PAPI_OK) {
        test_fail(__FILE__, __LINE__, "PAPI_start()",retval);
     }

	printf("\nMPI Wrapper: Writing values now... ");
	retval = PAPI_write(EventSet, values);
   
 	 if (retval != PAPI_OK) {
        	test_fail(__FILE__, __LINE__, "PAPI_write()",retval);
     	}


     before_time=PAPI_get_real_nsec();

} /*end if*/

{{endfn}}

{{fn foo MPI_Finalize}}
	{{callfn}}

  /* Stop Counting */

  if(rank % msr_rank_mod ==0) {   
  after_time=PAPI_get_real_nsec();
     retval = PAPI_stop( EventSet, values);
     if (retval != PAPI_OK) {
        test_fail(__FILE__, __LINE__, "PAPI_start()",retval);
     }

     elapsed_time=((double)(after_time-before_time))/1.0e9;

     rapl_print_info_event_names(event_names, num_events, elapsed_time, values,rank);

} /*end if*/

{{endfn}}
