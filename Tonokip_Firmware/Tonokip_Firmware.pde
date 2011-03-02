// Tonokip RepRap firmware rewrite based off of Hydra-mmm firmware.
// Licence: GPL

#include "configuration.h"
#include "pins.h"
#include "ThermistorTable.h"

// look here for descriptions of gcodes: http://linuxcnc.org/handbook/gcode/g-code.html
// http://objects.reprap.org/wiki/Mendel_User_Manual:_RepRapGCodes

//Implemented Codes
//-------------------
// G0 -> G1
// G1  - Coordinated Movement X Y Z E
// G4  - Dwell S<seconds> or P<milliseconds>
// G90 - Use Absolute Coordinates
// G91 - Use Relative Coordinates
// G92 - Set current position to cordinates given

//RepRap M Codes
// M104 - Set target temp
// M105 - Read current temp
// M106 - Fan on
// M107 - Fan off
// M109 - Wait for nozzle current temp to reach target temp.
// M112 - Emergency Stop
// M114 - Get Current Position	
// M115 - Get Firmware Version and Capabilities		
// M116 - Wait for nozzle AND Bed to get up to target temp     
// M140 - Set heated bed temp
// M141 - Set chamber temp		**Still working on this one.

//Custom M Codes
// M80  - Turn on Power Supply
// M81  - Turn off Power Supply
// M82  - Set E codes absolute (default)
// M83  - Set E codes relative while in Absolute Coordinates (G90) mode
// M84  - Disable steppers until next move
// M85  - Set inactivity shutdown timer with parameter S<seconds>. To disable set zero (default)
// M92  - Set axis_steps_per_unit - same syntax as G92

//Stepper Movement Variables
bool direction_x, direction_y, direction_z, direction_e;
unsigned long previous_micros=0, previous_micros_x=0, previous_micros_y=0, previous_micros_z=0, previous_micros_e=0, previous_millis_heater, previous_millis_bed_heater;
unsigned long x_steps_to_take, y_steps_to_take, z_steps_to_take, e_steps_to_take;
float destination_x =0.0, destination_y = 0.0, destination_z = 0.0, destination_e = 0.0;
float current_x = 0.0, current_y = 0.0, current_z = 0.0, current_e = 0.0;		//migrate this to steps rather than units
float x_interval, y_interval, z_interval, e_interval; // for speed delay
float feedrate = 3000, next_feedrate;
float time_for_move;
long gcode_N, gcode_LastN;
bool relative_mode = false;  //Determines Absolute or Relative Coordinates
bool relative_mode_e = false;  //Determines Absolute or Relative E Codes while in Absolute Coordinates mode. E is always relative in Relative Coordinates mode.

// comm variables
#define MAX_CMD_SIZE 256
char cmdbuffer[MAX_CMD_SIZE];
char serial_char;
int serial_count = 0;
boolean comment_mode = false;
char *strchr_pointer; // just a pointer to find chars in the cmd string like X, Y, Z, E, etc

//manage heater variables
int nozzle_target_raw = 0;
int nozzle_current_raw;
int bed_target_raw = 0;
int bed_current_raw;
//int chamber_target_raw = 0;
//int chamber_current_raw;

//Inactivity shutdown variables
unsigned long previous_millis_cmd=0;
unsigned long max_inactive_time = 0;

void setup()
{ 

 //Steppers default to disabled.
  if(X_ENABLE_PIN > -1) if(!X_ENABLE_ON) digitalWrite(X_ENABLE_PIN,HIGH);
  if(Y_ENABLE_PIN > -1) if(!Y_ENABLE_ON) digitalWrite(Y_ENABLE_PIN,HIGH);
  if(Z_ENABLE_PIN > -1) if(!Z_ENABLE_ON) digitalWrite(Z_ENABLE_PIN,HIGH);
  if(E_ENABLE_PIN > -1) if(!E_ENABLE_ON) digitalWrite(E_ENABLE_PIN,HIGH);

  //Initialize Enable Pins
  if(X_ENABLE_PIN > -1) pinMode(X_ENABLE_PIN,OUTPUT);
  if(Y_ENABLE_PIN > -1) pinMode(Y_ENABLE_PIN,OUTPUT);
  if(Z_ENABLE_PIN > -1) pinMode(Z_ENABLE_PIN,OUTPUT);
  if(E_ENABLE_PIN > -1) pinMode(E_ENABLE_PIN,OUTPUT);

  //Initialize Step Pins
  if(X_STEP_PIN > -1) pinMode(X_STEP_PIN,OUTPUT);
  if(Y_STEP_PIN > -1) pinMode(Y_STEP_PIN,OUTPUT);
  if(Z_STEP_PIN > -1) pinMode(Z_STEP_PIN,OUTPUT);
  if(E_STEP_PIN > -1) pinMode(E_STEP_PIN,OUTPUT);
  
  //Initialize Dir Pins
  if(X_DIR_PIN > -1) pinMode(X_DIR_PIN,OUTPUT);
  if(Y_DIR_PIN > -1) pinMode(Y_DIR_PIN,OUTPUT);
  if(Z_DIR_PIN > -1) pinMode(Z_DIR_PIN,OUTPUT);
  if(E_DIR_PIN > -1) pinMode(E_DIR_PIN,OUTPUT);

  if(HEATER_0_PIN > -1) pinMode(HEATER_0_PIN,OUTPUT);
  if(BED_HEATER_0_PIN > -1) pinMode(BED_HEATER_0_PIN,OUTPUT);
#ifdef USE_INTERNAL_PULLUPS
        pinMode(Y_MIN_PIN ,INPUT);
        digitalWrite(Y_MIN_PIN, HIGH); 
        pinMode(X_MIN_PIN ,INPUT);
        digitalWrite(X_MIN_PIN, HIGH); 
        pinMode(Z_MIN_PIN ,INPUT);
        digitalWrite(Z_MIN_PIN, HIGH); 
#endif
  	Serial.begin(BAUDRATE);
#ifdef SENDSTART 
	Serial.println("start");
#endif
}

inline void manage_heaters() {
  if( (millis() - previous_millis_heater) >= nozzle_check ) {
      manage_heater();
      previous_millis_heater = millis();
    }
    if( (millis() - previous_millis_bed_heater) >= hbp_check ) {
      manage_bed_heater();
      previous_millis_bed_heater = millis();
    }
}

void loop()
{
  get_command();
  manage_heaters();
}

inline void get_command() 
{ 

  if( Serial.available() > 0 ) {
    serial_char = Serial.read();
    if (serial_char >= 'a' && serial_char <= 'z') serial_char -= ('a' - 'A'); // make all commands upercase
    if(serial_char == '\n' || serial_char == '\r' || serial_char == ':' || serial_count >= (MAX_CMD_SIZE - 1) ) 
    {
      if(!serial_count) return; //if empty line
      cmdbuffer[serial_count] = 0; //terminate string
#ifdef ECHOING      
      Serial.print("Echo:");
      Serial.println(&cmdbuffer[0]);
#endif
      process_commands();
      
      comment_mode = false; //for new command
      serial_count = 0; //clear buffer
      //Serial.println("ok"); 
    }
    else
    {
      if(serial_char == ';') comment_mode = true;
      if(!comment_mode) cmdbuffer[serial_count++] = serial_char; 
    }
  }  
}


//#define code_num (strtod(&cmdbuffer[strchr_pointer - cmdbuffer + 1], NULL))
//inline void code_search(char code) { strchr_pointer = strchr(cmdbuffer, code); }
inline float code_value() { return (strtod(&cmdbuffer[strchr_pointer - cmdbuffer + 1], NULL)); }
inline long code_value_long() { return (strtol(&cmdbuffer[strchr_pointer - cmdbuffer + 1], NULL, 10)); }
inline bool code_seen(char code_string[]) { return (strstr(cmdbuffer, code_string) != NULL); }  //Return True if the string was found

inline bool code_seen(char code)
{
  strchr_pointer = strchr(cmdbuffer, code);
  return (strchr_pointer != NULL);  //Return True if a character was found
}



inline void process_commands()
{
    unsigned long codenum; //throw away variable
#ifdef LINENUM
  
  
  if(code_seen('N'))
  {
    gcode_N = code_value_long();
    if(gcode_N != gcode_LastN+1 && (strstr(cmdbuffer, "M110") == NULL) ) {
    //if(gcode_N != gcode_LastN+1 && !code_seen("M110") ) {   //Hmm, compile size is different between using this vs the line above even though it should be the same thing. Keeping old method.
      Serial.print("Serial Error: Line Number is not Last Line Number+1, Last Line:");
      Serial.println(gcode_LastN);
      FlushSerialRequestResend();
      return;
    }
#endif
#ifdef CHECKSUM
    if(code_seen('*'))
    {
      byte checksum = 0;
      byte count=0;
      while(cmdbuffer[count] != '*') checksum = checksum^cmdbuffer[count++];
     
      if( (int)code_value() != checksum) {
        Serial.print("Error: checksum mismatch, Last Line:");
        Serial.println(gcode_LastN);
        FlushSerialRequestResend();
        return;
      }
      //if no errors, continue parsing
    }
    else 
    {
      Serial.print("Error: No Checksum with line number, Last Line:");
      Serial.println(gcode_LastN);
      FlushSerialRequestResend();
      return;
    }
    
    gcode_LastN = gcode_N;
    //if no errors, continue parsing
  }
  else  // if we don't receive 'N' but still see '*'
  {
    if(code_seen('*'))
    {
      Serial.print("Error: No Line Number with checksum, Last Line:");
      Serial.println(gcode_LastN);
      return;
    }
  }
#endif

  //continues parsing only if we don't receive any 'N' or '*' or no errors if we do. :)
  
  if(code_seen('G'))
  {
    switch((int)code_value())
    {
      case 0: // G0 -> G1
      case 1: // G1
        get_coordinates(); // For X Y Z E F
        x_steps_to_take = abs(destination_x - current_x)*x_steps_per_unit;
        y_steps_to_take = abs(destination_y - current_y)*y_steps_per_unit;
        z_steps_to_take = abs(destination_z - current_z)*z_steps_per_unit;
        e_steps_to_take = abs(destination_e - current_e)*e_steps_per_unit;

        #define X_TIME_FOR_MOVE ((float)x_steps_to_take / (x_steps_per_unit*feedrate/60000000))
        #define Y_TIME_FOR_MOVE ((float)y_steps_to_take / (y_steps_per_unit*feedrate/60000000))
        #define Z_TIME_FOR_MOVE ((float)z_steps_to_take / (z_steps_per_unit*feedrate/60000000))
        #define E_TIME_FOR_MOVE ((float)e_steps_to_take / (e_steps_per_unit*feedrate/60000000))
        
        time_for_move = max(X_TIME_FOR_MOVE,Y_TIME_FOR_MOVE);
        time_for_move = max(time_for_move,Z_TIME_FOR_MOVE);
        time_for_move = max(time_for_move,E_TIME_FOR_MOVE);

        if(x_steps_to_take) x_interval = time_for_move/x_steps_to_take;
        if(y_steps_to_take) y_interval = time_for_move/y_steps_to_take;
        if(z_steps_to_take) z_interval = time_for_move/z_steps_to_take;
        if(e_steps_to_take) e_interval = time_for_move/e_steps_to_take;
        
        linear_move(x_steps_to_take, y_steps_to_take, z_steps_to_take, e_steps_to_take); // make the move
        ClearToSend();
        return;
      case 4: // G4 dwell
        codenum = 0;
        if(code_seen('P')) codenum = code_value(); // milliseconds to wait
        if(code_seen('S')) codenum = code_value()*1000; // seconds to wait
        previous_millis_heater = millis(); // keep track of when we started waiting
        while((millis() - previous_millis_heater) < codenum )
		{ manage_heaters();
		}
        break;
      case 90: // G90
        relative_mode = false;
        break;
      case 91: // G91
        relative_mode = true;
        break;
      case 92: // G92
        if(code_seen('X')) current_x = code_value();
        if(code_seen('Y')) current_y = code_value();
        if(code_seen('Z')) current_z = code_value();
        if(code_seen('E')) current_e = code_value();
        break;
        
    }
  }

  if(code_seen('M'))
  {
    
    switch( (int)code_value() ) 
    {
      case 104: // M104
        if (code_seen('S')) nozzle_target_raw = temp2analog(code_value());
        break;
      case 105: // M105
        Serial.print("OK T:");
        Serial.print( analog2temp(analogRead(TEMP_0_PIN)) ); 
	Serial.print(" B:");
        Serial.println( analog2temp(analogRead(BED_TEMP_0_PIN)) );
        //if(!code_seen('N')) return;  // If M105 is sent from generated gcode, then it needs a response.
        break;
      case 109: // M109 - Wait for heater to reach target.
        if (code_seen('S')) nozzle_target_raw = temp2analog(code_value());
        previous_millis_heater = millis(); 
        while(nozzle_current_raw < nozzle_target_raw) {
          if( (millis()-previous_millis_heater) > 1000 ) //Print Temp Reading every 1 second while heating up.
          {
            Serial.print("T:");
            Serial.println( analog2temp(analogRead(TEMP_0_PIN)) ); 
            previous_millis_heater = millis(); 
          }
          manage_heater();
	  manage_bed_heater();
        }
        break;
	case 112: // M112 - Emergency Stop
        kill(5);
        break;
	case 116: // M116 - Wait for heater and bed to reach target.
        while(nozzle_current_raw < nozzle_target_raw || bed_current_raw < bed_target_raw) {
          if( (millis()-previous_millis_heater) > 1000 ) //Print Temp Reading every 1 second while heating up.
          {
            Serial.print("T:");
            Serial.print( analog2temp(analogRead(TEMP_0_PIN)) );  
	    Serial.print("B:");
            Serial.println( analog2temp(analogRead(BED_TEMP_0_PIN)) ); 
            previous_millis_heater = millis(); 
          }
          manage_heater();
	  manage_bed_heater();
        }
        break;
	case 140: // M140
        if (code_seen('S')) bed_target_raw = temp2analog(code_value());
        break;
	//case 140: // M141
       // if (code_seen('S')) chamber_target_raw = temp2analog(code_value());
	//manage_chamber();
       // break;
      case 106: //M106 - Fan On
        digitalWrite(FAN_PIN, HIGH);
        break;
      case 107: //M107 - Fan Off
        digitalWrite(FAN_PIN, LOW);
        break;
      case 80: // M81 - ATX Power On
        if(PS_ON_PIN > -1) pinMode(PS_ON_PIN,OUTPUT); //GND
        break;
      case 81: // M81 - ATX Power Off
        if(PS_ON_PIN > -1) pinMode(PS_ON_PIN,INPUT); //Floating
        break;
      case 82:
        relative_mode_e = false;
        break;
      case 83:
        relative_mode_e = true;
        break;
      case 84:
        disable_x();
        disable_y();
        disable_z();
        disable_e();
        break;
      case 85: // M85
        code_seen('S');
        max_inactive_time = code_value()*1000; 
        break;
      case 92: // M92
        if(code_seen('X')) x_steps_per_unit = code_value();
        if(code_seen('Y')) y_steps_per_unit = code_value();
        if(code_seen('Z')) z_steps_per_unit = code_value();
        if(code_seen('E')) e_steps_per_unit = code_value();
        break;
 	case 114: // M114
	Serial.print("X:");
        Serial.print(current_x);
	Serial.print("Y:");
        Serial.print(current_y);
	Serial.print("Z:");
        Serial.print(current_z);
	Serial.print("E:");
        Serial.println(current_e);
        break;
	 case 115: // M115
        Serial.println("Tonokip Firmware");
        break;
        case 999: //M999
        Serial.print("Y Min: ");
        Serial.println(digitalRead(Y_MIN_PIN));
        Serial.print("X Min: ");
        Serial.println(digitalRead(X_MIN_PIN));
        break;
    }
    
  }
  
  ClearToSend();
}

inline void FlushSerialRequestResend()
{
  char cmdbuffer[100]="Resend:";
  ltoa(gcode_LastN+1, cmdbuffer+7, 10);
  Serial.flush();
  Serial.println(cmdbuffer);
  ClearToSend();
}

inline void ClearToSend()
{
  previous_millis_cmd = millis();
  Serial.println("ok"); 
}

inline void get_coordinates()
{
  if(code_seen('X')) destination_x = (float)code_value() + relative_mode*current_x;
  else destination_x = current_x;                                                       //Are these else lines really needed?
  if(code_seen('Y')) destination_y = (float)code_value() + relative_mode*current_y;
  else destination_y = current_y;
  if(code_seen('Z')) destination_z = (float)code_value() + relative_mode*current_z;
  else destination_z = current_z;
  if(code_seen('E')) destination_e = (float)code_value() + (relative_mode_e || relative_mode)*current_e;
  else destination_e = current_e;
  if(code_seen('F')) {
    next_feedrate = code_value();
    if(next_feedrate > 0.0) feedrate = next_feedrate;
  }
  
  //Find direction
  if(destination_x >= current_x) direction_x=1;
  else direction_x=0;
  if(destination_y >= current_y) direction_y=1;
  else direction_y=0;
  if(destination_z >= current_z) direction_z=1;
  else direction_z=0;
  if(destination_e >= current_e) direction_e=1;
  else direction_e=0;
  
  
  if(!x_min_hardware) if (destination_x < X_MIN) destination_x = X_MIN;
  if(!y_min_hardware) if (destination_y < Y_MIN) destination_y = Y_MIN;
  if(!z_min_hardware) if (destination_z < Z_MIN) destination_z = Z_MIN;

  if(!x_max_hardware) if (destination_x > X_MAX) destination_x = X_MAX;
  if(!y_max_hardware) if (destination_y > Y_MAX) destination_y = Y_MAX;
  if(!z_max_hardware) if (destination_z > Z_MAX) destination_z = Z_MAX;
  
  if(feedrate > max_feedrate) feedrate = max_feedrate;
}

void linear_move(unsigned long x_steps_remaining, unsigned long y_steps_remaining, unsigned long z_steps_remaining, unsigned long e_steps_remaining) // make linear move with preset speeds and destinations, see G0 and G1
{
  //Determine direction of movement
  if (destination_x > current_x) digitalWrite(X_DIR_PIN,!INVERT_X_DIR);
  else digitalWrite(X_DIR_PIN,INVERT_X_DIR);
  if (destination_y > current_y) digitalWrite(Y_DIR_PIN,!INVERT_Y_DIR);
  else digitalWrite(Y_DIR_PIN,INVERT_Y_DIR);
  if (destination_z > current_z) digitalWrite(Z_DIR_PIN,!INVERT_Z_DIR);
  else digitalWrite(Z_DIR_PIN,INVERT_Z_DIR);
  if (destination_e > current_e) digitalWrite(E_DIR_PIN,!INVERT_E_DIR);
  else digitalWrite(E_DIR_PIN,INVERT_E_DIR);
  
  //Only enable axis that are moving. If the axis doesn't need to move then it can stay disabled depending on configuration.
  if(x_steps_remaining) enable_x();
  if(y_steps_remaining) enable_y();
  if(z_steps_remaining) enable_z();
  if(e_steps_remaining) enable_e();

  if(x_min_hardware) if(X_MIN_PIN > -1) if(!direction_x) if(digitalRead(X_MIN_PIN) != ENDSTOPS_INVERTING) x_steps_remaining=0;
  if(y_min_hardware) if(Y_MIN_PIN > -1) if(!direction_y) if(digitalRead(Y_MIN_PIN) != ENDSTOPS_INVERTING) y_steps_remaining=0;
  if(z_min_hardware) if(Z_MIN_PIN > -1) if(!direction_z) if(digitalRead(Z_MIN_PIN) != ENDSTOPS_INVERTING) z_steps_remaining=0;
  if(x_max_hardware) if(X_MAX_PIN > -1) if(direction_x) if(digitalRead(X_MAX_PIN) != ENDSTOPS_INVERTING) x_steps_remaining=0;
  if(y_max_hardware) if(Y_MAX_PIN > -1) if(direction_y) if(digitalRead(Y_MAX_PIN) != ENDSTOPS_INVERTING) y_steps_remaining=0;
  if(z_max_hardware) if(Z_MAX_PIN > -1) if(direction_z) if(digitalRead(Z_MAX_PIN) != ENDSTOPS_INVERTING) z_steps_remaining=0;

  while(x_steps_remaining > 0 || y_steps_remaining > 0 || z_steps_remaining > 0 || e_steps_remaining > 0) // move until no more steps remain 
	//SK 2010.12.25 - The above compiled 2 bytes smaller. I wonder why it was commented out?
  //while(x_steps_remaining + y_steps_remaining + z_steps_remaining + e_steps_remaining > 0) // move until no more steps remain
  { 
    if(x_steps_remaining) {
      if ((micros()-previous_micros_x) >= x_interval) { do_x_step(); x_steps_remaining--; }
      if(x_min_hardware) if(X_MIN_PIN > -1) if(!direction_x) if(digitalRead(X_MIN_PIN) != ENDSTOPS_INVERTING) x_steps_remaining=0;
      if(x_max_hardware) if(X_MAX_PIN > -1) if(direction_x) if(digitalRead(X_MAX_PIN) != ENDSTOPS_INVERTING) x_steps_remaining=0;
    }
    
    if(y_steps_remaining) {
      if ((micros()-previous_micros_y) >= y_interval) { do_y_step(); y_steps_remaining--; }
      if(y_min_hardware) if(Y_MIN_PIN > -1) if(!direction_y) if(digitalRead(Y_MIN_PIN) != ENDSTOPS_INVERTING) y_steps_remaining=0;
      if(y_max_hardware) if(Y_MAX_PIN > -1) if(direction_y) if(digitalRead(Y_MAX_PIN) != ENDSTOPS_INVERTING) y_steps_remaining=0;
    }
    
    if(z_steps_remaining) {
      if ((micros()-previous_micros_z) >= z_interval) { do_z_step(); z_steps_remaining--; }
      if(z_min_hardware) if(Z_MIN_PIN > -1) if(!direction_z) if(digitalRead(Z_MIN_PIN) != ENDSTOPS_INVERTING) z_steps_remaining=0;
      if(z_max_hardware) if(Z_MAX_PIN > -1) if(direction_z) if(digitalRead(Z_MAX_PIN) != ENDSTOPS_INVERTING) z_steps_remaining=0;
    }    
    
    if(e_steps_remaining) if ((micros()-previous_micros_e) >= e_interval) { do_e_step(); e_steps_remaining--; }
    
    manage_heaters();
  }
  
  if(DISABLE_X) disable_x();
  if(DISABLE_Y) disable_y();
  if(DISABLE_Z) disable_z();
  if(DISABLE_E) disable_e();
  
  // Update current position partly based on direction, we probably can combine this with the direction code above...
  if (destination_x > current_x) current_x = current_x + x_steps_to_take/x_steps_per_unit;
  else current_x = current_x - x_steps_to_take/x_steps_per_unit;
  if (destination_y > current_y) current_y = current_y + y_steps_to_take/y_steps_per_unit;
  else current_y = current_y - y_steps_to_take/y_steps_per_unit;
  if (destination_z > current_z) current_z = current_z + z_steps_to_take/z_steps_per_unit;
  else current_z = current_z - z_steps_to_take/z_steps_per_unit;
  if (destination_e > current_e) current_e = current_e + e_steps_to_take/e_steps_per_unit;
  else current_e = current_e - e_steps_to_take/e_steps_per_unit;
}


inline void do_x_step()
{
  digitalWrite(X_STEP_PIN, HIGH);
  previous_micros_x = micros();
  digitalWrite(X_STEP_PIN, LOW);
}

inline void do_y_step()
{
  digitalWrite(Y_STEP_PIN, HIGH);
  previous_micros_y = micros();
  digitalWrite(Y_STEP_PIN, LOW);
}

inline void do_z_step()
{
  digitalWrite(Z_STEP_PIN, HIGH);
  previous_micros_z = micros();
  digitalWrite(Z_STEP_PIN, LOW);
}

inline void do_e_step()
{
  digitalWrite(E_STEP_PIN, HIGH);
  previous_micros_e = micros();
  digitalWrite(E_STEP_PIN, LOW);
}

inline void disable_x() { if(X_ENABLE_PIN > -1) digitalWrite(X_ENABLE_PIN,!X_ENABLE_ON); }
inline void disable_y() { if(Y_ENABLE_PIN > -1) digitalWrite(Y_ENABLE_PIN,!Y_ENABLE_ON); }
inline void disable_z() { if(Z_ENABLE_PIN > -1) digitalWrite(Z_ENABLE_PIN,!Z_ENABLE_ON); }
inline void disable_e() { if(E_ENABLE_PIN > -1) digitalWrite(E_ENABLE_PIN,!E_ENABLE_ON); }
inline void  enable_x() { if(X_ENABLE_PIN > -1) digitalWrite(X_ENABLE_PIN, X_ENABLE_ON); }
inline void  enable_y() { if(Y_ENABLE_PIN > -1) digitalWrite(Y_ENABLE_PIN, Y_ENABLE_ON); }
inline void  enable_z() { if(Z_ENABLE_PIN > -1) digitalWrite(Z_ENABLE_PIN, Z_ENABLE_ON); }
inline void  enable_e() { if(E_ENABLE_PIN > -1) digitalWrite(E_ENABLE_PIN, E_ENABLE_ON); }

/*
// From Bill2or3 http://protovision.com/2010/09/16/temperature-control-matters/
if (target_raw <= 50) {
analogWrite(HEATER_0_PIN,HEATER_0_OFF);
} else {
if(current_raw >= target_raw) {
analogWrite(HEATER_0_PIN,HEATER_0_LOW);
} else {
analogWrite(HEATER_0_PIN, HEATER_0_HIGH);
}
*/

inline void manage_heater()
{
  nozzle_current_raw = analogRead(TEMP_0_PIN);                  // If using thermistor, when the heater is colder than targer temp, we get a higher analog reading than target, 
  if(USE_THERMISTOR) nozzle_current_raw = 1023 - nozzle_current_raw;   // this switches it up so that the reading appears lower than target for the control logic.
  
  if(nozzle_current_raw >= nozzle_target_raw) digitalWrite(HEATER_0_PIN, LOW);
  else digitalWrite(HEATER_0_PIN, HIGH);

#ifdef PWM_NOZZLE
	//	if (target_raw <= 50) {
	//	analogWrite(HEATER_0_PIN,HEATER_0_OFF);
	//	} else {
	//	if(current_raw >= target_raw) {
//	analogWrite(HEATER_0_PIN,HEATER_0_LOW);
//	} else {
//	analogWrite(HEATER_0_PIN, HEATER_0_HIGH);
#endif
}

inline void manage_bed_heater()
{
  bed_current_raw = analogRead(BED_TEMP_0_PIN);                  // If using thermistor, when the heater is colder than targer temp, we get a higher analog reading than target, 
  if(USE_THERMISTOR) bed_current_raw = 1023 - bed_current_raw;   // this switches it up so that the reading appears lower than target for the control logic.
  
  if(bed_current_raw >= bed_target_raw) digitalWrite(BED_HEATER_0_PIN, LOW);
  else digitalWrite(BED_HEATER_0_PIN, HIGH);
}
/*
inline void manage_chamber()
{
  chamber_current_raw = analogRead(CHAMBER_TEMP_PIN);                  // If using thermistor, when the heater is colder than targer temp, we get a higher analog reading than target, 
  if(USE_THERMISTOR) chamber_current_raw = 1023 - chamber_current_raw;   // this switches it up so that the reading appears lower than target for the control logic.
  
  if(chamber_current_raw >= chamber_target_raw){
	 digitalWrite(EXHAUST_FAN_PIN, LOW);
		}
  else digitalWrite(EXHAUST_FAN_PIN, HIGH);
}
*/


// Takes temperature value as input and returns corresponding analog value from RepRap thermistor temp table.
// This is needed because PID in hydra firmware hovers around a given analog value, not a temp value.
// This function is derived from inversing the logic from a portion of getTemperature() in FiveD RepRap firmware.
float temp2analog(int celsius) {
  if(USE_THERMISTOR) {
    int raw = 0;
    byte i;
    
    for (i=1; i<NUMTEMPS; i++)
    {
      if (temptable[i][1] < celsius)
      {
        raw = temptable[i-1][0] + 
          (celsius - temptable[i-1][1]) * 
          (temptable[i][0] - temptable[i-1][0]) /
          (temptable[i][1] - temptable[i-1][1]);
      
        break;
      }
    }

    // Overflow: Set to last value in the table
    if (i == NUMTEMPS) raw = temptable[i-1][0];

    return 1023 - raw;
  } else {
    return celsius * (1024.0/(5.0*100.0));
  }
}

// Derived from RepRap FiveD extruder::getTemperature()
float analog2temp(int raw) {
  if(USE_THERMISTOR) {
    int celsius = 0;
    byte i;

    for (i=1; i < NUMTEMPS; i++)
    {
      if (temptable[i][0] > raw)
      {
        celsius  = temptable[i-1][1] + 
          (raw - temptable[i-1][0]) * 
          (temptable[i][1] - temptable[i-1][1]) /
          (temptable[i][0] - temptable[i-1][0]);

        break;
      }
    }

    // Overflow: Set to last value in the table
    if (i == NUMTEMPS) celsius = temptable[i-1][1];

    return celsius;
    
  } else {
    return raw * ((5.0*100.0)/1024.0);
  }
}

inline void kill(byte debug)
{
  if(HEATER_0_PIN > -1) digitalWrite(HEATER_0_PIN,LOW);
  if(BED_HEATER_0_PIN > -1) digitalWrite(BED_HEATER_0_PIN,LOW);
  disable_x;
  disable_y;
  disable_z;
  disable_e;
  
  if(PS_ON_PIN > -1) pinMode(PS_ON_PIN,INPUT);

    switch(debug)
    {
      case 1: Serial.print("Inactivity Shutdown, Last Line: "); break;
      case 2: Serial.print("Linear Move Abort, Last Line: "); break;
      case 3: Serial.print("Homing X Min Stop Fail, Last Line: "); break;
      case 4: Serial.print("Homing Y Min Stop Fail, Last Line: "); break;
      case 5: Serial.print("User terminated, Last Line: "); break;
    } 
    Serial.println(gcode_LastN);

}

//inline void manage_inactivity(byte debug) { 
//	if( (millis()-previous_millis_cmd) >  max_inactive_time ) if(max_inactive_time) kill(debug); 
//		}
