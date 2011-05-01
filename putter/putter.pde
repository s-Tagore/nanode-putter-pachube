/*
 * Arduino ENC28J60 Ethernet shield pachube client
 * Supports CSV method only due to buffer size limitations.
 * with option to tweet every hour
 *
 * Written by Andrew Lindsay, July 2009.
 * Portions of code taken from examples on nulectronics.com (oneWIre and sht11 code)
 * TCP/IP code originally from tuxgraphics.org - combined with ethershield library by me.
 * Now combined with Ken Boak's serial command interpreter Aug 25th 2010
 */

#include "EtherShield.h"

// Code compilation options
// define TWEET to include twitter calls
// #define TWEET

// define FULLWEB to display just a full webpage with values or a simple 1 line csv output
//#define FULLWEB

// ** Local Network Setup **
// Please modify the following lines. mac and ip have to be unique
// in your local area network. You can not have the same numbers in
// two devices:
static uint8_t mymac[6] = {
  0x54,0x55,0x58,0x10,0x00,0x25};

// how did I get the mac addr? Translate the first 3 numbers into ascii is: TUX
// The IP address of the arduino.
static uint8_t myip[4] = {192,168,1,92};

// Default gateway. The ip address of your DSL/Cable router.
static uint8_t gwip[4] = {
  87,114,102,8};

// ** pachube.com setup **
// IP address of the www.pachube.com server to contact (IP of the first portion of the URL):
static uint8_t pachubeip[4] = {
  173,203,98,29};

// The name of the virtual host which you want to contact at pachubeip (hostname of the first portion of the URL):
#define PACHUBE_VHOST "www.pachube.com"

// setup yor feed url and API keys here.
#define PACHUBEAPIURL "/api/24480.csv"
#define PACHUBEAPIKEY "X-PachubeApiKey: _v2KmM2YYleSiA3FwEfMFrTPKg5Xu5XLAV9p3V2_oOo"

#ifdef TWEET
// ** Twitter setup **
// IP address of the twitter server to contact (IP of the first portion of the URL):
static uint8_t twitterip[4] = {
  128,121,146,228};

// The name of the virtual host which you want to contact at twitterip (hostname of the first portion of the URL):
#define TWITTER_VHOST "twitter.com"
#define TWITTERAPIURL "/statuses/update.xml"

// The TWITTERACCOUNT Authorization code can be generated from 
// username and password of your twitter account 
// by using this encoder: http://tuxgraphics.org/~guido/javascript/base64-javascript.html
// Replace the string after the space after Basic with your authurization string
#define TWITTERACCOUNT "Authorization: Basic xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

// how many pachube updates to do before tweeting, currently updating vert 30s, so 120 is after about an hour.
#define UPDATES_TO_TWEET 120
#endif

// End of configuration 

// listen port for tcp/www:
#define MYWWWPORT 80

static volatile uint8_t start_web_client=0;  // 0=off but enabled, 1=send update, 2=sending initiated, 3=update was sent OK, 4=diable updates
static uint8_t web_client_attempts=0;
static uint8_t web_client_sendok=0;
static uint8_t resend=0;

int tempr = 0;
int outTemp = 0;
int humid = 0;
int dewpoint = 0;
int lightValue = 0;


//  for the serial command interpreter

long previousMillis = 0;        // will store last time serial output was updated
int interval = 1000;           // interval at which to generate serial output (milliseconds)

int incomingByte = 0;
boolean dataReady = false;
int i = 0;
int len = 4;                      // expected string is 6 bytes long
char inString[34];                // expected input string could be up to 33 characters long
char sub_add_String[4];           // sub-address is up to 3 characters

char arg0_String[6];              // arg0 is up to 5 digits
char arg1_String[6];              // arg1 is up to 5 digits
char arg2_String[6];              // arg2 is up to 5 digits
char arg3_String[6];              // arg3 is up to 5 digits
char arg4_String[6];              // arg4 is up to 5 digits
char arg5_String[6];              // arg5 is up to 5 digits

char inByte;
char inChar;
char commandChar = 0;           // holds the command character
char nextChar;
int incoming;

int temporary = 0;
int temp2 = 0;
int sub_add = 0;
char arg0 = 0;
unsigned int arg1 = 0;      // Initialise the six input arguments
unsigned int arg2 = 0;
unsigned int arg3 = 0;
unsigned int arg4 = 0;
unsigned int arg5 = 0;
unsigned int arg6 = 0;
int k = 0;
int o = 0;
int q;                     //pointers for string handling
int r;
int s;
int t;
int u;
int n = 0;

int PWMpin = 5;    // PWM output on pin 5 to MPPT active load
int PWMval = 0;
int LEDpin = 6;    // PWM drive to LED driver
int LEDval = 0;
int FANpin = 3;    // PWM to fan speed control
int FANval = 0;

//*****************************************************************************************


#include <SoftwareSerial.h>
#include <math.h>



#define Therm0 0   // Analog Pin 0
#define Therm1 1   // Analog Pin 1
#define Therm2 2   // Analog Pin 2
#define Therm3 3   // Analog Pin 3
#define Therm4 4   // Analog Pin 4
#define Therm5 5   // Analog Pin 5
#define LDR 4

double temp;



char N;
int I;
int ByteVar;
int Temp1;
int Temp2;
int Temp3;
int x;
int hours;
int mins;
int secs;
unsigned long millisold;
int illum;

int pumpPin = 13;                 // LED connected to digital pin 13


int NN;
int Remainder;
int Num_5;

#ifdef TWEET
#define STATUS_BUFFER_SIZE 200
int updatesSinceTweet = UPDATES_TO_TWEET;
#else
#define STATUS_BUFFER_SIZE 50
#endif

#define BUFFER_SIZE 650
static uint8_t buf[BUFFER_SIZE+1];

// global string buffer for twitter message:
static char statusstr[STATUS_BUFFER_SIZE];

// Instantiate the EtherShield class
EtherShield es=EtherShield();

// prepare the webpage by writing the data to the tcp send buffer
uint16_t print_webpage(uint8_t *buf)
{
  uint16_t plen;
  char vstr[5];

  plen = es.ES_fill_tcp_data_p(buf,0,PSTR("HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nPragma: no-cache\r\n\r\n"));
#ifdef FULLWEB
  // Display full info 
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("<h1>Arduino Monitoring</h1><pre>\n"));
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("Inside Temp: "));
  itoa(tempr/100,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("."));
  itoa(tempr%100,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);

  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("C\nRel Humidity: "));
  itoa(humid/100,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("."));
  itoa(humid%100,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("%RH\nDew Point: "));
  itoa(dewpoint/100,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("."));
  itoa(dewpoint%100,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);

  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("C\nOutside Temp: "));
  itoa(outTemp/100,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("."));
  itoa(outTemp%100,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);

  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("C\nLight Level: "));
  // convert number to string:
  plen=es.ES_fill_tcp_data(buf,plen,vstr);

#ifdef TWEET
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("%\nUpdates since tweet: "));
  itoa(updatesSinceTweet,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);

  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("\n</pre>"));
#else
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("%\n</pre>"));
#endif
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("<a href=\"http://www.pachube.com/feeds/xxxx/\">Pachube Feed</a>"));
#else  
  // Display just the csv data
  plen=es.ES_fill_tcp_data(buf,plen,statusstr);
#endif
  return(plen);
}

// Browser callback, where we get to after receiving a reply to an update, should really 
// do somthing here to check all was OK.
void browserresult_callback(uint8_t statuscode,uint16_t datapos){

  if (statuscode==0){
    web_client_sendok++;
  }
  // clear pending state at sucessful contact with the
  // web server even if account is expired:
  if (start_web_client==2) start_web_client=3;
}

// Perform setup on etherent and oneWire
void setup(){

  initOneWire();
  Serial.begin(9600);
  
  Serial.println("Pachube Command Loader");
  
  pinMode(PWMpin, OUTPUT);     //  Set up the digital pins as outputs for PWM
  pinMode(FANpin, OUTPUT);
  pinMode(LEDpin, OUTPUT);
  
  // Code will hang here if the ENC28J60 is not responding
  
  

  // initialize enc28j60
  es.ES_enc28j60Init(mymac);
  //init the ethernet/ip layer:
  es.ES_init_ip_arp_udp_tcp(mymac,myip, MYWWWPORT);
  // init the web client:
  es.ES_client_set_gwip(gwip);  // e.g internal IP of dsl router
  
  
  
  
}

// The business end of things
void loop(){
  uint16_t dat_p;
  int8_t cmd;
  start_web_client=1;
  unsigned long lastSend = millis();
  unsigned long time;
  
 

  while(1){
    // handle ping and wait for a tcp packet
    dat_p=es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
    
    
     
  
 
    
    if(dat_p==0){
      // Nothing received, just see if there is anythng to do 
      
      // update every 10s
      time = millis();
      // see if there is any serial
     serialReader();

      
      if( time > (lastSend + 10000) ) {
        if (dataReady) break;
        
        resend=1; // resend once if it failed
        start_web_client=1;
        
       
        
        lastSend = time;
        
      }
      
      if (start_web_client==1) {
        start_web_client=2;
        web_client_attempts++;

        // Here is where we make the reading and build the csv data
        takeSHTReading();
        tempr = readSHTemp();
        humid = readRelHumidity();
        dewpoint = readDewPoint();
        outTemp = readOneWireTemp();
        lightValue = readLight();
        
        
        // Read and interpret any serial input and form the argument string
        
       
       
        
        // Decide to update pachube or tweet
#ifdef TWEET
        if( updatesSinceTweet > UPDATES_TO_TWEET ) {
          // Build tweet message - just build up here and slap in values should be encoded ok.
          sprintf( statusstr, "status=Inside+Temp+%d.%dC,+Rel+Humidity+%d.%d,+Dew+Point+%d.%dC,+Outside+Temp+%d.%dC,+Light+Level+%d", tempr / 100, tempr % 100, humid / 100, humid % 100, dewpoint / 100, dewpoint % 100, outTemp / 100, outTemp % 100, lightValue );
          es.ES_client_set_wwwip(twitterip);
          es.ES_client_http_post(PSTR(TWITTERAPIURL),PSTR(TWITTER_VHOST),PSTR(TWITTERACCOUNT), PSTR("POST "),statusstr,&browserresult_callback);
          updatesSinceTweet = 0;
        } 
        else {
#endif
          // Pachube update
          //sprintf( statusstr, "%d.%d,%d.%d,%d.%d,%d.%d,%d", tempr / 100, tempr % 100, humid / 100, humid % 100, dewpoint / 100, dewpoint % 100, outTemp / 100, outTemp % 100, lightValue );
         // sprintf( statusstr, "%d.%d,%d.%d,%d.%d,%d.%d,%d.%d,%d.%d", temp0 / 100, temp0 % 100, temp1 / 100, temp1 % 100, temp2 / 100, temp2 % 100, temp3 / 100, temp3 % 100, temp4 / 100, temp4 % 100, temp5 / 100, temp5 % 100 );
 
          sprintf( statusstr, "%c,%u,%u,%u,%u,%u,%u", arg0,  arg1,  arg2, arg3,  arg4 ,  arg5, arg6  );
          
        Serial.println(statusstr);   // print out the string for debug purposes
 
 
          es.ES_client_set_wwwip(pachubeip);
          es.ES_client_http_post(PSTR(PACHUBEAPIURL),PSTR(PACHUBE_VHOST),PSTR(PACHUBEAPIKEY), PSTR("PUT "), statusstr ,&browserresult_callback);
#ifdef TWEET
          updatesSinceTweet++;
        }
#endif
      }

      continue;
    }

    dat_p=print_webpage(buf);
    es.ES_www_server_reply(buf,dat_p); // send data
  }
}
// Thats all folks!!





// Thermistor Linearisation Code

double Thermistor(int RawADC) {
 // Inputs ADC Value from Thermistor and outputs Temperature in Celsius
 //  requires: include <math.h>
 // Utilizes the Steinhart-Hart Thermistor Equation:
 //    Temperature in Kelvin = 1 / {A + B[ln(R)] + C[ln(R)]^3}
 //    where A = 0.001129148, B = 0.000234125 and C = 8.76741E-08
 
 long Resistance;  
 double Temp;     // Dual-Purpose variable to save space.
 int i; 
 double accum = 0;
 
 // Take 10 readings each 100mS and average them
 
 for (int i=0; i <= 9; i++) {
 
 Resistance=((10240000/RawADC) - 10000);  // Assuming a 10k Thermistor.  Calculation is actually: Resistance = (1024 * BalanceResistor/ADC) - BalanceResistor
 
 Temp = log(Resistance); // Saving the Log(resistance) so not to calculate it 4 times later. // "Temp" means "Temporary" on this line.
 
 Temp = 1 / (0.001129148 + (0.000234125 * Temp) + (0.0000000876741 * Temp * Temp * Temp));   // Now it means both "Temporary" and "Temperature"
 
 Temp = Temp - 273.15;  // Convert Kelvin to Celsius                                         // Now it only means "Temperature"
 
 accum = accum + Temp;
 
 delay(100); 
 
 }
 

 
 Temp = accum * 10;    // Multiply by 100 so it can be divided down and modulo'd later
 
// Serial.print(Temp);
// Serial.print(",");
 
 return Temp;  // Return the Temperature
 

 
 
}




 /****************************** Functions **************************************/
 
 /*************************************************************************************************/
 // Gets the serial command from the serial port, decodes it and performs action
 /*********************************************************************************************/
// Decodes a serial input string in the form  a255,65535,65535,65535,65535 CR
// So an alpha command a (arg0), followed by up to 5 numerical arguments (arg1 to arg5)
// If any of the arguments are missing they will default to zero
// so b1  =  b,1,0,0,0,0 and b,1 = b,1,0,0,0,0
// Always produces 6 comma separated terms, of which the first is alpha 
// (or punctuation character except comma)
 /*************************************************************************************************/
// a = command 
// 255 = 8-bit sub address
// , is delimiter
// 65535 is integer arg1
// , is delimiter
// 65535 is integer arg2
// , is delimiter
// 65535 is integer arg3
// , is delimiter
// 65535 is integer arg4
// , is delimiter
// 65535 is integer arg5
/*********************************************************************************************/
 

/*************************************************************************************************/
int serialReader(){ 
  
  initStrings();                          // Clear the string buffers before we start
  dataReady = 0;                           // Clear the serial flag
  
  if  (Serial.available() > 0) {          // if there are bytes waiting on the serial port
    inByte = Serial.read();               // read a byte
    delay(10);                            // *** added to make it work ***

    if (inByte == 13){                    //  follow the false code until you get a CR - this packs inString with the complete string
      dataReady = true;
      
      
      
      
      // now start to strip out the command and argument fields
      
      inChar = inString[1];               // get the leading character - this is the command character
      
      arg0 = inChar;                      // arg0 is the command character

      
      /*******************************************************************************************/
      // Now we process the arg1_String  checking whether we are b1 or b,1 format
      /*******************************************************************************************/
      
      // q is a pointer which increments it's way through inString
      
       k =  0;                          //reset the string pointer
       
       nextChar = inString[2];           // check if the second character is a comma (b,1 format)- if so start at the 3rd character
       
       if ( nextChar==44)  q=3;         // If character 2 is a comma - arg 1 will be in position 3
       else q=2;                        // b1 format
       
       
      for (int p = q; p <34; p++) {     // Now start at the location after the comma and strip out the arg1_String
      
      
      
        nextChar = inString[p];         // get the next Char
        
       q++;                             // Increment pointer q to keep track of where we are in inString
      
         if (nextChar == 44 || nextChar == 13 ) {          // if it's a comma (ASCII 44) then bail out
         
         q--;
      
       
        break;
       
      }
        
      arg1_String[k] = nextChar;    // start packing the arg1_String
      
      k++;                             // increment the pointer to arg1_String
      
     
        
      }
      
      
       // arg1_String should now contain up to 5 characters
      
      
      
      /*******************************************************************************************/
      // Now we process the arg2_String in the same way
      /*******************************************************************************************/
      
      k =  0;                    //reset the string pointer
       
      for (int p = q+1; p <34; p++) {   // Now start at the location after the 2nd comma and strip out the arg2_String
      
      nextChar = inString[p];         // get the next Char
      
      q++;
      
     if (nextChar == 44 || nextChar == 13 ) {          // if it's a comma (ASCII 44) then bail out
      
       
       break;
       
      }
        
      arg2_String[k] = nextChar;    // start packing the arg1_String
      
      k++;                             // increment the pointer to arg2_String
      
     
        
      }
      
      /*******************************************************************************************/
      // Now we process the arg3_String in the same way
      /*******************************************************************************************/
      
      k =  0;                    //reset the string pointer
       
      for (int p = q+1; p <34; p++) {   // Now start at the location after the 2nd comma and strip out the arg3_String
      
      nextChar = inString[p];         // get the next Char
      
      q++;
      
      if (nextChar == 44 || nextChar == 13 ) {          // if it's a comma (ASCII 44) then bail out
      
       break;
       
      }
        
      arg3_String[k] = nextChar;    // start packing the arg1_String
      
      k++;                             // increment the pointer to arg3_String
    
      }
      
      /*******************************************************************************************/
      // Now we process the arg4_String in the same way
      /*******************************************************************************************/
      
      k =  0;                    //reset the string pointer
       
      for (int p = q+1; p <34; p++) {   // Now start at the location after the 2nd comma and strip out the arg4_String
      
      nextChar = inString[p];         // get the next Char
      
      q++;
      
      if (nextChar == 44 ) {         // if it's a comma (ASCII 44) then bail out
      
       break;
       
      }
        
      arg4_String[k] = nextChar;    // start packing the arg1_String
      
      k++;                             // increment the pointer to arg4_String
     
      }
      
      
      /*******************************************************************************************/
      // Now we process the arg5_String in the same way
      /*******************************************************************************************/
      
      k =  0;                    //reset the string pointer
       
      for (int p = q+1; p <34; p++) {   // Now start at the location after the 2nd comma and strip out the arg5_String
      
      nextChar = inString[p];         // get the next Char
      
      q++;
      
     if (nextChar == 44 || nextChar == 13 ) {          // if it's a comma (ASCII 44) then bail out
    
       break;
       
      }
        
      arg5_String[k] = nextChar;    // start packing the arg1_String
      
      k++;                             // increment the pointer to arg5_String
        
      }
      
     
       
  //     arg0 = atoi(arg0_String);          // get enumerated arg0
       arg1 = atoi(arg1_String);          // get enumerated arg1
       arg2 = atoi(arg2_String);          // get enumerated arg2
       arg3 = atoi(arg3_String);          // get enumerated arg3
       arg4 = atoi(arg4_String);          // get enumerated arg4
       arg5 = atoi(arg5_String);          // get enumerated arg5
       arg6++;                            // increment the message number
       
       
       
   // Print out the ennumerated arguments noting that arg0 is a character   
      
      sprintf( statusstr, "%c,%u,%u,%u,%u,%u,%u", arg0,  arg1,  arg2, arg3,  arg4 ,  arg5, arg6 );
//      Serial.println(statusstr);   // print out the string for debug purposes
      
      
      
 //     clear the inStrings
 
      for (int j = 0; j < 34; j++) {        // clear the inString for next time
     inString[j] = 0;
      }
 
      
      i = 0;
      
      return incoming;
    }
    else dataReady = false;      // No CR seen yet so put digits into array
//    Serial.print(inByte); 


    inString[i] = inByte;
    
   
    
    i++;
 
  
  }


}

/***************************************************************************************************/
// Initialise the strings to zero 
/***************************************************************************************************/

 int initStrings()  {


 /*
 
        arg0 = 0;                            // Initialise the six input arguments
        arg1 = 0;      
        arg2 = 0;
        arg3 = 0;
        arg4 = 0;
        arg5 = 0;
   */   
      for (int j = 0; j < 4; j++) {        // clear the sub_add_String
      sub_add_String[j] = 0;
      }
      
      for (int j = 0; j < 6; j++) {        // clear the arg1_String
      arg1_String[j] = 0;
      }
      
      for (int j = 0; j < 6; j++) {        // clear the arg2_String
      arg2_String[j] = 0;
      }
      
       for (int j = 0; j < 6; j++) {        // clear the arg1_String
      arg3_String[j] = 0;
      }
      
      for (int j = 0; j < 6; j++) {        // clear the arg2_String
      arg4_String[j] = 0;
      }
      
      for (int j = 0; j < 6; j++) {        // clear the arg2_String
      arg5_String[j] = 0;
      }
      
    }

/***********************************************************************************/
// John Crouchley's GET code for ENC28J60
/*************************************************************************************/
