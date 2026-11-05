// Servo az/el rotator for Gpredict, Arduino Uno + Hitec HS-311 servos
//
// Speaks the EasyComm II protocol over USB serial at 9600 baud, so Hamlib's
// rotctld can drive it and Gpredict can talk to rotctld.
//
// Wiring:
//   Azimuth servo signal   -> pin 5   (your current test servo)
//   Elevation servo signal -> pin 6   (add later; fine to leave unconnected)
//   Servo red wires        -> power bank +5V
//   Servo black wires      -> Uno GND
//   Power bank black       -> Uno GND
//
// Flip mode: hobby servos only turn about 180 degrees. With FLIP_MODE on,
// azimuths past 180 are reached by turning azimuth to (az - 180) and tilting
// elevation past straight up (180 - el). That covers the whole sky, and
// Gpredict can treat the rotator as a full 0-360 azimuth unit.
//
// Note: don't open the Arduino Serial Monitor while rotctld is running;
// only one program can use the port at a time.

#include <Servo.h>

const int AZ_PIN = 5;
const int EL_PIN = 6;
const bool FLIP_MODE = true;

// Calibrated pulse widths for 0 and 180 degrees on each servo.
int azMinUs = 550;
int azMaxUs = 2350;
int elMinUs = 550;
int elMaxUs = 2350;

const int STEP_US = 10;               // pulse change per step
const unsigned long STEP_MS = 15;     // time between steps (raise to slow down)

Servo azServo;
Servo elServo;

int azUs = 1350, elUs = 1350;         // start slightly off-center so boot is a small move
int azTargetUs = 1350, elTargetUs = 1350;
float reportedAz = 0, reportedEl = 0; // position in Gpredict's terms
unsigned long lastStep = 0;

char buf[64];
int bufLen = 0;

int degToUs(float deg, int minUs, int maxUs) {
  deg = constrain(deg, 0, 180);
  return minUs + (long)((maxUs - minUs) * deg / 180.0);
}

void setPosition(float az, float el) {
  az = fmod(az, 360.0);
  if (az < 0) az += 360.0;
  el = constrain(el, 0, 90);
  reportedAz = az;
  reportedEl = el;

  float servoAz = az;
  float servoEl = el;
  if (FLIP_MODE && az > 180.0) {
    servoAz = az - 180.0;
    servoEl = 180.0 - el;
  } else if (!FLIP_MODE && az > 180.0) {
    servoAz = 180.0;  // can't reach it; go as far as possible
  }

  azTargetUs = degToUs(servoAz, azMinUs, azMaxUs);
  elTargetUs = degToUs(servoEl, elMinUs, elMaxUs);
}

int stepToward(int current, int target) {
  if (abs(target - current) <= STEP_US) return target;
  return current + (target > current ? STEP_US : -STEP_US);
}

// Returns true and sets *value if a number follows the 2-letter tag at p.
bool readNumberAfter(const char *p, float *value) {
  const char *n = p + 2;
  if (isdigit(*n) || *n == '-' || *n == '.' || *n == '+') {
    *value = atof(n);
    return true;
  }
  return false;
}

void handleCommand(char *cmd) {
  char *az = strstr(cmd, "AZ");
  char *el = strstr(cmd, "EL");

  if (az || el) {
    float newAz = reportedAz, newEl = reportedEl;
    bool hasAz = az && readNumberAfter(az, &newAz);
    bool hasEl = el && readNumberAfter(el, &newEl);

    if (hasAz || hasEl) {
      setPosition(newAz, newEl);
    } else {
      // Position query. Hamlib may ask "AZ EL" together, or "AZ" and "EL"
      // separately, so answer only what was asked.
      if (az && el) {
        Serial.print("AZ");
        Serial.print(reportedAz, 1);
        Serial.print(" EL");
        Serial.print(reportedEl, 1);
      } else if (az) {
        Serial.print("AZ");
        Serial.print(reportedAz, 1);
      } else {
        Serial.print("EL");
        Serial.print(reportedEl, 1);
      }
      Serial.print("\n");
    }
  }
  // Other EasyComm commands (stop, version, etc.) are ignored.
}

void setup() {
  Serial.begin(9600);
  azServo.attach(AZ_PIN);
  elServo.attach(EL_PIN);
  azServo.writeMicroseconds(azUs);
  elServo.writeMicroseconds(elUs);

  // Park: azimuth 90, elevation 90 (both servos near center).
  setPosition(90, 90);
}

void loop() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (bufLen > 0) {
        buf[bufLen] = '\0';
        handleCommand(buf);
        bufLen = 0;
      }
    } else if (bufLen < (int)sizeof(buf) - 1) {
      buf[bufLen++] = toupper(c);
    }
  }

  if (millis() - lastStep >= STEP_MS) {
    lastStep = millis();
    azUs = stepToward(azUs, azTargetUs);
    elUs = stepToward(elUs, elTargetUs);
    azServo.writeMicroseconds(azUs);
    elServo.writeMicroseconds(elUs);
  }
}
