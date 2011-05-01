/*
 * Functions for reading sht10 humidity &temperature sensor 
 */
#include <avr/io.h>

//register dr command r/w
#define STATUS_REG_W 0x06 //000 0011 0
#define STATUS_REG_R 0x07 //000 0011 1
#define MEASURE_TEMP 0x03 //000 0001 1
#define MEASURE_HUMI 0x05 //000 0010 1
#define RESET 0x1e        //000 1111 0

// pins at - PORTD5 (5), clk - PORTD6 (6) so they dont clash with SPI pins 10-13
#define SETSCK1 PORTD|=(1<<PORTD6)
#define SETSCK0 PORTD&=~(1<<PORTD6)
#define SCKOUTP DDRD|=(1<<DDD6)
//
#define SETDAT1 PORTD|=(1<<PORTD5)
#define SETDAT0 PORTD&=~(1<<PORTD5)
#define GETDATA (PIND&(1<<PIND5))
//
#define DMODEIN DDRD&=~(1<<DDD5)
#define PULLUP1 PORTD|=(1<<PIND5)
#define DMODEOU DDRD|=(1<<DDD5)

//pulswith long
#define S_PULSLONG delayMicroseconds(3) 
#define S_PULSSHORT delayMicroseconds(1)

// function declaration
char s_measure(unsigned int *p_value, unsigned char mode);
void calc_sth11(float *p_humidity ,float *p_temperature);
float calc_dewpoint(float h,float t);

float humival_f, tempval_f, dew_point_f;

int readSHTemp() {
  return (int)(tempval_f * 100);
}

int readRelHumidity() {
  return (int)(humival_f * 100);
}

int readDewPoint() {
  return (int)(dew_point_f * 100);
}

void takeSHTReading() {
  byte error;
  byte rh;
  unsigned int humival_raw,tempval_raw;
  char str[15];

  error=s_measure( &tempval_raw,0); //measure temperature

  if (error==0){
    error=s_measure( &humival_raw,1); //measure humidity
  }

  if(error!=0){ //in case of an error
    /*    if (error==1){
     Serial.println("SHT1x sensor communication error");
     }
     if (error==3){
     Serial.println("SHT1x sensor timeout error");
     }
     */
    return;
  }

  humival_f = (float) humival_raw;
  tempval_f = (float) tempval_raw;

  calc_sth11(&humival_f, &tempval_f);
  dew_point_f=calc_dewpoint(humival_f,tempval_f); //calculate dew point
}

// writes a byte on the Sensibus and checks the acknowledge
char s_write_byte(unsigned char value)
{
  unsigned char i=0x80;
  unsigned char error=0;
  DMODEOU; 
  while(i){ //shift bit for masking
    if (i & value) {
      SETDAT1; //masking value with i , write to SENSI-BUS
    }
    else{ 
      SETDAT0;
    }
    SETSCK1; //clk for SENSI-BUS
    S_PULSLONG;
    SETSCK0;
    S_PULSSHORT;
    i=(i>>1);
  }
  DMODEIN; //release DATA-line
  PULLUP1;
  SETSCK1; //clk #9 for ack
  S_PULSLONG;
  if (GETDATA){ //check ack (DATA will be pulled down by SHT11)
    error=1;
  }
  S_PULSSHORT;
  SETSCK0;
  return(error); //error=1 in case of no acknowledge
}

// reads a byte form the Sensibus and gives an acknowledge in case of "ack=1"
unsigned char s_read_byte(unsigned char ack)
{
  unsigned char i=0x80;
  unsigned char val=0;
  DMODEIN; //release DATA-line
  PULLUP1;
  while(i){ //shift bit for masking
    SETSCK1; //clk for SENSI-BUS
    S_PULSSHORT;
    if (GETDATA){
      val=(val | i); //read bit
    }
    SETSCK0;
    S_PULSSHORT;
    i=(i>>1);
  }
  DMODEOU; 
  if (ack){
    //in case of "ack==1" pull down DATA-Line
    SETDAT0;
  }
  else{
    SETDAT1;
  }
  SETSCK1; //clk #9 for ack
  S_PULSLONG;
  SETSCK0;
  S_PULSSHORT;
  DMODEIN; //release DATA-line
  PULLUP1;
  return (val);
}

// generates a sensirion specific transmission start
// This is the point where sensirion is not I2C standard conform and the
// main reason why the AVR TWI hardware support can not be used.
//       _____         ________
// DATA:      |_______|
//           ___     ___
// SCK : ___|   |___|   |______
void s_transstart(void)
{
  //Initial state
  SCKOUTP;
  SETSCK0;
  DMODEOU; 
  SETDAT1;
  //
  S_PULSSHORT;
  SETSCK1;
  S_PULSSHORT;
  SETDAT0;
  S_PULSSHORT;
  SETSCK0;
  S_PULSLONG;
  SETSCK1;
  S_PULSSHORT;
  SETDAT1;
  S_PULSSHORT;
  SETSCK0;
  S_PULSSHORT;
  //
  DMODEIN; //release DATA-line
  PULLUP1;
}

// communication reset: DATA-line=1 and at least 9 SCK cycles followed by transstart
//      _____________________________________________________         ________
// DATA:                                                     |_______|
//          _    _    _    _    _    _    _    _    _        ___    ___
// SCK : __| |__| |__| |__| |__| |__| |__| |__| |__| |______|  |___|   |______
void s_connectionreset(void)
{
  unsigned char i;
  //Initial state
  SCKOUTP;
  SETSCK0;
  DMODEOU; 
  SETDAT1;
  for(i=0;i<9;i++){ //9 SCK cycles
    SETSCK1;
    S_PULSLONG;
    SETSCK0;
    S_PULSLONG;
  }
  s_transstart(); //transmission start
}

// resets the sensor by a softreset
char s_softreset(void)
{
  s_connectionreset(); //reset communication
  //send RESET-command to sensor:
  return (s_write_byte(RESET)); //return=1 in case of no response form the sensor
}


// makes a measurement (humidity/temperature) with checksum
// p_value returns 2 bytes
// mode: 1=humidity  0=temperature
// return value: 1=write error, 2=crc error, 3=timeout
//
char s_measure(unsigned int *p_value, unsigned char mode)
{
  unsigned error;
  unsigned char i=0;
  s_transstart(); //transmission start
  *p_value=0;
  if(mode){
    mode=MEASURE_HUMI;
  }
  else{
    mode=MEASURE_TEMP;
  }
  if(s_write_byte(mode)){
    return(1);
  }
  // normal delays: temp i=70, humi i=20
  while(i<240){
    delay(3);
    if (GETDATA==0){
      i=0;
      break;
    }
    i++;
  }
  if(i){
    // or timeout 
    return(3);
  }
  i=s_read_byte(1); //read the first byte (MSB)
  *p_value=(i<<8)|s_read_byte(0); //read the second byte (LSB) and end with no-ack
  return(0);
}

//----------------------------------------------------------------------------------------
void calc_sth11(float *p_humidity ,float *p_temperature)
//----------------------------------------------------------------------------------------
// calculates temperature [�C] and humidity [%RH] 
// input :  humi [Ticks] (12 bit) 
//          temp [Ticks] (14 bit)
// output:  humi [%RH]
//          temp [�C]
{ 
  const float C1=-4.0;              // for 12 Bit
  const float C2=+0.0405;           // for 12 Bit
  const float C3=-0.0000028;        // for 12 Bit
  const float T1=+0.01;             // for 14 Bit @ 5V
  const float T2=+0.00008;           // for 14 Bit @ 5V	

  float rh=*p_humidity;             // rh:      Humidity [Ticks] 12 Bit 
  float t=*p_temperature;           // t:       Temperature [Ticks] 14 Bit
  float rh_lin;                     // rh_lin:  Humidity linear
  float rh_true;                    // rh_true: Temperature compensated humidity
  float t_C;                        // t_C   :  Temperature [�C]

  t_C=t*0.01 - 40;                  //calc. temperature from ticks to [�C]
  rh_lin=C3*rh*rh + C2*rh + C1;     //calc. humidity from ticks to [%RH]
  rh_true=(t_C-25)*(T1+T2*rh)+rh_lin;   //calc. temperature compensated humidity [%RH]
  if(rh_true>100)rh_true=100;       //cut if the value is outside of
  if(rh_true<0.1)rh_true=0.1;       //the physical possible range

  *p_temperature=t_C;               //return temperature [�C]
  *p_humidity=rh_true;              //return humidity[%RH]
}

//--------------------------------------------------------------------
float calc_dewpoint(float h,float t)
//--------------------------------------------------------------------
// calculates dew point
// input:   humidity [%RH], temperature [�C]
// output:  dew point [�C]
{ 
  float logEx,dew_point;
  logEx=0.66077+7.5*t/(237.3+t)+(log10(h)-2);
  dew_point = (logEx - 0.66077)*237.3/(0.66077+7.5-logEx);
  return dew_point;
}

