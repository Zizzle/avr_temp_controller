#include <OneWire.h>
#include <LiquidCrystal.h>
#include <EEPROM.h>

OneWire  ds(5);  // on pin 10
// initialize the library with the numbers of the interface pins
LiquidCrystal lcd(12, 11, 8, 10, 7, 9, 6);

/* Rotary encoder read example */
#define ENC_A 4
#define ENC_B 3
#define ENC_PORT PIND

#define ENC_SW 1

#define RELAY 2

#define TARGET_XY 0, 11
#define TEMP_XY   1, 11 
#define COMPRESSOR_DELAY 900
#define HYSTERISIS 100

int target = 1800;
byte displayCelcius = 1;
int  since_run;  // seconds since the compressr was last run
byte running = 0;
unsigned long ticks = 0;
byte coolMode = 1;

/* returns change in encoder state (-1,0,1) */
int8_t read_encoder()
{
  int8_t enc_states[] = {
    0,-1,1,0,1,0,0,-1,-1,0,0,1,0,1,-1,0  };
  static uint8_t old_AB = 0;
  old_AB <<= 2;                   //remember previous state
  old_AB |= ( (ENC_PORT >> 3) & 0x03 );  //add current state
  return ( enc_states[( old_AB & 0x0f )]);
}

void delay_update(int ms)
{
  int old = target;
  while (ms--)
  {
    target += read_encoder() * 4;     
    if (target != old)
    {
      old = target;
      display_temperature(TARGET_XY, target, displayCelcius);
      EEPROM.write(0, target >> 8);
      EEPROM.write(1, target & 0xff);
    }     
   
    if ((ENC_PORT & (1 << ENC_SW)) == 0)
    {
      if (coolMode) coolMode = 0;
      else coolMode = 1;
      EEPROM.write(2, coolMode);
    }
    
    delay(1);
  }
}

void setup(void)
{
  pinMode(RELAY, OUTPUT);
  digitalWrite(RELAY, LOW);

  /* Setup encoder pins as inputs */
  pinMode(ENC_A, INPUT);
  digitalWrite(ENC_A, HIGH);
  pinMode(ENC_B, INPUT);
  digitalWrite(ENC_B, HIGH);
  pinMode(ENC_SW, INPUT);
  digitalWrite(ENC_SW, HIGH);

  //  Serial.begin(19200);

  target = EEPROM.read(0);
  target <<= 8;
  target += EEPROM.read(1);
  coolMode = EEPROM.read(2);

  if (target < 100 || target > 6000)
    target = 1800;

  // set up the LCD's number of rows and columns: 
  lcd.begin(16, 2);
  // Print a message to the LCD.
  lcd.print( "    Target ");
}

void display_temperature(byte y, byte x, int temperature, byte celcius)
{
  int Whole, Fract;
  char buf[20];

  if (!celcius)
  {
    temperature = (temperature * 9 / 5) + 3200;
  }

  Whole = temperature / 100;  // separate off the whole and fractional portions
  Fract = temperature % 100;

  sprintf(buf, "%d.%d%c  ",Whole, Fract < 10 ? 0 : Fract/10,  celcius ? 'C' : 'F');

  //  Serial.print(buf);
  lcd.setCursor(x, y);
  lcd.print(buf);  
}

void compressor(byte on)
{
    char buf[20] = "    ";
  if (on)
  {
    if (running || since_run > COMPRESSOR_DELAY)
    {
      digitalWrite(RELAY, HIGH);
      since_run = 0;
      running   = 1;
      strcpy(buf, "on  ");
      lcd.setCursor(0, 0);
      lcd.print(buf);
      return;
    }
    else
    {
      sprintf(buf, "%d ", COMPRESSOR_DELAY - since_run);
    }
  }

  running   = 0;
  since_run++; // keep track of time since last compressor run
  digitalWrite(RELAY, LOW);

  lcd.setCursor(0, 0);
  lcd.print(buf);
}

void heat(byte on)
{
  char buf[20] = "    ";
  if (on)
  {
      digitalWrite(RELAY, HIGH);
      since_run = 0;
      running   = 1;
      strcpy(buf, "on  ");
  }
  else
  {
    running   = 0;
    since_run++; // keep track of time since last compressor run
    digitalWrite(RELAY, LOW);
  }
  lcd.setCursor(0, 0);
  lcd.print(buf);
}


int get_temperature()
{
  byte i;
  int HighByte, LowByte, TReading, SignBit, Tc_100;
  byte data[12];

  ds.reset();
  ds.skip();
  ds.write(0xBE);         // Read Scratchpad

  for ( i = 0; i < 9; i++) {           // we need 9 bytes
    data[i] = ds.read();
  }

  LowByte = data[0];
  HighByte = data[1];
  TReading = (HighByte << 8) + LowByte;
  SignBit = TReading & 0x8000;  // test most sig bit

  if (SignBit) // negative
  {
    TReading = (TReading ^ 0xffff) + 1; // 2's comp
  }

  int mult = 100;

  Tc_100 = data[6]; // remainder
  Tc_100 *= -mult;

  Tc_100 += 16 * mult;
  Tc_100 /= 16;

  Tc_100 -= 25;
  Tc_100 += (TReading >> 1) * mult;

  return Tc_100;
}

void loop(void)
{   
  byte present = 0;

  // The DallasTemperature library can do all this work for you!
  present = ds.reset();
  ds.skip();
  ds.write(0x44,1);         // start conversion, with parasite power on at the end

  lcd.setCursor(0, 1);
  if (!present)
  {
    lcd.print("No sensor      "); 
    return;
  }
  else
  {
    lcd.print(coolMode ? "C" : "H" "  Current ");
  }

  delay_update(1000);     // maybe 750ms is enough, maybe not


  //  Serial.print(" CRC=");
  //  Serial.print( OneWire::crc8( data, 8), HEX);
  //  Serial.println();

  if ((ticks % 3) == 0)
    displayCelcius = !displayCelcius;  // toggle between C and F

  int temp = get_temperature();
  display_temperature(TEMP_XY, temp, displayCelcius);
  display_temperature(TARGET_XY, target, displayCelcius);  

  if (coolMode)
  {
    compressor(temp > target + (running ? -HYSTERISIS : HYSTERISIS));
  }
  else
  {
     heat( temp < target + (running ? HYSTERISIS : -HYSTERISIS));
  }
  ticks++;
}

