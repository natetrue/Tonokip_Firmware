// PLEASE VERIFY PIN ASSIGNMENTS FOR YOUR CONFIGURATION!!!!!!!

// THERMOCOUPLE SUPPORT UNTESTED... USE WITH CAUTION!!!!
const bool USE_THERMISTOR = true; //Set to false if using thermocouple
//If using thermocouple with RAMPS you cannot use the t0 and t1 labeled headers, you need to use an empty analog pin.

// Calibration formulas
// e_extruded_steps_per_mm = e_feedstock_steps_per_mm * (desired_extrusion_diameter^2 / feedstock_diameter^2)
// new_axis_steps_per_mm = previous_axis_steps_per_mm * (test_distance_instructed/test_distance_traveled)
// units are in millimeters or whatever length unit you prefer: inches,football-fields,parsecs etc

//Calibration variables
float x_steps_per_unit = 64;	//64 for 10 tooth 5mm pulleys
float y_steps_per_unit = 64;	
float z_steps_per_unit = 3072;	
float e_steps_per_unit = 17.6;	//17.6 for adrians 36.65 for MakerGear extruder    What is wades?
float max_feedrate = 18000;

//For Inverting Stepper Enable Pins (Active Low) use 0, Non Inverting (Active High) use 1
const bool X_ENABLE_ON = 0;
const bool Y_ENABLE_ON = 0;
const bool Z_ENABLE_ON = 0;
const bool E_ENABLE_ON = 0;

//Disables axis when it's not being used. Z is the only one recommended to disable.
const bool DISABLE_X = false;
const bool DISABLE_Y = false;
const bool DISABLE_Z = true;
const bool DISABLE_E = false;

const bool INVERT_X_DIR = false;
const bool INVERT_Y_DIR = false;
const bool INVERT_Z_DIR = true;
const bool INVERT_E_DIR = false;

//Endstop Settings
	//if you do not have max hardware endstops, it defaults to software endstops, defined by the max length numbers.
	//if you do not have min hardware endstops, the firmware will not move to lengths less than 0
const bool ENDSTOPS_INVERTING = true;
const bool x_max_hardware = false;
const bool x_min_hardware = true;
const int X_MAX_LENGTH = 212;
const bool y_max_hardware = false;
const bool y_min_hardware = true;
const int Y_MAX_LENGTH = 205;
const bool z_max_hardware = false;
const bool z_min_hardware = true;
const int Z_MAX_LENGTH = 70;


//Chamber Settings
const bool servo_inverting = true; //Inverts the servo direction (PWM value)
const int chamber_check = 1000; //This defines how many times we need to check the extruder temp before we check the chamber temp 

#define BAUDRATE 115200

