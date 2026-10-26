#include <WiFi.h>
#include <WebSocketsServer.h>
#include <ESP32Servo.h>
#include <DHT.h>

#define USE_AP 1   // if gusto nyo access point, 1 ang use_ap. if ikokonek sa wifi connection, gawin lang 0
const char* WIFI_SSID = "YOUR_WIFI_NAME";  //dapat 2.4GHz kokonekan. para mas sage wag 5G na phone gamitin
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";


const int L[] = {4, 5, 6, 7, 15};   // 5 LEDs
const int BZ = 16, SV = 17, IR = 8, TR = 10, EC = 11; // BZ=BUZZER, SV=SERVO, TR=TRIG PIN, EC=ECHO PIN
DHT dht(9, DHT11);
Servo sv;
WebSocketsServer ws(81);

bool sec = false;
int lastIr = 0;
unsigned long t = 0, bz = 0;

int br = 70;
bool l0 = false;
void setL0() { analogWrite(L[0], l0 ? map(br, 0, 100, 0, 255) : 0); }

void onEvent(uint8_t n, WStype_t type, uint8_t* p, size_t len) {
  if (type != WStype_TEXT) return;
  String s = String((char*)p).substring(0, len);
  int i = s.indexOf(':');
  if (i < 0) return;
  String k = s.substring(0, i);
  int v = s.substring(i + 1).toInt();
  if (k == "LOCK") sv.write(v ? 0 : 90);
  else if (k == "SEC") sec = v;
  else if (k == "BZ") digitalWrite(BZ, v);
  else if (k == "BR") { br = v; setL0(); }
  else if (k[0] == 'L') {
    int idx = k.substring(1).toInt();
    if (idx == 0) { l0 = v; setL0(); }
    else if (idx > 0 && idx < 5) digitalWrite(L[idx], v);
  }
}

int dist() {
  digitalWrite(TR, LOW); delayMicroseconds(2);
  digitalWrite(TR, HIGH); delayMicroseconds(10);
  digitalWrite(TR, LOW);
  return pulseIn(EC, HIGH, 30000) / 58;
}

void setup() {
  Serial.begin(115200);
  for (int p : L) pinMode(p, OUTPUT);
  pinMode(BZ, OUTPUT); pinMode(IR, INPUT);
  pinMode(TR, OUTPUT); pinMode(EC, INPUT);
  dht.begin();
  sv.attach(SV); sv.write(0);
#if USE_AP
  WiFi.softAP("SmartHome-ESP32", "12345678");
  Serial.print("IP: "); Serial.println(WiFi.softAPIP());  // 192.168.4.1
#else
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.print("IP: "); Serial.println(WiFi.localIP());
#endif
  ws.begin();
  ws.onEvent(onEvent);
}

void loop() {
  ws.loop();

  int m = !digitalRead(IR);         
  if (m != lastIr) {
    lastIr = m;
    ws.broadcastTXT(m ? "IR:1" : "IR:0");
    if (m && sec) { digitalWrite(BZ, 1); bz = millis() + 2000; }
  }
  if (bz && millis() > bz) { digitalWrite(BZ, 0); bz = 0; }

  if (millis() - t > 2000) {
    t = millis();
    float tt = dht.readTemperature(), hh = dht.readHumidity();
    String a = "TEMP:" + String(isnan(tt) ? 0 : (int)tt);
    String b = "HUM:" + String(isnan(hh) ? 0 : (int)hh);
    String c = "DIST:" + String(dist());
    ws.broadcastTXT(a);
    ws.broadcastTXT(b);
    ws.broadcastTXT(c);
  }
}
