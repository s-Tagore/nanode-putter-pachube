/*
 * Light sensor functions
 */

#define SOLARCELLINPUT 0
#define MAXANALOGUEIN  420

int readLight() {
  int cellValue;
  int lightValue;
  
  cellValue = analogRead(SOLARCELLINPUT);
  
  lightValue = map( cellValue, 0, MAXANALOGUEIN, 0, 100 );
//  Serial.print( cellValue, DEC );
//  Serial.print(" ");
//  Serial.println(lightValue, DEC);
 
  return( lightValue );
}

