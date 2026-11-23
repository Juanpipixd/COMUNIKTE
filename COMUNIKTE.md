# 🏍️ Documentación Técnica del Proyecto: COMUNIKTE
**Sistema de Intercomunicador Bluetooth en Tiempo Real para Motociclistas**

---

## 1. Contexto y Objetivos del Proyecto
* **Propósito:** Aplicación móvil multiplataforma (Android / iOS) que permite a dos motociclistas establecer una comunicación de voz en tiempo real de baja latencia mediante conexión P2P.
* **Integración Bluetooth:** El teléfono se conecta al intercomunicador del casco (micrófono y auriculares).
* **Funcionalidad Clave:** Control de volumen independiente por software para la voz del compañero entrante mediante streaming, **sin alterar ni pausar** la música de fondo (Spotify, YouTube) ni los sonidos del sistema operativo.

---

## 2. Arquitectura de Transmisión y Red (Punto 1)
* **Motor WebRTC:** Se selecciona `flutter_webrtc` por su madurez y rendimiento nativo en C++. Utiliza el códec **Opus** por su excelente rendimiento en voz humana, sample rates adaptativos, jitter buffer y supresión de eco integrada (AEC).
* **Mecanismo de Conexión:**
  * **P2P Directo (STUN/ICE):** Latencia típica de 30 ms a 80 ms usando servidores STUN públicos (ej. Google STUN).
  * **Fallback / Redes Inestables:** Preparado para conmutación a TURN o redes locales (Wi-Fi Direct / Hotspot) en zonas sin cobertura celular.

---

## 3. Audio Routing Nativo y Bluetooth SCO (Punto 1.2)
* **Audio Focus (Android/iOS):** Configuración del pipeline de audio en modo comunicación (`USAG_VOICE_COMMUNICATION` / `AVAudioSessionCategoryPlayAndRecord` con las opciones `.mixWithOthers` y `.allowBluetooth`) para lograr el modo *Duck/Mix* (la voz se mezcla encima de la música bajándole volumen en vez de pausarla).
* **Canal Bluetooth SCO/HFP:** Activación explícita del perfil de manos libres (Hands-Free Profile) para capturar el audio bidireccional desde el micrófono del casco.

---

## 4. Control Independiente de Volumen (Software Gain - Punto 1.3)
* **Lógica:** No se modifica el volumen general del hardware del dispositivo.
* **Implementación:** Se aplica una ganancia de software directamente sobre el objeto `MediaStreamTrack` de la voz remota (en un rango de `0.0` a `2.0`), ajustando la amplitud PCM antes de enviarla al mezclador de salida del casco.

---

## 5. Arquitectura de Módulos y Estructura de Carpetas (Clean Architecture)

```text
lib/
├── main.dart
├── core/
│   ├── audio/
│   │   ├── audio_routing_service.dart   # Manejo de Bluetooth SCO / AVAudioSession
│   │   └── gain_controller.dart        # Control de volumen por software (Software Gain)
│   ├── network/
│   │   └── signaling_service.dart      # Conexión WebSocket / Firebase para SDP/ICE
│   └── theme/
│       └── hud_theme.dart              # Estilos UI de alto contraste y botones grandes
├── features/
│   ├── connection/
│   │   ├── presentation/
│   │   │   ├── qr_scanner_screen.dart
│   │   │   └── room_entry_screen.dart
│   └── intercom/
│       ├── presentation/
│       │   ├── intercom_hud_screen.dart
│       │   └── widgets/
│       │       ├── volume_slider.dart
│       │       └── connection_badge.dart
│       └── domain/
│           └── webrtc_intercom_engine.dart # Orquestador de MediaStream y PeerConnection